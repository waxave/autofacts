# frozen_string_literal: true

module Autofacts
  # Read-through client: checks the local database before fetching, so data we
  # already have is never requested again. Pass `force: true` to bypass.
  class Client
    def initialize(database:, source: nil, base_url: Autofacts::BASE_URL, brand_config_path: "config/brands.yml")
      @database = database.is_a?(Database) ? database : Database.new(database)
      @source = source || Source::HttpSource.new(base_url: base_url)
      @repository = Repository.new(@database.db)
      @brand_config = BrandConfig.load(brand_config_path)
    end

    # Fetch and persist the part-brands index (/part/).
    #
    # Returns a BrandIndex from the database. Skips the network when a previous
    # scrape is already marked complete, unless `force: true`.
    #
    # Pass `fields:` to get just those PartBrand fields as symbol-keyed hashes.
    def get_part_brands(force: false, fields: nil)
      index =
        if !force && repository.complete?(Repository::PART_BRANDS_TYPE, Repository::INDEX_KEY)
          repository.brand_index
        else
          scraper = Scrapers.for("autofactsdb").new(source: source)
          repository.store_brand_index(scraper.scrape_brand_index)
          repository.brand_index
        end

      fields ? select_fields(index.brands, fields) : index
    end

    # Search the catalog by part number. Results are persisted as `partial`
    # search results (they become `complete` once their detail is scraped).
    #
    # Pass `fields:` to get just those SearchResult fields as symbol-keyed
    # hashes instead of the SearchResults wrapper.
    def search_parts(query, page: 1, fields: nil)
      scraper = Scrapers.for("autofactsdb").new(source: source)
      results = scraper.search(query, page: page)
      repository.store_search_results(results)
      fields ? select_fields(results.parts, fields) : results
    end

    # Look up a part by part number, optionally with its brand. Local-first:
    # returns a stored `complete` part without fetching. When the brand is not
    # given, it is resolved from stored parts or search results.
    #
    # Accepts a full URL, "brand-slug/part-number", or a bare part number.
    # Pass `fields:` to get just those Part fields as a symbol-keyed hash.
    def get_part(identifier, brand: nil, force: false, fields: nil)
      parsed_brand, part_number = split_identifier(identifier)
      brand_slug = (brand || parsed_brand).to_s.strip
      part_number = part_number.to_s.strip

      brand_slug = resolve_brand_locally(part_number) if brand_slug.empty?
      if brand_slug.to_s.empty?
        raise Error, "Could not determine the brand for part #{part_number.inspect}; provide a brand."
      end

      part =
        if !force && (existing = repository.part(brand_slug, part_number)) &&
           repository.complete?(Repository::PART_TYPE, "#{brand_slug}/#{part_number}")
          existing
        else
          config = brand_config.config_for(brand_slug)
          source_key = config.fetch("source", "autofactsdb")
          scraper = Scrapers.for(source_key).new(source: source, config: config)
          scraped = scraper.scrape_part(brand_slug, part_number)
          repository.store_part(scraped)
          repository.part(scraped.brand_slug, scraped.part_number)
        end

      fields ? select_fields(part, fields) : part
    end

    # Scrape and persist a vehicle category page (parts that fit a car).
    #
    # Pass `fields:` to get just those VehiclePart fields as symbol-keyed
    # hashes instead of the VehicleCategory wrapper.
    def get_vehicle_parts(make:, year:, model:, category:, fields: nil)
      scraper = Scrapers.for("autofactsdb").new(source: source)
      listing = scraper.vehicle_category(make: make, year: year, model: model, category: category)
      repository.store_vehicle_category(listing)
      fields ? select_fields(listing.parts, fields) : listing
    end

    def close
      @source.close if @source.respond_to?(:close)
      @database.close
    end

    private

    attr_reader :repository, :source, :brand_config

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

    # Split an identifier into [brand_slug, part_number]. A URL, "/part/..." or
    # "brand/part-number" carries the brand; a bare part number does not.
    def split_identifier(identifier)
      value = identifier.to_s.strip
      return Parsers.brand_slug_and_part_number(value) if value.start_with?("http", "/part/")
      return value.split("/", 2).map(&:strip) if value.count("/") == 1

      [nil, value]
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
  end
end
