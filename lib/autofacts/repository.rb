# frozen_string_literal: true

require "json"
require "yaml"

module Autofacts
  # Persistence layer over the SQLite database. Knows nothing about HTTP or
  # HTML: it stores entities idempotently and answers "have we scraped this
  # yet?" via the scrape_state ledger.
  class Repository
    COUNTRIES_DATA_PATH = File.expand_path("data/countries.yml", __dir__)

    STATUS_COMPLETE = "complete"
    STATUS_EMPTY = "empty"
    STATUS_PARTIAL = "partial"

    PART_BRANDS_TYPE = "part_brands"
    INDEX_KEY = "index"
    PART_TYPE = "part"

    def initialize(db)
      @db = db
    end

    # True when a previous scrape of entity_type/key finished successfully.
    def complete?(entity_type, key)
      @db[:scrape_state].where(entity_type: entity_type, key: key).get(:status) == STATUS_COMPLETE
    end

    # === PART BRANDS ===

    def part_brands
      @db[:part_brands].all.map { |row| part_brand_from_row(row) }.sort_by { |brand| sort_name(brand.name) }
    end

    # Find a brand by slug or name (case-insensitive), or nil.
    def part_brand(value)
      text = value.to_s.strip
      return nil if text.empty?

      needle = text.downcase
      row = @db[:part_brands].where(slug: needle).first ||
            @db[:part_brands].where(Sequel.function(:lower, :name) => needle).first
      row && part_brand_from_row(row)
    end

    # Full-text search for part brands (prefix matching: "den*" -> DENSO).
    def search_brands(term)
      ids = exact_brand_alias_ids(term)
      ids = fts_match_ids(:part_brands_fts, term, :rowid) if ids.empty?
      return [] if ids.empty?

      @db[:part_brands].where(id: ids).all.map { |row| part_brand_from_row(row) }
        .sort_by { |brand| sort_name(brand.name) }
    end

    def brand_index
      meta = @db[:catalog_meta].to_hash(:key, :value)

      BrandIndex.new(
        brands: part_brands,
        last_updated: meta["brands.last_updated"],
        last_refreshed_at: meta["brands.last_refreshed_at"],
        brand_count: meta["brands.brand_count"]&.to_i,
        part_numbers_count: meta["brands.part_numbers_count"]&.to_i
      )
    end

    def store_brand_index(index)
      @db.transaction do
        index.brands.each { |brand| upsert_brand(brand) }

        write_meta("brands.last_updated", index.last_updated)
        write_meta("brands.last_refreshed_at", index.last_refreshed_at)
        write_meta("brands.brand_count", index.brand_count)
        write_meta("brands.part_numbers_count", index.part_numbers_count)

        status = index.brands.empty? ? STATUS_EMPTY : STATUS_COMPLETE
        mark_state(PART_BRANDS_TYPE, INDEX_KEY, status, index.brands.length)
      end
    end

    def upsert_brand(brand)
      now = Time.now
      attrs = {
        name: brand.name,
        url: brand.url,
        part_numbers_count: brand.part_numbers_count,
        popular: brand.popular,
        source: brand.source,
        source_url: brand.source_url,
        last_seen_at: now
      }

      existing_id = @db[:part_brands].where(slug: brand.slug).get(:id)
      if existing_id
        @db[:part_brands].where(id: existing_id).update(attrs)
        store_brand_aliases(existing_id, brand.aliases) unless brand.aliases.nil?
      else
        brand_id = @db[:part_brands].insert(attrs.merge(slug: brand.slug, first_seen_at: now))
        store_brand_aliases(brand_id, brand.aliases) unless brand.aliases.nil?
      end
    end

    # === COUNTRIES ===

    def countries
      @db[:countries].all.map { |row| country_from_row(row) }.sort_by { |country| sort_name(country.name) }
    end

    def country(code)
      row = @db[:countries].where(code: code.to_s.upcase).first
      row && country_from_row(row)
    end

    def upsert_countries(country_list)
      @db.transaction do
        country_list.each { |country| upsert_country(country) }
      end
    end

    def upsert_country(country)
      attrs = { name: country.name, description: country.description, alpha_3: country.alpha_3 }
      code = country.code.to_s.upcase

      if @db[:countries].where(code: code).count.positive?
        @db[:countries].where(code: code).update(attrs)
      else
        @db[:countries].insert(attrs.merge(code: code))
      end
    end

    # === PART TAXONOMY ===

    def categories(locale: nil)
      @db[:categories].all.map { |row| category_from_row(row, locale: locale) }
        .sort_by { |category| sort_name(category.name) }
    end

    # Full-text search for categories (name, slug, translations and aliases).
    def search_categories(term, locale: nil)
      ids = fts_match_ids(:categories_fts, term, :category_id)
      return [] if ids.empty?

      @db[:categories].where(id: ids).all.map { |row| category_from_row(row, locale: locale) }
        .sort_by { |category| sort_name(category.name) }
    end

    def subcategories(category_slug: nil, locale: nil)
      rows = subcategory_rows
      rows = rows.where(Sequel[:categories][:slug] => category_slug) if category_slug
      rows.all.map { |row| subcategory_from_row(row, locale: locale) }
        .sort_by { |subcategory| sort_name(subcategory.name) }
    end

    # Full-text search for subcategories (name, slug, translations and aliases).
    def search_subcategories(term, locale: nil)
      ids = fts_match_ids(:subcategories_fts, term, :subcategory_id)
      ids |= exact_alias_ids("subcategory", term)
      return [] if ids.empty?

      subcategory_rows.where(Sequel[:subcategories][:id] => ids).all
        .map { |row| subcategory_from_row(row, locale: locale) }
        .sort_by { |subcategory| sort_name(subcategory.name) }
    end

    # Replace the taxonomy FTS index. The seeder calls this after loading the
    # YAML so search matches names, translations and aliases.
    def clear_taxonomy_fts
      @db[:categories_fts].delete
      @db[:subcategories_fts].delete
      @db[:taxonomy_aliases].delete
    end

    def index_category(id, slug, terms)
      @db[:categories_fts].insert(category_id: id, slug: slug, terms: terms)
    end

    def index_subcategory(id, slug, terms, aliases: [])
      @db[:subcategories_fts].insert(subcategory_id: id, slug: slug, terms: terms)
      Array(aliases).each do |alias_text|
        text = alias_text.to_s.strip
        next if text.empty?

        @db[:taxonomy_aliases].insert(
          entity_type: "subcategory",
          entity_id: id,
          alias_text: text,
          normalized_text: normalize_alias(text)
        )
      end
    end

    # Upsert a category using an explicit slug (seed data preserves slugs).
    def store_category(slug:, name:)
      upsert_category_row(slug, name)
    end

    # Upsert a subcategory under a category slug using an explicit slug.
    def store_subcategory(category_slug:, slug:, name:)
      category_id = @db[:categories].where(slug: category_slug.to_s.strip.downcase).get(:id)
      return nil if category_id.nil?

      upsert_subcategory_row(category_id, slug, name)
    end

    # === PART DETAIL ===

    # Persist a full part and its relations. The part's brand, category and
    # subcategory are resolved to their own tables; attributes are stored as
    # class/attribute/unit/value rows; fitment goes through
    # vehicles/vehicle_brands/part_applications.
    def store_part(part)
      @db.transaction do
        brand_id = upsert_part_brand(part.brand_slug, part.brand)
        raise Error, "Part #{part.part_number.inspect} has no brand" if brand_id.nil?

        category_id = upsert_category(part.category)
        subcategory_id = category_id ? upsert_subcategory(category_id, part.subcategory) : nil
        part_id = upsert_part_row(part, brand_id, category_id, subcategory_id)

        merge_part_attributes(part_id, part.attributes)
        replace_part_countries(part_id, part.countries)
        replace_part_applications(part_id, part.applications)

        mark_search_results_complete(part.brand_slug, part.part_number)
        mark_state(PART_TYPE, part_key(part.brand_slug, part.part_number), STATUS_COMPLETE, Array(part.applications).length)
      end
    end

    # Read a stored part by brand slug + part number (case-insensitive), or nil.
    # Pass `locale:` to localize category, subcategory and attribute names.
    def part(brand_slug, part_number, locale: nil)
      brand_row = @db[:part_brands].where(slug: brand_slug.to_s.downcase).first
      return nil unless brand_row

      row = @db[:parts]
        .where(brand_id: brand_row[:id])
        .where(Sequel.function(:lower, :part_number) => part_number.to_s.downcase)
        .first
      row && part_from_row(row, locale: locale)
    end

    # All stored parts with the given part number (case-insensitive).
    def parts_by_part_number(part_number, locale: nil)
      needle = part_number.to_s.downcase
      @db[:parts].where(Sequel.function(:lower, :part_number) => needle).all.map { |row| part_from_row(row, locale: locale) }
    end

    # === VEHICLE CATEGORY ===

    # Persist a vehicle category listing: make, vehicles (per engine),
    # categories/subcategories, parts (partial), notes (attributes), markets
    # (countries) and applications (part <-> vehicle).
    def store_vehicle_category(listing)
      @db.transaction do
        make_name = listing.make_name || titleize(listing.make)
        make_id = upsert_vehicle_brand(make_name)
        category_id = upsert_category(listing.category_name)
        model_name = listing.model_name || titleize(listing.model)

        listing.parts.each do |vehicle_part|
          brand_id = upsert_part_brand(vehicle_part.brand_slug, vehicle_part.brand)
          next if brand_id.nil?

          subcategory_id = category_id ? upsert_subcategory(category_id, vehicle_part.subcategory) : nil
          part_id = upsert_listing_part(vehicle_part, brand_id, category_id, subcategory_id)
          next if part_id.nil?

          merge_part_attributes(part_id, vehicle_part.notes)
          replace_part_countries(part_id, vehicle_part.markets)

          vehicle_part.engines.each do |engine|
            vehicle = Vehicle.new(year: listing.year, make: make_name, model: model_name, engine: engine)
            vehicle_id = upsert_vehicle(make_id, vehicle)
            insert_application(part_id, vehicle_id)
          end
        end

        mark_state("vehicle_category", vehicle_category_key(listing), STATUS_COMPLETE, listing.parts.length)
      end
    end

    # === SEARCH RESULTS ===

    def store_search_results(results)
      @db.transaction do
        results.parts.each { |result| upsert_search_result(result, results.query) }
      end
    end

    def search_results(query: nil)
      dataset = @db[:search_results]
      dataset = dataset.where(query: query) if query
      dataset.order(:brand_slug, :part_number).all.map { |row| search_result_from_row(row) }
    end

    # All saved search results with the given part number (case-insensitive).
    def search_results_by_part_number(part_number)
      needle = part_number.to_s.downcase
      @db[:search_results].where(Sequel.function(:lower, :part_number) => needle).all.map { |row| search_result_from_row(row) }
    end

    # === TRANSLATIONS ===

    def set_translation(translatable_type:, translatable_id:, field:, locale:, text:)
      now = Time.now
      key = {
        translatable_type: translatable_type.to_s,
        translatable_id: translatable_id,
        field: field.to_s,
        locale: locale.to_s
      }

      if @db[:translations].where(key).count.positive?
        @db[:translations].where(key).update(text: text, updated_at: now)
      else
        @db[:translations].insert(key.merge(text: text, updated_at: now))
      end
    end

    def translation(translatable_type, translatable_id, field, locale)
      @db[:translations].where(
        translatable_type: translatable_type.to_s,
        translatable_id: translatable_id,
        field: field.to_s,
        locale: locale.to_s
      ).get(:text)
    end

    def translations_for(translatable_type, translatable_id)
      @db[:translations]
        .where(translatable_type: translatable_type.to_s, translatable_id: translatable_id)
        .order(:field, :locale)
        .all
        .map do |row|
          Translation.new(
            translatable_type: row[:translatable_type],
            translatable_id: row[:translatable_id],
            field: row[:field],
            locale: row[:locale],
            text: row[:text]
          )
        end
    end

    private

    # --- part helpers ---

    def upsert_part_brand(slug, name)
      value = slug.to_s.strip.downcase
      return nil if value.empty?

      existing_id = @db[:part_brands].where(slug: value).get(:id)
      if existing_id
        @db[:part_brands].where(id: existing_id).update(name: name.to_s.strip, last_seen_at: Time.now) unless name.to_s.strip.empty?
        existing_id
      else
        now = Time.now
        @db[:part_brands].insert(slug: value, name: name.to_s.strip, first_seen_at: now, last_seen_at: now)
      end
    end

    def upsert_category(name)
      value = name.to_s.strip
      return nil if value.empty?

      upsert_category_row(slugify(value), value)
    end

    def upsert_category_row(slug, name)
      value = slug.to_s.strip.downcase
      return nil if value.empty?

      value_name = name.to_s.strip
      existing_id = @db[:categories].where(slug: value).get(:id)
      if existing_id
        @db[:categories].where(id: existing_id).update(name: value_name)
        existing_id
      else
        @db[:categories].insert(slug: value, name: value_name)
      end
    end

    def upsert_subcategory(category_id, name)
      value = name.to_s.strip
      return nil if value.empty?

      upsert_subcategory_row(category_id, slugify(value), value)
    end

    def upsert_subcategory_row(category_id, slug, name)
      value = slug.to_s.strip.downcase
      return nil if value.empty?

      dataset = @db[:subcategories].where(category_id: category_id, slug: value)
      existing_id = dataset.get(:id)
      if existing_id
        dataset.update(name: name.to_s.strip)
        existing_id
      else
        @db[:subcategories].insert(category_id: category_id, slug: value, name: name.to_s.strip)
      end
    end

    def upsert_part_row(part, brand_id, category_id, subcategory_id)
      now = Time.now
      attrs = {
        category_id: category_id,
        subcategory_id: subcategory_id,
        description: part.description,
        grade: part.grade,
        status: part.status,
        last_seen_at: now
      }

      existing_id = @db[:parts].where(brand_id: brand_id, part_number: part.part_number).get(:id)
      if existing_id
        @db[:parts].where(id: existing_id).update(attrs)
        existing_id
      else
        @db[:parts].insert(attrs.merge(brand_id: brand_id, part_number: part.part_number, first_seen_at: now))
      end
    end

    # Merge attributes by (class, attribute, unit, value) so notes from a
    # vehicle listing and attributes from a part detail can coexist without
    # duplication.
    def merge_part_attributes(part_id, attributes)
      existing = @db[:part_attributes].where(part_id: part_id).select_map(%i[class attribute unit value])

      Array(attributes).each do |attribute|
        klass, name, unit, value = attribute_pair(attribute)
        name = name.to_s.strip
        next if name.empty?

        row = [klass, name, unit, value]
        next if existing.include?(row)

        @db[:part_attributes].insert(part_id: part_id, class: klass, attribute: name, unit: unit, value: value)
        existing << row
      end
    end

    def attribute_pair(attribute)
      if attribute.is_a?(Hash)
        [
          attribute[:class] || attribute["class"],
          attribute[:attribute] || attribute["attribute"],
          attribute[:unit] || attribute["unit"],
          attribute[:value] || attribute["value"]
        ]
      else
        [nil, attribute.to_s.strip, nil, nil]
      end
    end

    def part_from_row(row, locale: nil)
      brand_row = @db[:part_brands].where(id: row[:brand_id]).first
      category_row = row[:category_id] ? @db[:categories].where(id: row[:category_id]).first : nil
      subcategory_row = row[:subcategory_id] ? @db[:subcategories].where(id: row[:subcategory_id]).first : nil

      vehicles = part_applications(row[:id])
      country_codes = part_country_codes(row[:id])
      applications = expand_applications(vehicles, country_codes)
      attributes = part_attributes_list(row[:id], locale: locale)
      brand_slug = brand_row && brand_row[:slug]

      Part.new(
        brand_slug: brand_slug,
        part_number: row[:part_number],
        brand: brand_row && brand_row[:name],
        category: taxonomy_node("category", category_row),
        subcategory: taxonomy_node("subcategory", subcategory_row),
        description: row[:description],
        grade: row[:grade],
        attributes: attributes,
        attributes_count: attributes.length,
        countries: country_codes,
        applications: applications,
        applications_count: applications.length,
        years_range: years_range(applications),
        makes: vehicles.map(&:make).compact.uniq,
        url: part_url(brand_slug, row[:part_number]),
        status: row[:status]
      )
    end

    # A taxonomy node: base name plus all stored locale translations.
    def taxonomy_node(type, row)
      return nil if row.nil?

      translations = @db[:translations]
        .where(translatable_type: type, translatable_id: row[:id], field: "name")
        .order(:locale)
        .all
        .to_h { |translation| [translation[:locale].to_sym, translation[:text]] }

      { name: row[:name], translations: translations }
    end

    # Expand each vehicle across the part's markets, one entry per country.
    # Parts with no markets still keep one entry per vehicle (country = nil).
    def expand_applications(vehicles, country_codes)
      alpha3_codes = country_codes.empty? ? {} : @db[:countries].where(code: country_codes).select_hash(:code, :alpha_3)

      vehicles.flat_map do |vehicle|
        if country_codes.empty?
          [application_entry(vehicle, nil, nil)]
        else
          country_codes.map { |code| application_entry(vehicle, code, alpha3_codes[code]) }
        end
      end
    end

    def application_entry(vehicle, country_code, country_alpha3)
      {
        year: vehicle.year,
        make: presence(vehicle.make),
        model: presence(vehicle.model),
        engine: presence(vehicle.engine),
        country_code: country_code,
        country_alpha3: country_alpha3
      }
    end

    def presence(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def part_attributes_list(part_id, locale: nil)
      @db[:part_attributes].where(part_id: part_id).order(:id).all.map do |row|
        name = translated_name("part_attribute", row[:id], row[:attribute], locale)
        { class: row[:class], attribute: name, unit: row[:unit], value: row[:value] }
      end
    end

    def translated_name(type, id, fallback, locale)
      return fallback if locale.nil?

      translation(type, id, "name", locale) || fallback
    end

    def part_country_codes(part_id)
      @db[:part_countries].where(part_id: part_id).order(:country_code).select_map(:country_code)
    end

    def part_applications(part_id)
      rows = @db[:part_applications]
        .where(part_id: part_id)
        .join(:vehicles, id: :vehicle_id)
        .join(:vehicle_brands, Sequel[:vehicle_brands][:id] => Sequel[:vehicles][:make_id])
        .select(
          Sequel[:vehicles][:year],
          Sequel[:vehicle_brands][:name].as(:make_name),
          Sequel[:vehicles][:model],
          Sequel[:vehicles][:engine]
        )
        .order(Sequel[:vehicles][:year], Sequel[:vehicle_brands][:name], Sequel[:vehicles][:model])
        .all

      rows.map { |r| Vehicle.new(year: r[:year], make: r[:make_name], model: r[:model], engine: r[:engine]) }
    end

    def years_range(applications)
      years = applications.map { |application| application[:year] }.compact
      return nil if years.empty?

      min, max = years.minmax
      min == max ? [min] : [min, max]
    end

    def part_url(brand_slug, part_number)
      return nil if brand_slug.to_s.empty?

      "#{BASE_URL}/part/#{brand_slug}/#{part_number}/"
    end

    def replace_part_countries(part_id, codes)
      @db[:part_countries].where(part_id: part_id).delete

      normalize_country_codes(codes).each do |code|
        @db[:part_countries].insert(part_id: part_id, country_code: code)
      end
    end

    # Normalize to valid catalog country codes, creating minimal catalog
    # entries for any code that is not yet present.
    def normalize_country_codes(codes)
      Array(codes)
        .map { |code| code.to_s.strip.upcase }
        .reject(&:empty?)
        .uniq
        .filter_map { |code| ensure_country(code) }
    end

    def ensure_country(code)
      value = code.to_s.strip.upcase
      return nil if value.empty?

      existing = @db[:countries].where(code: value).first
      return existing[:code] if existing

      data = country_catalog[value]
      return nil unless data

      @db[:countries].insert(code: value, alpha_3: data["alpha_3"], name: data["name"], description: data["description"])
      value
    end

    def country_catalog
      @country_catalog ||= begin
        rows = YAML.safe_load_file(COUNTRIES_DATA_PATH) || []
        rows.to_h { |row| [row["code"], row] }
      end
    end

    def replace_part_applications(part_id, vehicles)
      @db[:part_applications].where(part_id: part_id).delete

      Array(vehicles).each do |vehicle|
        make_id = upsert_vehicle_brand(vehicle.make)
        next if make_id.nil?

        vehicle_id = upsert_vehicle(make_id, vehicle)
        insert_application(part_id, vehicle_id)
      end
    end

    def upsert_vehicle_brand(name)
      value = name.to_s.strip
      return nil if value.empty?

      slug = slugify(value)
      existing_id = @db[:vehicle_brands].where(slug: slug).get(:id)

      if existing_id
        @db[:vehicle_brands].where(id: existing_id).update(name: value)
        existing_id
      else
        @db[:vehicle_brands].insert(slug: slug, name: value)
      end
    end

    def upsert_vehicle(make_id, vehicle)
      dataset = @db[:vehicles].where(
        make_id: make_id,
        year: vehicle.year,
        model: vehicle.model.to_s,
        engine: vehicle.engine.to_s
      )

      existing_id = dataset.get(:id)
      return existing_id if existing_id

      @db[:vehicles].insert(
        make_id: make_id,
        year: vehicle.year,
        model: vehicle.model.to_s,
        engine: vehicle.engine.to_s
      )
    end

    def mark_search_results_complete(brand_slug, part_number)
      @db[:search_results]
        .where(Sequel.function(:lower, :brand_slug) => brand_slug.to_s.downcase)
        .where(Sequel.function(:lower, :part_number) => part_number.to_s.downcase)
        .update(status: STATUS_COMPLETE, last_seen_at: Time.now)
    end

    def upsert_listing_part(vehicle_part, brand_id, category_id, subcategory_id)
      now = Time.now
      attrs = {
        category_id: category_id,
        subcategory_id: subcategory_id,
        grade: vehicle_part.tier,
        last_seen_at: now
      }

      existing = @db[:parts]
        .where(brand_id: brand_id)
        .where(Sequel.function(:lower, :part_number) => vehicle_part.part_number.to_s.downcase)
        .first

      if existing
        @db[:parts].where(id: existing[:id]).update(attrs)
        existing[:id]
      else
        @db[:parts].insert(attrs.merge(
          brand_id: brand_id,
          part_number: vehicle_part.part_number,
          status: STATUS_COMPLETE,
          first_seen_at: now
        ))
      end
    end

    def insert_application(part_id, vehicle_id)
      return if vehicle_id.nil?
      return if @db[:part_applications].where(part_id: part_id, vehicle_id: vehicle_id).count.positive?

      @db[:part_applications].insert(part_id: part_id, vehicle_id: vehicle_id)
    end

    def vehicle_category_key(listing)
      "#{listing.make}/#{listing.year}/#{listing.model}/#{listing.category}"
    end

    def titleize(slug)
      slug.to_s.split("-").map(&:capitalize).join(" ")
    end

    # True when a complete part already exists for this brand + part number.
    def part_complete?(brand_slug, part_number)
      brand_row = @db[:part_brands].where(slug: brand_slug.to_s.downcase).first
      return false unless brand_row

      @db[:parts]
        .where(brand_id: brand_row[:id])
        .where(Sequel.function(:lower, :part_number) => part_number.to_s.downcase)
        .where(status: STATUS_COMPLETE)
        .count
        .positive?
    end

    # --- search-result helpers ---

    def upsert_search_result(result, query)
      now = Time.now
      attrs = {
        query: query,
        brand: result.brand,
        description: result.description,
        category: result.category,
        subcategory: result.subcategory,
        url: result.url,
        attributes: JSON.generate(Array(result.attributes)),
        applications: JSON.generate(Array(result.applications)),
        applications_count: result.applications_count,
        last_seen_at: now
      }

      existing_id = @db[:search_results]
        .where(brand_slug: result.brand_slug, part_number: result.part_number)
        .get(:id)

      if existing_id
        # Never downgrade a completed result back to partial.
        @db[:search_results].where(id: existing_id).update(attrs)
      else
        status = part_complete?(result.brand_slug, result.part_number) ? STATUS_COMPLETE : (result.status || STATUS_PARTIAL)
        @db[:search_results].insert(attrs.merge(
          brand_slug: result.brand_slug,
          part_number: result.part_number,
          status: status,
          first_seen_at: now
        ))
      end
    end

    def search_result_from_row(row)
      SearchResult.new(
        brand_slug: row[:brand_slug],
        part_number: row[:part_number],
        brand: row[:brand],
        description: row[:description],
        category: row[:category],
        subcategory: row[:subcategory],
        url: row[:url],
        attributes: parse_json_array(row[:attributes]),
        applications: parse_json_array(row[:applications]),
        applications_count: row[:applications_count],
        status: row[:status]
      )
    end

    # --- shared helpers ---

    # Prefix-match every token against an FTS5 table and return the mapped
    # source ids (e.g. "den" -> DENSO). Punctuation is stripped so slugs and
    # names like "balance-shaft" or "A/C" are safe query input.
    def fts_match_ids(table, term, id_column)
      tokens = term.to_s.scan(/[[:alnum:]]+/).reject(&:empty?)
      return [] if tokens.empty?

      query = tokens.map { |token| "#{token}*" }.join(" AND ")
      @db[table].where(Sequel.lit("#{table} MATCH ?", query)).select_map(id_column)
    end

    def subcategory_rows
      @db[:subcategories]
        .join(:categories, Sequel[:categories][:id] => Sequel[:subcategories][:category_id])
        .select_all(:subcategories)
        .select_append(
          Sequel[:categories][:slug].as(:category_slug),
          Sequel[:categories][:name].as(:category_name)
        )
        .order(Sequel[:categories][:name], Sequel[:subcategories][:name])
    end

    def category_from_row(row, locale: nil)
      Category.new(
        slug: row[:slug],
        name: translated_name("category", row[:id], row[:name], locale),
        translations: taxonomy_translations("category", row[:id])
      )
    end

    def subcategory_from_row(row, locale: nil)
      Subcategory.new(
        slug: row[:slug],
        name: translated_name("subcategory", row[:id], row[:name], locale),
        translations: taxonomy_translations("subcategory", row[:id]),
        category: row[:category_slug],
        category_name: translated_name("category", row[:category_id], row[:category_name], locale),
        category_translations: taxonomy_translations("category", row[:category_id])
      )
    end

    def taxonomy_translations(type, id)
      @db[:translations]
        .where(translatable_type: type, translatable_id: id, field: "name")
        .order(:locale)
        .all
        .to_h { |translation| [translation[:locale].to_sym, translation[:text]] }
    end

    def sort_name(value)
      value.to_s.downcase
    end

    def exact_alias_ids(type, term)
      normalized = normalize_alias(term)
      return [] if normalized.empty?

      @db[:taxonomy_aliases]
        .where(entity_type: type, normalized_text: normalized)
        .select_map(:entity_id)
    end

    def exact_brand_alias_ids(term)
      normalized = normalize_alias(term)
      return [] if normalized.empty?

      @db[:brand_aliases].where(normalized_text: normalized).select_map(:brand_id)
    end

    def brand_aliases(brand_id)
      @db[:brand_aliases]
        .where(brand_id: brand_id)
        .order(:normalized_text)
        .select_map(:alias_text)
    end

    def store_brand_aliases(brand_id, aliases)
      @db[:brand_aliases].where(brand_id: brand_id).delete
      Array(aliases).each do |alias_text|
        text = alias_text.to_s.strip
        next if text.empty?

        normalized = normalize_alias(text)
        next if normalized.empty?

        @db[:brand_aliases].insert(brand_id: brand_id, alias_text: text, normalized_text: normalized)
      rescue Sequel::UniqueConstraintViolation
        next
      end
    end

    def normalize_alias(value)
      value.to_s
        .unicode_normalize(:nfkd)
        .gsub(/\p{Mn}/, "")
        .downcase
        .gsub(/\s+/, " ")
        .strip
    end

    def part_key(brand_slug, part_number)
      "#{brand_slug}/#{part_number}"
    end

    def slugify(value)
      value.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    end

    def parse_json_array(value)
      return [] if value.nil? || value.to_s.strip.empty?

      parsed = JSON.parse(value)
      parsed.is_a?(Array) ? parsed : []
    rescue JSON::ParserError
      []
    end

    def write_meta(key, value)
      row = { value: value.nil? ? nil : value.to_s, updated_at: Time.now }

      if @db[:catalog_meta].where(key: key).count.positive?
        @db[:catalog_meta].where(key: key).update(row)
      else
        @db[:catalog_meta].insert(row.merge(key: key))
      end
    end

    def mark_state(entity_type, key, status, row_count)
      row = { status: status, row_count: row_count, error: nil, scraped_at: Time.now }

      if @db[:scrape_state].where(entity_type: entity_type, key: key).count.positive?
        @db[:scrape_state].where(entity_type: entity_type, key: key).update(row)
      else
        @db[:scrape_state].insert(row.merge(entity_type: entity_type, key: key))
      end
    end

    def part_brand_from_row(row)
      PartBrand.new(
        slug: row[:slug],
        name: row[:name],
        url: row[:url],
        part_numbers_count: row[:part_numbers_count],
        popular: row[:popular],
        source: row[:source],
        source_url: row[:source_url],
        aliases: brand_aliases(row[:id])
      )
    end

    def country_from_row(row)
      Country.new(code: row[:code], alpha_3: row[:alpha_3], name: row[:name], description: row[:description])
    end
  end
end
