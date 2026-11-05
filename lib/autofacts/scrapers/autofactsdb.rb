# frozen_string_literal: true

module Autofacts
  module Scrapers
    # Built-in scraper for AutoFactsDB.com.
    class AutofactsDb < Base
      SOURCE = "autofactsdb"

      # Our taxonomy slugs differ from AutoFactsDB's category URL slugs for these.
      TRANSMISSION_SLUGS = {
        "automatic-transmission" => "transmission-automatic",
        "manual-transmission" => "transmission-manual"
      }.freeze

      def scrape_brand_index
        html = source.get("/part/")
        index = Parsers.parse_brand_index(html)
        index.brands.each { |brand| brand.source = SOURCE }
        index
      end

      # Search the catalog by part number (and optionally page).
      def search(query, page: nil)
        path = "/search/?q=#{query}"
        path += "&page=#{page}" if page && page.to_i > 1

        html = source.get(path)
        Parsers.parse_search_results(html, query: query, page: page || 1)
      end

      # Build the detail path for a part: /part/{brand}/{part_number}/.
      def part_path(brand_slug, part_number)
        "/part/#{brand_slug}/#{part_number}/"
      end

      def scrape_part(brand_slug, part_number)
        part_detail(part_path(brand_slug, part_number.to_s.downcase))
      end

      # Scrape a part detail page. Accepts a full URL or a "/part/brand/mpn/"
      # path.
      def part_detail(url)
        path = normalize_path(url)
        html = source.get(path)
        Parsers.parse_part_detail(html, url: path)
      end

      # Scrape a vehicle category page (parts that fit a car/year/model/category).
      # `category` is the plain category (e.g. "engine"); the slug is built.
      def vehicle_category(make:, year:, model:, category:)
        path = "/vehicles/#{make}/#{year}/#{model}/#{vehicle_category_slug(category)}/"
        html = source.get(path)
        Parsers.parse_vehicle_category(html, url: path)
      end

      private

      def vehicle_category_slug(category)
        slug = slugify(category.to_s.gsub("&", " and "))
        slug = TRANSMISSION_SLUGS.fetch(slug, slug)
        slug.end_with?("-parts") ? slug : "#{slug}-parts"
      end

      def slugify(value)
        value.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      end

      def normalize_path(url)
        path = url.to_s.sub(%r{\Ahttps?://[^/]+}, "")
        path = "/#{path}" unless path.start_with?("/")
        path = "#{path}/" unless path.end_with?("/")
        path
      end
    end
  end
end
