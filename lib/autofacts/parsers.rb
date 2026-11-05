# frozen_string_literal: true

require "nokogiri"
require "set"
require "json"

module Autofacts
  # HTML parsers. Each parser turns a saved page into plain Ruby model objects.
  module Parsers
    module_function

    # Parse the part-brands index page (/part/).
    #
    # Returns a BrandIndex with the full A-Z brand list (each carrying its URL
    # and slug) plus the catalog metadata ("Catalog updated", brand count and
    # part-number count) shown in the page hero.
    def parse_brand_index(html)
      doc = Nokogiri::HTML(html)

      popular_slugs = Set.new
      popular = doc.at_css("#popular-brands-section")
      if popular
        popular.css(".brand-card").each do |card|
          slug = slug_from_url(card["href"])
          popular_slugs.add(slug) unless slug.empty?
        end
      end

      brands = []
      all = doc.at_css("#all-brands")
      if all
        all.css(".brand-card").each do |card|
          slug = slug_from_url(card["href"])
          next if slug.empty?

          brands << PartBrand.new(
            slug: slug,
            name: node_text(card.at_css(".brand-card-name")),
            url: card["href"].to_s.empty? ? nil : card["href"].to_s,
            part_numbers_count: parse_part_count(node_text(card.at_css(".small.muted"))),
            popular: popular_slugs.include?(slug)
          )
        end
      end

      meta = parse_catalog_meta(doc)

      BrandIndex.new(
        brands: brands,
        last_updated: meta[:last_updated],
        last_refreshed_at: meta[:last_refreshed_at],
        brand_count: meta[:brand_count],
        part_numbers_count: meta[:part_numbers_count]
      )
    rescue Nokogiri::XML::SyntaxError => e
      raise ParseError, "Failed to parse brand index: #{e.message}"
    end

    # Extract the slug from an absolute brand URL, e.g.
    # "https://autofactsdb.com/part/gm-genuine/" -> "gm-genuine".
    def slug_from_url(url)
      uri = url.to_s.strip
      return "" if uri.empty?

      path = uri.sub(%r{\Ahttps?://[^/]+}, "") # strip scheme + host
      path = path.split("?", 2).first         # strip query string
      path.split("/").reject(&:empty?).last.to_s
    end

    def parse_catalog_meta(doc)
      hero = doc.at_xpath('//*[@id="main"]/div/div[1]/p')
      return {} unless hero

      badge = hero.at_css(".badge--verified")
      text = node_text(hero)

      {
        last_updated: badge ? node_text(badge) : nil,
        last_refreshed_at: badge ? badge["title"] : nil,
        brand_count: parse_count(text, /(\d[\d,]*)\s*Brands?\b/i),
        part_numbers_count: parse_count(text, /(\d[\d,]*)\s*[Pp]art numbers?\b/i)
      }
    end

    # Parse an integer out of "1,243,293 part numbers".
    def parse_part_count(text)
      match = text.to_s.match(/([\d,]+)\s*part numbers?\b/i)
      match ? match[1].delete(",").to_i : nil
    end

    def parse_count(text, pattern)
      match = text.to_s.match(pattern)
      match ? match[1].delete(",").to_i : nil
    end

    # Parse a part-number search results page (/search/?q=...).
    #
    # Returns a SearchResults with the matched parts, the reported count and the
    # next-page URL.
    def parse_search_results(html, query:, page: 1)
      doc = Nokogiri::HTML(html)

      parts = doc.css(".search-result").filter_map { |card| parse_search_result(card) }
      meta = search_meta(doc)

      SearchResults.new(
        query: query,
        page: page,
        parts: parts,
        next_page_url: meta[:next_page_url],
        result_count: meta[:result_count]
      )
    rescue Nokogiri::XML::SyntaxError => e
      raise ParseError, "Failed to parse search results: #{e.message}"
    end

    def parse_search_result(card)
      link = card.at_css("a.card")
      return nil unless link

      href = link["href"].to_s
      brand_slug, part_number = brand_slug_and_part_number(href)
      strong = node_text(link.at_css("strong"))
      brand = brand_from_strong(strong)

      divs = link.element_children.select { |node| node.name == "div" }
      category, subcategory = split_on_middle_dot(node_text(divs[0]))
      # Applications keep their raw whitespace: entries are separated by a dot
      # padded with two spaces, which node_text would collapse.
      applications, applications_count = split_applications(divs[1] ? divs[1].text : "")

      SearchResult.new(
        brand_slug: brand_slug,
        part_number: part_number,
        brand: brand,
        description: presence(strong),
        category: category,
        subcategory: subcategory,
        url: presence(href),
        applications: applications,
        applications_count: applications_count,
        attributes: split_attributes(node_text(divs[2]))
      )
    rescue StandardError
      nil
    end

    def search_meta(doc)
      nav = doc.at_css("#main section nav.chip-row")
      next_link = nav&.at_css("a[rel='next']")
      count_text = node_text(doc.at_css("#main section > p.muted"))

      {
        next_page_url: next_link && presence(next_link["href"]),
        result_count: parse_count(count_text, /(\d[\d,]*)\s*parts?\b/i)
      }
    end

    # Extract the canonical brand slug and part number from a part URL:
    # "/part/hastings-manufacturing/2c4504/" -> ["hastings-manufacturing", "2c4504"].
    def brand_slug_and_part_number(href)
      segments = href.to_s.sub(%r{\Ahttps?://[^/]+}, "").split("/").reject(&:empty?)
      return [nil, nil] if segments.length < 2

      [segments[-2], segments[-1]]
    end

    # Extract the brand from a search card's <strong> ("Brand MPN — Type").
    def brand_from_strong(text)
      head = text.to_s.split(/\s+—\s+/, 2).first.to_s
      tokens = head.split
      tokens.pop # the last token is the display part number

      presence(tokens.join(" "))
    end

    def split_on_middle_dot(text)
      parts = text.to_s.split(" · ", 2).map(&:strip)
      [presence(parts[0]), presence(parts[1])]
    end

    def split_applications(text)
      value = text.to_s.strip
      count = nil

      if (match = value.match(/\+\s*(\d[\d,]*)\s*more/i))
        count = match[1].delete(",").to_i
        value = value[0...match.begin(0)]
      end

      value = value.sub(/\AFits:\s*/i, "").strip
      # Applications are separated by a dot padded with two or more spaces; the
      # vehicle/engine dot inside an application uses single spaces.
      applications = value.split(/\s{2,}·\s{2,}/).filter_map { |entry| parse_application(entry) }
      [applications, count]
    end

    # Parse one application ("2017 Hyundai Accent · 1.6L L4").
    #
    # The vehicle part is kept whole (`year` + `vehicle`) because make/model
    # cannot be split reliably without a makes dictionary; the engine follows
    # the " · " separator.
    def parse_application(text)
      vehicle, engine = text.to_s.split(" · ", 2).map(&:strip)
      return nil if vehicle.to_s.empty?

      tokens = vehicle.split
      year_token = tokens.first.to_s
      year = year_token.match?(/\A\d+\z/) ? year_token.to_i : nil
      vehicle_name = year ? tokens[1..].join(" ") : tokens.join(" ")

      { year: year, vehicle: presence(vehicle_name), engine: presence(engine) }
    end

    def split_attributes(text)
      text.to_s.split(/[;|]/).map(&:strip).reject(&:empty?)
    end

    # Parse a part detail page (/part/BRAND/MPN/).
    def parse_part_detail(html, url:)
      doc = Nokogiri::HTML(html)
      container = doc.at_css(".part-detail")
      raise ParseError, "Could not find part detail container" unless container

      brand_slug, part_number = brand_slug_and_part_number(url)
      facts = parse_quick_facts(container)
      header = parse_detail_header(container)

      Part.new(
        brand_slug: brand_slug,
        part_number: part_number,
        brand: facts[:brand],
        description: parse_part_description(container),
        category: header[:category],
        subcategory: facts[:subcategory],
        grade: header[:grade],
        url: absolute_url(url),
        attributes: parse_part_attributes(container),
        countries: parse_part_countries(container),
        applications: parse_part_applications(doc),
        applications_count: facts[:applications_count],
        years_range: facts[:years_range],
        makes: facts[:makes] || [],
        status: "complete"
      )
    rescue Nokogiri::XML::SyntaxError => e
      raise ParseError, "Failed to parse part detail: #{e.message}"
    end

    def parse_quick_facts(container)
      facts = { makes: [] }

      container.css("dl.quick-facts .quick-facts__row").each do |row|
        label = node_text(row.at_css("dt")).downcase
        value = node_text(row.at_css("dd"))

        case label
        when "brand" then facts[:brand] = presence(value)
        when "part number" then facts[:part_number] = presence(value)
        when "type" then facts[:subcategory] = presence(value)
        when "verified fitment" then facts[:applications_count] = parse_count(value, /(\d[\d,]*)\s*configurations?/i)
        when "years" then facts[:years_range] = presence(value)
        when "makes" then facts[:makes] = split_makes(value)
        end
      end

      facts
    end

    def split_makes(value)
      value.to_s.split(/\s+and\s+|,\s*/i).map(&:strip).reject(&:empty?)
    end

    def parse_detail_header(container)
      header = container.at_css("header")
      meta = header&.at_css("p")
      spans = meta ? meta.element_children.select { |node| node.name == "span" } : []
      badge = spans.find { |span| span["class"].to_s.include?("badge--verified") }

      {
        description: presence(node_text(header&.at_css(".h1-type"))),
        category: presence(node_text(spans[1])),
        grade: presence(node_text(spans[2]).sub(/\A·\s*/, "")),
        last_updated: presence(node_text(badge)),
        last_refreshed_at: badge && badge["title"]
      }
    end

    def parse_part_attributes(container)
      container.css(".spec-card .note-pill").filter_map do |pill|
        text = node_text(pill)
        next if text.empty?

        name, value = text.split(": ", 2)
        { class: nil, attribute: name.to_s.strip, unit: nil, value: presence(value) }
      end
    end

    # The prose description paragraph on the detail page.
    def parse_part_description(container)
      presence(node_text(container.at_css("div.prose.part-prose")))
    end

    def parse_part_countries(container)
      container.css(".part-markets .market-badge").filter_map { |badge| presence(badge["data-market"]) }
    end

    def parse_part_applications(doc)
      table = doc.at_css("#fitment table")
      return [] unless table

      table.css("tbody tr").filter_map do |row|
        cells = row.css("td")
        next unless cells.length >= 4

        year_value = cell_value(cells[0])
        Vehicle.new(
          year: year_value.to_s.match?(/\A\d+\z/) ? year_value.to_i : nil,
          make: cell_value(cells[1]),
          model: cell_value(cells[2]),
          engine: cell_value(cells[3])
        )
      end
    end

    def cell_value(cell)
      presence(cell["data-value"]) || presence(node_text(cell))
    end

    def absolute_url(path)
      value = path.to_s
      return value if value.start_with?("http")

      "#{BASE_URL}#{value.start_with?("/") ? "" : "/"}#{value}"
    end

    def presence(value)
      value = value.to_s.strip
      value.empty? ? nil : value
    end

    # Parse a vehicle category page (/vehicles/MAKE/YEAR/MODEL/CATEGORY/).
    def parse_vehicle_category(html, url:)
      doc = Nokogiri::HTML(html)
      container = doc.at_css("#main div.container") || doc.at_css("#main")
      raise ParseError, "Could not find vehicle category container" unless container

      context = parse_vehicle_context(doc, url)
      meta = parse_vehicle_meta(container)

      VehicleCategory.new(
        make: context[:make_slug],
        year: context[:year],
        model: context[:model_slug],
        category: context[:category_slug],
        make_name: context[:make_name],
        model_name: context[:model_name],
        category_name: context[:category_name],
        title: presence(node_text(container.at_css("h1"))),
        parts_count: meta[:parts_count],
        part_types_count: meta[:part_types_count],
        brands_count: meta[:brands_count],
        engine_options_count: meta[:engine_options_count],
        last_updated: meta[:last_updated],
        parts: parse_vehicle_parts(doc)
      )
    rescue Nokogiri::XML::SyntaxError => e
      raise ParseError, "Failed to parse vehicle category: #{e.message}"
    end

    def parse_vehicle_context(doc, url)
      links = doc.css("#main nav.breadcrumbs a")
      make_link = links[2]
      year_link = links[3]
      model_link = links[4]
      category_span = doc.css("#main nav.breadcrumbs span").last
      segments = url.to_s.sub(%r{\Ahttps?://[^/]+}, "").split("/").reject(&:empty?)

      {
        make_slug: slug_from_url(make_link && make_link["href"]),
        make_name: presence(node_text(make_link)),
        year: parse_count(node_text(year_link), /(\d{4})/),
        model_slug: slug_from_url(model_link && model_link["href"]),
        model_name: presence(node_text(model_link)),
        category_slug: presence(segments.last),
        category_name: presence(node_text(category_span).sub(/\s+Parts\z/i, ""))
      }
    end

    def parse_vehicle_meta(container)
      meta = container.at_css("p.archive-meta")
      text = node_text(meta)
      badge = meta && meta.at_css(".badge--verified")

      {
        last_updated: presence(node_text(badge)),
        parts_count: parse_count(text, /(\d[\d,]*)\s*Parts?\b/i),
        part_types_count: parse_count(text, /(\d[\d,]*)\s*Part types?\b/i),
        brands_count: parse_count(text, /(\d[\d,]*)\s*Brands?\b/i),
        engine_options_count: parse_count(text, /(\d[\d,]*)\s*engine options?/i)
      }
    end

    ALL_ENGINES_MARKER = "*"

    def parse_vehicle_parts(doc)
      article = doc.at_css("#main article")
      return [] unless article

      notes = parse_fitment_notes(doc)

      parts = article.css("section.subcat-section").flat_map do |section|
        subcategory_slug = presence(section["id"])
        subcategory_name = presence(node_text(section.at_css("h2")))

        section.css(".tier-block").flat_map do |tier_block|
          tier = presence(node_text(tier_block.at_css(".tier-heading")))

          tier_block.css("table.parts tbody tr").filter_map do |row|
            parse_vehicle_part_row(row, subcategory_slug, subcategory_name, tier, notes)
          end
        end
      end

      # "Fits: All engines" rows apply to every engine offered for this vehicle.
      concrete_engines = (parts.flat_map(&:engines).uniq - [ALL_ENGINES_MARKER])
      parts.each do |part|
        part.engines = concrete_engines if part.engines.include?(ALL_ENGINES_MARKER)
      end
      parts
    end

    def parse_vehicle_part_row(row, subcategory_slug, subcategory_name, tier, notes)
      brand_link = row.at_css("a.brand-link")
      pn_link = row.at_css("a.pn-link")
      return nil unless brand_link && pn_link

      VehiclePart.new(
        brand_slug: slug_from_url(brand_link["href"]),
        brand: presence(node_text(brand_link)),
        part_number: presence(node_text(pn_link)),
        url: presence(pn_link["href"]),
        subcategory: subcategory_name,
        subcategory_slug: subcategory_slug,
        tier: tier,
        markets: parse_markets(row),
        notes: parse_row_notes(row, notes),
        engines: row.css(".engine-pill").map { |pill| engine_value(pill) }.reject(&:empty?)
      )
    end

    def engine_value(pill)
      text = node_text(pill)
      if pill["class"].to_s.include?("engine-pill--all") || text.match?(/All engines/i)
        ALL_ENGINES_MARKER
      else
        text
      end
    end

    def parse_markets(row)
      row.css(".market-badge").filter_map { |badge| presence(badge["data-market"]) }
    end

    def parse_row_notes(row, notes_map)
      inline = row.css(".notes-inline .note-pill").filter_map { |pill| note_pair(node_text(pill)) }

      button = row.at_css(".notes-inline .notes-more")
      full =
        if button
          groups = notes_map[button["data-notes-target"]]
          Array(groups).flatten.filter_map { |text| note_pair(text) }
        else
          []
        end

      (inline + full).uniq
    end

    def note_pair(text)
      value = text.to_s.strip
      return nil if value.empty?

      name, val = value.split(": ", 2)
      { class: nil, attribute: name.to_s.strip, unit: nil, value: presence(val) }
    end

    def parse_fitment_notes(doc)
      script = doc.at_css("script#fitment-notes")
      return {} unless script

      parsed = JSON.parse(script.text)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    # Nokogiri helper: collapse whitespace and strip.
    def node_text(node)
      return "" if node.nil?

      node.text.gsub(/\s+/, " ").strip
    end
  end
end
