# frozen_string_literal: true

require "cgi"
require "json"
require "nokogiri"

module Autofacts
  module Scrapers
    # Standalone scraper for the ELGIN catalog (catalog.elginind.com).
    #
    # ELGIN part numbers are resolved to a UUID through the autocomplete JSON
    # endpoint, then the part page is parsed:
    #   GET /part-autocomplete/?q=HL-7025S  -> [{"label":"HL-7025S","value":"<uuid>"}]
    #   GET /engine/part/<uuid>/            -> part detail HTML
    class Elgin < Base
      SOURCE = "elgin"
      DEFAULT_SOURCE_URL = "https://catalog.elginind.com"
      DEFAULT_FIXTURES_DIR = "elgin"

      # Scrape an ELGIN part by its part number (e.g. "HL-7025S").
      def scrape_part(_brand_slug, part_number)
        part_number = part_number.to_s.strip
        uuid = resolve_uuid(part_number)
        raise Error, "ELGIN part #{part_number.inspect} was not found in autocomplete" if uuid.to_s.empty?

        parse_part(fetch_part_page(part_number, uuid), part_number: part_number)
      end

      def scrape(part_number)
        scrape_part(config.fetch("slug", "elgin"), part_number)
      end

      # Resolve a part number to the UUID used by the part page.
      def resolve_uuid(part_number)
        rows = JSON.parse(fetch_autocomplete(part_number))
        entry = Array(rows).find { |row| row.is_a?(Hash) && row["value"] }
        entry && entry["value"]
      rescue JSON::ParserError
        nil
      end

      # Parse an ELGIN part detail page.
      def parse_part(html, part_number:)
        doc = Nokogiri::HTML(html)
        identity = parse_identity(doc, part_number)
        list = parse_list(doc)
        attributes = parse_specifications(doc) + list[:attributes]
        applications = parse_applications(doc)

        Part.new(
          brand_slug: config.fetch("slug", "elgin"),
          part_number: identity[:part_number],
          brand: config.fetch("name", "ELGIN"),
          description: list[:description],
          category: identity[:category],
          subcategory: identity[:subcategory],
          attributes: attributes,
          countries: countries,
          applications: applications,
          applications_count: applications.length,
          status: "complete"
        )
      end

      private

      # Markets this brand's parts are listed for (config override, MX/US default).
      def countries
        Array(config.fetch("countries", %w[MX US])).map { |code| code.to_s.upcase }.reject(&:empty?).uniq
      end

      def fixtures_dir
        config.fetch("fixtures_dir", DEFAULT_FIXTURES_DIR)
      end

      def source_url
        config.fetch("source_url", DEFAULT_SOURCE_URL).sub(%r{/\z}, "")
      end

      def fetch_autocomplete(part_number)
        if source.is_a?(Source::FixtureSource)
          source.get("/#{fixtures_dir}/#{part_number}/autocomplete.html")
        else
          source.get("#{source_url}/part-autocomplete/?q=#{CGI.escape(part_number)}")
        end
      end

      def fetch_part_page(part_number, uuid)
        if source.is_a?(Source::FixtureSource)
          source.get("/#{fixtures_dir}/#{part_number}/index.html")
        else
          source.get("#{source_url}/engine/part/#{uuid}/")
        end
      end

      # "HL-7025S | Lifters/Tappets | Engine Part"
      def parse_identity(doc, fallback_part_number)
        segments = doc.at_css("title")&.text.to_s.split("|").map(&:strip)
        part_number = presence(segments[0]) || fallback_part_number
        subcategory = presence(segments[1])
        category = presence(segments[2])&.sub(/\s+Part\z/i, "")

        {
          part_number: part_number,
          category: category || "Engine",
          subcategory: subcategory || presence(doc.at_css("main h2")&.text)
        }
      end

      # main > div > ul.list-unstyled: "Label: Value" items plus the marketing
      # description (which becomes Part#description).
      def parse_list(doc)
        list = doc.at_css("main > div > ul.list-unstyled") || doc.at_css("main ul.list-unstyled")
        attributes = []
        description = nil
        return { attributes: attributes, description: description } unless list

        list.css("li").each do |item|
          span = item.at_css("span")
          next unless span

          label = span.text.to_s.sub(/:\s*\z/, "").strip
          value = item.text.to_s.sub(span.text.to_s, "").strip
          next if label.empty? || value.empty?

          if label.casecmp?("Marketing Description")
            description = value
          else
            attributes << { class: nil, attribute: label, unit: nil, value: value }
          end
        end

        { attributes: attributes, description: description }
      end

      # #specifications-table: two-column "Specification Type / Data" rows.
      # "<Name> UOM" rows become the unit of the matching "<Name>" attribute.
      def parse_specifications(doc)
        table = doc.at_css("#specifications-table")
        return [] unless table

        rows = table.css("tbody tr").filter_map do |row|
          cells = row.css("td")
          next unless cells.length >= 2

          [cells[0].text.strip, cells[1].text.strip]
        end
        names = rows.map(&:first)
        units = rows.each_with_object({}) do |(name, value), hash|
          base = name.sub(/\s+UOM\z/i, "")
          hash[base] = value if base != name
        end

        rows.filter_map do |name, value|
          next if name.empty? || value.empty?
          # Drop UOM rows that were merged into their base attribute.
          next if name.match?(/\s+UOM\z/i) && names.include?(name.sub(/\s+UOM\z/i, ""))

          { class: nil, attribute: name, unit: units[name], value: value }
        end
      end

      # #applications-table: Manufacturer (make), Engine, Year range.
      # Ranges expand into one Vehicle per year.
      def parse_applications(doc)
        table = doc.at_css("#applications-table")
        return [] unless table

        table.css("tbody tr").flat_map do |row|
          cells = row.css("td")
          next [] if cells.length < 3

          make = cells[0].text.strip
          engine = cells[1].text.strip
          years = expand_years(cells[2].text.strip)
          years.map { |year| Vehicle.new(year: year, make: make, model: nil, engine: engine) }
        end
      end

      # "1999–16" -> 1999..2016, "2005" -> 2005, "" -> [].
      def expand_years(value)
        text = value.to_s.strip
        return [text.to_i] if text.match?(/\A\d{4}\z/)

        match = text.match(/\A(\d{4})\s*[–—\-]\s*(\d{2}|\d{4})\z/)
        return [] unless match

        start_year = match[1].to_i
        end_raw = match[2]

        end_year =
          if end_raw.length == 4
            end_raw.to_i
          else
            candidate = (start_year / 100 * 100) + end_raw.to_i
            candidate < start_year ? candidate + 100 : candidate
          end

        (start_year..end_year).to_a
      end

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
