# frozen_string_literal: true

module Autofacts
  # Read-through client: checks the local database before fetching, so data we
  # already have is never requested again. Pass `force: true` to bypass.
  #
  # The database is an implementation detail: it defaults to
  # `Autofacts.database_path` and is seeded by `autofacts install`.
  class Client
    def initialize(database: nil, source: nil, base_url: Autofacts::BASE_URL, brand_config_path: "config/brands.yml")
      database ||= Autofacts.database_path
      @database = database.is_a?(Database) ? database : Database.new(database)
      @source = source || Source::HttpSource.new(base_url: base_url)
      @repository = Repository.new(@database.db)
      @brand_config = BrandConfig.load(brand_config_path)
    end

    # === SEEDED DATA (read from the local catalog) ===

    # Part brands seeded at install time.
    def brands
      repository.part_brands
    end

    def categories(locale: nil)
      repository.categories(locale: locale)
    end

    def subcategories(category_slug: nil, locale: nil)
      repository.subcategories(category_slug: category_slug, locale: locale)
    end

    def countries
      repository.countries
    end

    # Full-text search seeded brands by name or slug.
    def search_brands(term)
      repository.search_brands(term)
    end

    # Full-text search seeded categories by name, slug, translation or alias.
    def search_categories(term, locale: nil)
      repository.search_categories(term, locale: locale)
    end

    # Full-text search seeded subcategories by name, slug, translation or alias.
    def search_subcategories(term, locale: nil)
      repository.search_subcategories(term, locale: locale)
    end

    # === LOOKUPS ===

    # Search the catalog by part number. Results are persisted as `partial`
    # search results (they become `complete` once their detail is scraped).
    #
    # The part number is normalized (e.g. "+STD" is removed) before the request.
    # Pass `fields:` to get just those SearchResult fields as symbol-keyed
    # hashes instead of the SearchResults wrapper.
    def find(part_number, page: 1, fields: nil)
      query = PartNumber.clean(part_number)
      scraper = Scrapers.for("autofactsdb").new(source: source)
      results = scraper.search(query, page: page)
      repository.store_search_results(results)
      fields ? select_fields(results.parts, fields) : results
    end

    # Look up a part by part number (and brand), or by URL. Local-first:
    # returns a stored `complete` part without fetching.
    #
    #   client.part("HL-7025S", brand: "ELGIN")
    #   client.part("2c4504")                      # brand resolved locally
    #   client.part(url: "https://…/part/brand/mpn/")
    #
    # The brand is validated against the configured standalone brands and the
    # local catalog before any request is made. Pass `fields:` to get just those
    # Part fields as a symbol-keyed hash.
    def part(part_number = nil, brand: nil, url: nil, force: false, fields: nil)
      parsed_brand, parsed_part_number = url ? Parsers.brand_slug_and_part_number(url.to_s) : [nil, nil]
      original_part_number = (part_number || parsed_part_number).to_s.strip
      brand_slug, source_key = resolve_brand(brand || parsed_brand, original_part_number)
      config = brand_config.config_for(brand_slug)
      normalized_part_number = PartNumber.clean(original_part_number, rules: config["part_number_rules"])

      part =
        if !force && (existing = repository.part(brand_slug, original_part_number)) &&
           repository.complete?(Repository::PART_TYPE, "#{brand_slug}/#{original_part_number}")
          existing
        else
          scraper = Scrapers.for(source_key).new(source: source, config: config)
          scraped = scraper.scrape_part(brand_slug, normalized_part_number)
          scraped.part_number = original_part_number
          scraped.normalized_part_number = normalized_part_number
          repository.store_part(scraped)
          repository.part(scraped.brand_slug, scraped.part_number)
        end

      fields ? select_fields(part, fields) : part
    end

    # Scrape and persist a vehicle category page (parts that fit a car).
    #
    # `category` is a category name/alias resolved through the seeded taxonomy
    # full-text search before any request. Ambiguous or unknown categories raise
    # without hitting the network.
    #
    # Pass `fields:` to get just those VehiclePart fields as symbol-keyed
    # hashes instead of the VehicleCategory wrapper.
    def vehicle(make:, year:, model:, category:, fields: nil)
      resolved = resolve_category(category)
      scraper = Scrapers.for("autofactsdb").new(source: source)
      listing = scraper.vehicle_category(make: make, year: year, model: model, category: resolved.name)
      repository.store_vehicle_category(listing)
      fields ? select_fields(listing.parts, fields) : listing
    end

    def close
      @source.close if @source.respond_to?(:close)
      @database.close
    end

    private

    attr_reader :repository, :source, :brand_config

    # Resolve a brand to [slug, source_key], validating against the configured
    # standalone brands and the local catalog. Raises before any request when
    # the brand is unknown.
    def resolve_brand(brand_input, part_number)
      candidate = brand_input.to_s.strip

      if candidate.empty?
        candidate = resolve_brand_locally(part_number).to_s
        raise Error, "Could not determine the brand for part #{part_number.inspect}; provide a brand." if candidate.empty?
      end

      config = brand_config.find(candidate)
      if config
        slug = config.fetch("slug", candidate.downcase)
        return [slug, config.fetch("source", PartBrand::DEFAULT_SOURCE)]
      end

      stored = repository.part_brand(candidate)
      if stored
        source_key = stored.source.to_s.empty? ? PartBrand::DEFAULT_SOURCE : stored.source
        return [stored.slug, source_key]
      end

      matches = repository.search_brands(candidate)
      if matches.length == 1
        matched = matches.first
        source_key = matched.source.to_s.empty? ? PartBrand::DEFAULT_SOURCE : matched.source
        return [matched.slug, source_key]
      end

      if matches.length > 1
        names = matches.map(&:name).join(", ")
        raise Error, "Ambiguous brand #{candidate.inspect} (matched: #{names}); no request was made."
      end

      raise Error, "Unknown brand #{candidate.inspect} (not configured and not in the database); no request was made."
    end

    # Recover a missing brand slug from local parts or saved search results.
    def resolve_brand_locally(part_number)
      parts = repository.parts_by_part_number(part_number)
      if parts.any?
        complete = parts.find { |part| part.status == Repository::STATUS_COMPLETE }
        return (complete || parts.first).brand_slug
      end

      repository.search_results_by_part_number(part_number).first&.brand_slug
    end

    # Resolve a category term to its seeded Category using the taxonomy FTS.
    # Raises before any request when the term is unknown or ambiguous.
    def resolve_category(term)
      matches = repository.search_categories(term)

      if matches.empty?
        raise Error, "Unknown category #{term.inspect}; no request was made."
      end

      if matches.length > 1
        names = matches.map(&:name).join(", ")
        raise Error, "Ambiguous category #{term.inspect} (matched: #{names}); no request was made."
      end

      matches.first
    end

    # Reduce one model (or an array of models) to a symbol-keyed hash with only
    # the requested attributes. Unknown attribute names are ignored.
    def select_fields(records, fields)
      keys = Array(fields).map(&:to_sym)
      return records.map { |record| model_fields(record, keys) } if records.is_a?(Array)

      model_fields(records, keys)
    end

    def model_fields(record, keys)
      available = record.class.public_attributes
      (available & keys).to_h { |key| [key, record.public_send(key)] }
    end
  end
end
