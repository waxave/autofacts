# frozen_string_literal: true

require "yaml"

module Autofacts
  # Loads the built-in ISO country list, the brands YAML and the category
  # taxonomy, then upserts them into the database.
  class Seeder
    COUNTRIES_PATH = File.expand_path("data/countries.yml", __dir__)
    CATEGORIES_PATH = File.expand_path("data/categories.yml", __dir__)

    def initialize(repository, brands_path: nil, countries_path: COUNTRIES_PATH, categories_path: CATEGORIES_PATH)
      @repository = repository
      @brands_path = brands_path
      @countries_path = countries_path
      @categories_path = categories_path
    end

    # Seed countries, brands and taxonomy. Returns a summary hash.
    def call
      { countries: seed_countries, brands: seed_brands, categories: seed_categories }
    end

    # Upsert every country from the ISO 3166 data file. Returns the count.
    def seed_countries
      countries = load_countries
      repository.upsert_countries(countries)
      countries.length
    end

    # Upsert every brand declared in the brands YAML. Returns the count.
    def seed_brands
      return 0 if brands_path.nil?

      brands = load_brands
      brands.each { |brand| repository.upsert_brand(brand) }
      brands.length
    end

    # Upsert categories, their subcategories and their name translations, then
    # rebuild the taxonomy full-text index (names, translations and aliases).
    # Returns counts for categories, subcategories and translations written.
    def seed_categories
      counts = { categories: 0, subcategories: 0, translations: 0 }
      entries = load_categories

      repository.clear_taxonomy_fts

      entries.each do |entry|
        category_id = repository.store_category(slug: entry.fetch("slug"), name: entry.fetch("name"))
        next if category_id.nil?

        translations = entry["translations"]
        counts[:categories] += 1
        counts[:translations] += store_translations("category", category_id, translations)
        repository.index_category(category_id, entry.fetch("slug"), taxonomy_terms(entry, translations))

        Array(entry["subcategories"]).each do |subcategory|
          subcategory_id = repository.store_subcategory(
            category_slug: entry.fetch("slug"),
            slug: subcategory.fetch("slug"),
            name: subcategory.fetch("name")
          )
          next if subcategory_id.nil?

          subcategory_translations = subcategory["translations"]
          counts[:subcategories] += 1
          counts[:translations] += store_translations("subcategory", subcategory_id, subcategory_translations)
          repository.index_subcategory(
            subcategory_id,
            subcategory.fetch("slug"),
            taxonomy_terms(subcategory, subcategory_translations)
          )
        end
      end

      counts
    end

    private

    attr_reader :repository, :brands_path, :countries_path, :categories_path

    def load_countries
      rows = YAML.safe_load_file(countries_path) || []
      rows.map { |row| Country.new(**symbolize(row)) }
    end

    def load_brands
      data = YAML.safe_load_file(brands_path) || {}
      Array(data["brands"]).map { |entry| brand_from_entry(entry) }
    end

    def load_categories
      Array(YAML.safe_load_file(categories_path))
    end

    def store_translations(translatable_type, translatable_id, translations)
      return 0 unless translations.is_a?(Hash)

      translations.count do |locale, text|
        next false if text.to_s.strip.empty?

        repository.set_translation(
          translatable_type: translatable_type,
          translatable_id: translatable_id,
          field: "name",
          locale: locale.to_s,
          text: text
        )
        true
      end
    end

    # Searchable text for one taxonomy entry: slug + name + translations +
    # curated aliases. FTS5 tokenizes and lowercases this bag of words.
    def taxonomy_terms(entry, translations)
      words = [entry["slug"], entry["name"]]
      words.concat(Array(entry["aliases"]))
      words.concat(translations.values) if translations.is_a?(Hash)

      words.flatten.compact.map { |word| word.to_s.strip }.reject(&:empty?).uniq.join(" ")
    end

    def brand_from_entry(entry)
      entry = symbolize(entry)

      PartBrand.new(
        slug: entry.fetch(:slug),
        name: entry.fetch(:name),
        source: entry[:source] || PartBrand::DEFAULT_SOURCE,
        source_url: entry[:source_url]
      )
    end

    def symbolize(hash)
      hash.to_h.transform_keys(&:to_sym)
    end
  end
end
