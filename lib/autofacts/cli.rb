# frozen_string_literal: true

require "json"
require "thor"

require_relative "../autofacts"

module Autofacts
  # Command-line interface for seeding and searching the local catalog.
  class CLI < Thor
    # [model attribute, column width, header label] for `find`'s default table.
    FIND_COLUMNS = [
      [:part_number, 16, "PART #"],
      [:brand, 26, "BRAND"],
      [:category, 18, "CATEGORY"],
      [:subcategory, 24, "SUB-CATEGORY"]
    ].freeze

    def self.exit_on_failure? = true

    desc "seed", "Seed countries, configured brands, categories and catalog brands"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    option :brands, aliases: "-b", default: "config/brands.yml", desc: "Brands YAML path"
    def seed
      with_repository do |repository|
        puts "Database: #{options[:database]}"
        seeder = Seeder.new(repository, brands_path: options[:brands])
        country_count = seeder.seed_countries
        configured_count = seeder.seed_brands
        taxonomy = seeder.seed_categories
        catalog_count = seeder.seed_catalog_brands

        puts "Seeded #{country_count} countries"
        puts "Seeded #{configured_count} configured brands"
        puts "Seeded #{catalog_count} catalog brands"
        puts "Seeded #{taxonomy[:categories]} categories and #{taxonomy[:subcategories]} subcategories " \
             "(#{taxonomy[:translations]} translations)"
        puts "Total brands: #{repository.part_brands.length}"
      end
    end

    desc "install", "Create/migrate the SQLite database and seed it"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    option :brands, aliases: "-b", default: "config/brands.yml", desc: "Brands YAML path"
    option :seed, type: :boolean, default: true, desc: "Seed countries, categories, brands and catalog brands"
    def install
      result = Autofacts.install(
        path: options[:database],
        seed: options[:seed],
        brands_path: options[:brands]
      )

      puts "Database ready at #{result[:path]}"
      return unless options[:seed]

      taxonomy = result[:categories]
      puts "Seeded #{result[:countries]} countries"
      puts "Seeded #{result[:brands]} configured brands"
      puts "Seeded #{result[:catalog_brands]} catalog brands"
      puts "Seeded #{taxonomy[:categories]} categories and #{taxonomy[:subcategories]} subcategories " \
           "(#{taxonomy[:translations]} translations)"
    rescue Autofacts::Error => e
      warn "Error: #{e.message}"
    end

    desc "brands", "List seeded brands"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    def brands
      with_repository do |repository|
        brands = repository.part_brands

        if brands.empty?
          puts "No brands found."
          next
        end

        puts format("%-28s %-28s %-12s", "SLUG", "NAME", "SOURCE")
        brands.each do |brand|
          puts format("%-28s %-28s %-12s", brand.slug, brand.name, brand.source)
        end
      end
    end

    desc "countries", "List seeded countries"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    def countries
      with_repository do |repository|
        repository.countries.each { |country| puts "#{country.code}  #{country.name}" }
      end
    end

    desc "categories", "List part categories"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    option :locale, aliases: "-l", desc: "Locale for translated names"
    def categories
      with_repository do |repository|
        rows = repository.categories(locale: options[:locale])

        if rows.empty?
          puts "No categories found."
          next
        end

        rows.each { |category| puts "#{category.slug}  #{category.name}" }
      end
    end

    desc "subcategories", "List part subcategories (optionally by category)"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    option :category, aliases: "-c", desc: "Only subcategories of this category slug"
    option :locale, aliases: "-l", desc: "Locale for translated names"
    def subcategories
      with_repository do |repository|
        rows = repository.subcategories(category_slug: options[:category], locale: options[:locale])

        if rows.empty?
          puts "No subcategories found."
          next
        end

        puts format("%-20s %-28s %s", "CATEGORY", "SLUG", "NAME")
        rows.each do |subcategory|
          puts format("%-20s %-28s %s", subcategory.category, subcategory.slug, subcategory.name)
        end
      end
    end

    desc "search TERM", "Full-text search brands, categories and subcategories (prefix match)"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    option :locale, aliases: "-l", desc: "Locale for translated taxonomy names"
    def search(term)
      with_repository do |repository|
        brands = repository.search_brands(term)
        categories = repository.search_categories(term, locale: options[:locale])
        subcategories = repository.search_subcategories(term, locale: options[:locale])

        if brands.empty? && categories.empty? && subcategories.empty?
          puts "No matches for #{term.inspect}"
          next
        end

        brands.each { |brand| puts "brand:       #{brand.name} (#{brand.slug}) — #{brand.source}" }
        categories.each { |category| puts "category:    #{category.name} (#{category.slug})" }
        subcategories.each do |subcategory|
          context = subcategory.category_name || subcategory.category
          puts "subcategory: #{subcategory.name} (#{subcategory.slug}) · #{context}"
        end
      end
    end

    desc "category TERM", "Search part categories by name, translation, slug or alias"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    option :locale, aliases: "-l", desc: "Locale for translated names"
    option :json, type: :boolean, default: false, desc: "Output structured JSON"
    def category(term)
      with_repository do |repository|
        rows = repository.search_categories(term, locale: options[:locale])
        puts JSON.generate(rows.map(&:to_h)) if options[:json]
        next if options[:json]

        if rows.empty?
          puts "No category matches for #{term.inspect}"
          next
        end

        rows.each { |row| puts "#{row.slug}  #{row.name}" }
      end
    end

    desc "subcategory TERM", "Search part subcategories by name, translation, slug or alias"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    option :locale, aliases: "-l", desc: "Locale for translated names"
    option :json, type: :boolean, default: false, desc: "Output structured JSON"
    def subcategory(term)
      with_repository do |repository|
        rows = repository.search_subcategories(term, locale: options[:locale])
        puts JSON.generate(rows.map(&:to_h)) if options[:json]
        next if options[:json]

        if rows.empty?
          puts "No subcategory matches for #{term.inspect}"
          next
        end

        rows.each do |row|
          puts "#{row.category}  #{row.slug}  #{row.name} (#{row.category_name})"
        end
      end
    end

    desc "find PART_NUMBER", "Search the catalog by part number (saved as partial results)"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    option :fixtures, aliases: "-f", desc: "Saved-page directory (offline) instead of the live site"
    option :page, type: :numeric, default: 1, desc: "Results page"
    option :verbose, aliases: "-v", type: :boolean, default: false, desc: "Show full details for each part"
    option :json, type: :boolean, default: false, desc: "Output results as JSON"
    def find(part_number)
      source = options[:fixtures] ? Source::FixtureSource.new(options[:fixtures]) : Source::HttpSource.new
      client = Client.new(database: options[:database], source: source)
      results = client.find(part_number, page: options[:page])

      if options[:json]
        print_results_json(results)
      elsif results.parts.empty?
        puts "No parts found for #{part_number.inspect}"
      elsif options[:verbose]
        print_results_verbose(results)
      else
        print_results_table(results)
      end
    rescue Autofacts::Error => e
      warn "Error: #{e.message}"
    ensure
      client&.close
    end

    desc "part PART_NUMBER", "Scrape and save a part detail (part number + brand, or a URL)"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    option :fixtures, aliases: "-f", desc: "Saved-page directory (offline) instead of the live site"
    option :brand, aliases: "-b", desc: "Brand name (e.g. ELGIN, Hastings Manufacturing)"
    option :url, aliases: "-u", desc: "Part detail URL (alternative to PART_NUMBER + brand)"
    option :json, type: :boolean, default: false, desc: "Output the part as JSON"
    def part(part_number = nil)
      source = options[:fixtures] ? Source::FixtureSource.new(options[:fixtures]) : Source::HttpSource.new
      client = Client.new(database: options[:database], source: source)
      record = client.part(part_number, brand: options[:brand], url: options[:url])

      if options[:json]
        print_part_json(record)
      else
        print_part(record)
      end
    rescue Autofacts::Error => e
      warn "Error: #{e.message}"
    ensure
      client&.close
    end

    desc "vehicle MAKE YEAR MODEL CATEGORY", "Scrape and save a vehicle category (parts that fit)"
    option :database, aliases: "-d", default: Autofacts.database_path, desc: "SQLite database path"
    option :fixtures, aliases: "-f", desc: "Saved-page directory (offline) instead of the live site"
    option :json, type: :boolean, default: false, desc: "Output as JSON"
    option :limit, type: :numeric, default: 20, desc: "Max parts to print"
    def vehicle(make, year, model, category)
      source = options[:fixtures] ? Source::FixtureSource.new(options[:fixtures]) : Source::HttpSource.new
      client = Client.new(database: options[:database], source: source)
      listing = client.vehicle(make: make, year: year.to_i, model: model, category: category)
      if options[:json]
        print_vehicle_category_json(listing)
      else
        print_vehicle_category(listing, limit: options[:limit])
      end
    rescue Autofacts::Error => e
      warn "Error: #{e.message}"
    ensure
      client&.close
    end

    private

    def print_vehicle_category(listing, limit: 20)
      puts listing.title
      puts "  Parts: #{listing.parts_count} · Types: #{listing.part_types_count} · " \
           "Brands: #{listing.brands_count} · Engines: #{listing.engine_options_count}"
      puts "  Parsed #{listing.count} parts"

      listing.parts.first(limit).each do |part|
        puts "  #{part.part_number.ljust(16)} #{part.brand.to_s.ljust(24)} #{part.subcategory}"
      end
      puts "  … #{listing.count - limit} more" if listing.count > limit
    end

    def print_vehicle_category_json(listing)
      payload = listing.to_h
      payload[:parts] = listing.parts.map(&:to_h)
      puts JSON.pretty_generate(payload)
    end

    def print_results_table(results)
      puts format_row(FIND_COLUMNS.map { |_, width, label| [label, width] })

      results.parts.each do |part|
        cells = FIND_COLUMNS.map { |attribute, width, _| [part.public_send(attribute), width] }
        puts format_row(cells)
      end

      puts
      puts find_summary(results)
    end

    def print_results_verbose(results)
      results.parts.each { |part| print_part_details(part) }
      puts find_summary(results)
    end

    def print_results_json(results)
      payload = {
        query: results.query,
        page: results.page,
        result_count: results.result_count,
        next_page_url: results.next_page_url,
        parts: results.parts.map(&:to_h)
      }

      puts JSON.pretty_generate(payload)
    end

    def print_part_details(part)
      puts part.description
      puts "  Category:     #{part.category}" if part.category
      puts "  Sub-category: #{part.subcategory}" if part.subcategory

      print_applications(part)
      print_list("Attributes", part.attributes)

      puts "  URL:          #{part.url}" if part.url
      puts
    end

    def print_applications(part)
      return if part.applications.empty?

      puts "  Applications:"
      part.applications.each do |application|
        label = [application[:year], application[:vehicle]].compact.join(" ")
        label += " · #{application[:engine]}" if application[:engine]
        puts "    - #{label}"
      end
      puts "    (+#{part.applications_count} more)" if part.applications_count
    end

    def print_list(label, values)
      return if values.empty?

      puts "  #{label}:"
      values.each { |value| puts "    - #{value}" }
    end

    def find_summary(results)
      total = results.result_count || results.count
      summary = "#{total} #{total == 1 ? "part" : "parts"} · page #{results.page}"
      summary += " · next: #{results.next_page_url}" if results.next_page_url
      summary
    end

    def format_row(cells)
      cells.map { |value, width| format("%-#{width}s", truncate(value, width)) }.join(" ")
    end

    def truncate(value, width)
      text = value.to_s
      return text if text.length <= width
      return text[0, width] if width <= 1

      "#{text[0, width - 1]}…"
    end

    def print_part(part)
      title = [part.brand, part.part_number].compact.join(" ")
      title += " — #{part.subcategory[:name]}" if part.subcategory
      puts title
      puts "  Status:       #{part.status}"
      puts "  Description:  #{part.description}" if part.description
      print_taxonomy("Category", part.category)
      print_taxonomy("Sub-category", part.subcategory)
      puts "  Grade:        #{part.grade}" if part.grade
      puts "  Years:        #{format_years(part.years_range)}" if part.years_range
      puts "  Makes:        #{Array(part.makes).join(", ")}" unless Array(part.makes).empty?
      puts "  Countries:    #{Array(part.countries).join(", ")}" unless Array(part.countries).empty?
      puts "  Attributes:   #{part.attributes_count}" if part.attributes_count
      puts "  Applications: #{part.applications_count}" if part.applications_count

      print_attributes(part.attributes)

      unless part.applications.empty?
        puts "  Applications:"
        part.applications.each do |application|
          label = [application[:year], application[:make], application[:model]].compact.join(" ")
          label += " · #{application[:engine]}" if application[:engine]
          label += " · #{application[:country_code]}" if application[:country_code]
          puts "    - #{label}"
        end
      end

      puts "  URL:          #{part.url}" if part.url
    end

    def print_taxonomy(label, node)
      return if node.nil?

      translations = node[:translations] || {}
      suffix = translations.empty? ? "" : " (#{translations.map { |locale, text| "#{locale}: #{text}" }.join(", ")})"
      puts "  #{label.ljust(13)}#{node[:name]}#{suffix}"
    end

    def format_years(range)
      return nil if range.nil?

      Array(range).join("–")
    end

    def print_attributes(attributes)
      return if attributes.empty?

      puts "  Attributes:"
      attributes.each do |attribute|
        label = [attribute[:class], attribute[:attribute]].compact.join(" ")
        label += " (#{attribute[:unit]})" if attribute[:unit]
        label += ": #{attribute[:value]}" if attribute[:value]
        puts "    - #{label}"
      end
    end

    def print_part_json(part)
      puts JSON.pretty_generate(part.to_h)
    end

    def with_repository
      database = Database.new(options[:database])
      yield Repository.new(database.db)
    ensure
      database&.close
    end
  end
end
