# frozen_string_literal: true

require "nokogiri"

module Autofacts
  module Scrapers
    # Standalone scraper for the FRACO brand (simepa.mx).
    #
    # Given a part number (JGO), it fetches two pages:
    #   * ModComp.php?JGO=...  -> component attributes
    #   * ModAplic.php?JGO=... -> fitment applications
    class Fraco < Base
      SOURCE = "fraco"

      # Scrape a FRACO part by its part number (JGO).
      def scrape(part_number)
        attributes_html = fetch_page(part_number, "attributes")
        applications_html = fetch_page(part_number, "applications")

        attributes = parse_attributes(attributes_html)
        applications = parse_applications(applications_html)
        extra_attributes = applications.flat_map { |app| app[:attributes] }.uniq

        Part.new(
          brand_slug: config.fetch("slug", "fraco"),
          part_number: part_number,
          brand: config.fetch("name", "FRACO"),
          attributes: attributes + extra_attributes,
          countries: countries,
          applications: build_vehicles(applications),
          status: "complete"
        )
      end

      def scrape_part(_brand_slug, part_number)
        scrape(part_number)
      end

      # Parse the component/attributes table (#TAbContPorJgo).
      def parse_attributes(html)
        doc = Nokogiri::HTML(html)
        table = doc.at_css("#TAbContPorJgo")
        return [] unless table

        table.css("tr").drop(1).filter_map do |row|
          cells = row.css("td")
          next if cells.length < 3

          attribute = text(cells[1])
          next if attribute.empty?

          {
            class: presence(input_value(cells[0]) || text(cells[0])),
            attribute: attribute,
            unit: nil,
            value: presence(text(cells[2]))
          }
        end
      end

      # Parse the fitment/applications table (body > table).
      def parse_applications(html)
        doc = Nokogiri::HTML(html)
        table = doc.at_css("body > table") || doc.at_css("table")
        return [] unless table

        table.css("tr").drop(1).filter_map do |row|
          cells = row.css("td")
          next if cells.length < 7

          brand = titleize(text(cells[0]))
          model = text(cells[1])
          next if brand.empty? || model.empty?

          {
            brand: brand,
            model: model,
            years: years_from(text(cells[2])),
            engine: build_engine(text(cells[3]), text(cells[4])),
            attributes: [text(cells[5]), text(cells[6])].reject(&:empty?).map do |value|
              { class: nil, attribute: value, unit: nil, value: nil }
            end
          }
        end
      end

      private

      # Markets this brand's parts are listed for (config override, MX/US default).
      def countries
        Array(config.fetch("countries", %w[MX US])).map { |code| code.to_s.upcase }.reject(&:empty?).uniq
      end

      def fetch_page(part_number, page)
        if source.is_a?(Source::FixtureSource)
          source.get("/#{fixtures_dir}/#{part_number}/#{page}.html")
        else
          file = page == "attributes" ? "ModComp.php" : "ModAplic.php"
          source.get("#{source_url}/#{file}?JGO=#{part_number}")
        end
      end

      def fixtures_dir
        config.fetch("fixtures_dir", "fraco")
      end

      def source_url
        config.fetch("source_url", "https://simepa.mx/Simepa.mx/admin/buscador").sub(%r{/\z}, "")
      end

      def build_vehicles(applications)
        applications.flat_map do |application|
          application[:years].map do |year|
            Vehicle.new(year: year, make: application[:brand], model: application[:model], engine: application[:engine])
          end
        end
      end

      def years_from(value)
        value.to_s.scan(/\d{4}/).map(&:to_i)
      end

      def build_engine(liters, motor_type)
        [liters.to_s.sub(/\.\s*\z/, "").strip, motor_type.to_s.strip].reject(&:empty?).join(" ")
      end

      def titleize(value)
        value.to_s.gsub(/\s+/, " ").strip.split(/\s+/).map(&:capitalize).join(" ")
      end

      def text(node)
        node ? node.text.gsub(/\s+/, " ").strip : ""
      end

      def input_value(node)
        input = node&.at_css("input")
        input && input["value"].to_s.strip
      end

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
