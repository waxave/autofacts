# frozen_string_literal: true

RSpec.describe Autofacts::Repository do
  let(:database) { Autofacts::Database.new(":memory:") }
  let(:repository) { described_class.new(database.db) }

  let(:brand) do
    Autofacts::PartBrand.new(
      slug: "gm-genuine",
      name: "GM Genuine",
      url: "https://autofactsdb.com/part/gm-genuine/",
      part_numbers_count: 1_243_293,
      popular: true
    )
  end

  let(:index) do
    Autofacts::BrandIndex.new(
      brands: [brand],
      last_updated: "Catalog updated · Sep 2026",
      last_refreshed_at: "Application data last refreshed Sep 26, 2026 (UTC)",
      brand_count: 504,
      part_numbers_count: 20_858_993
    )
  end

  it "is not complete before any scrape" do
    expect(repository.complete?(described_class::PART_BRANDS_TYPE, described_class::INDEX_KEY)).to be(false)
  end

  it "stores a brand index and marks it complete" do
    repository.store_brand_index(index)

    expect(repository.complete?(described_class::PART_BRANDS_TYPE, described_class::INDEX_KEY)).to be(true)
    expect(repository.part_brands.length).to eq(1)
    expect(repository.part_brands.first.name).to eq("GM Genuine")
  end

  it "upserts by slug instead of duplicating" do
    repository.store_brand_index(index)
    repository.store_brand_index(index)

    expect(repository.part_brands.length).to eq(1)
  end

  it "updates an existing brand's attributes on re-scrape" do
    repository.store_brand_index(index)

    updated = Autofacts::BrandIndex.new(
      brands: [
        Autofacts::PartBrand.new(
          slug: "gm-genuine",
          name: "GM Genuine",
          url: "https://autofactsdb.com/part/gm-genuine/",
          part_numbers_count: 1_300_000,
          popular: false
        )
      ],
      last_updated: "Catalog updated · Oct 2026",
      last_refreshed_at: nil,
      brand_count: 505,
      part_numbers_count: 21_000_000
    )
    repository.store_brand_index(updated)

    stored = repository.part_brands.first
    expect(stored.part_numbers_count).to eq(1_300_000)
    expect(stored.popular).to be(false)
  end

  it "stores original and normalized part numbers separately" do
    repository.store_part(Autofacts::Part.new(
      brand_slug: "gm-genuine",
      part_number: "9-1234",
      normalized_part_number: "91234",
      brand: "GM Genuine",
      status: "complete"
    ))

    part = repository.part("gm-genuine", "9-1234")

    expect(part.part_number).to eq("9-1234")
    expect(part.normalized_part_number).to eq("91234")
  end

  it "rebuilds the brand index with metadata" do
    repository.store_brand_index(index)

    rebuilt = repository.brand_index
    expect(rebuilt.brands.length).to eq(1)
    expect(rebuilt.last_updated).to eq("Catalog updated · Sep 2026")
    expect(rebuilt.last_refreshed_at).to eq("Application data last refreshed Sep 26, 2026 (UTC)")
    expect(rebuilt.brand_count).to eq(504)
    expect(rebuilt.part_numbers_count).to eq(20_858_993)
  end

  it "marks an empty scrape as empty, not complete" do
    repository.store_brand_index(Autofacts::BrandIndex.new(brands: []))

    expect(repository.complete?(described_class::PART_BRANDS_TYPE, described_class::INDEX_KEY)).to be(false)
    expect(repository.part_brands).to be_empty
  end

  it "orders brands and countries ascending by name" do
    repository.upsert_brand(Autofacts::PartBrand.new(slug: "zeta", name: "zeta"))
    repository.upsert_brand(Autofacts::PartBrand.new(slug: "alpha", name: "Alpha"))
    repository.upsert_country(Autofacts::Country.new(code: "ZZ", name: "zulu"))
    repository.upsert_country(Autofacts::Country.new(code: "AA", name: "Alpha"))

    expect(repository.part_brands.map(&:name)).to eq(["Alpha", "zeta"])
    expect(repository.countries.map(&:name)).to eq(["Alpha", "zulu"])
  end

  it "searches brands by exact normalized aliases" do
    repository.upsert_brand(Autofacts::PartBrand.new(
      slug: "hastings",
      name: "Hastings Manufacturing",
      aliases: ["Hastings Parts"]
    ))

    expect(repository.search_brands("hastings").map(&:slug)).to eq(["hastings"])
    expect(repository.search_brands("HASTINGS PARTS").map(&:slug)).to eq(["hastings"])
    expect(repository.search_brands("hastings part")).to eq([])
    expect(repository.search_brands("asting parts")).to eq([])
    expect(repository.part_brand("hastings").aliases).to eq(["Hastings Parts"])
  end

  describe "part detail" do
    let(:part) do
      Autofacts::Parsers.parse_part_detail(
        read_fixture("part/hastings-manufacturing/2c4504/index.html"),
        url: "/part/hastings-manufacturing/2c4504/"
      )
    end

    it "stores and reads a complete part with per-country applications" do
      repository.store_part(part)

      stored = repository.part("hastings-manufacturing", "2c4504")
      expect(stored.status).to eq("complete")
      expect(stored.brand).to eq("Hastings Manufacturing")
      expect(stored.applications.length).to eq(80) # 40 vehicles x 2 markets
      expect(stored.applications_count).to eq(80)
      expect(stored.applications.map { |application| application[:country_code] }.uniq).to contain_exactly("CA", "US")
      expect(stored.applications.map { |application| application[:country_alpha3] }.uniq).to contain_exactly("CAN", "USA")

      sample = stored.applications.find { |application| application[:year] == 2010 }
      expect(sample).to include(make: "KIA", model: "Soul", engine: "1.6L L4")

      expect(stored.countries).to contain_exactly("CA", "US")
      expect(stored.attributes).to include({ class: nil, attribute: "Full Set", unit: nil, value: nil })
      expect(stored.attributes_count).to eq(stored.attributes.length)
      expect(stored.makes).to contain_exactly("KIA", "Hyundai")
      expect(stored.years_range).to eq([2010, 2022])
    end

    it "marks the part scrape complete" do
      repository.store_part(part)

      expect(repository.complete?(described_class::PART_TYPE, "hastings-manufacturing/2c4504")).to be(true)
    end

    it "stores the prose description" do
      repository.store_part(part)

      stored = repository.part("hastings-manufacturing", "2c4504")
      expect(stored.description).to start_with("Hastings Manufacturing part number 2C4504")
    end

    it "links part countries to the countries catalog" do
      repository.store_part(part)

      expect(database.db[:part_countries].select_map(:country_code)).to contain_exactly("CA", "US")
      expect(database.db[:countries].select_map(:code)).to include("US", "CA")
      expect(database.db.foreign_key_list(:part_countries)).to include(
        hash_including(columns: [:country_code], table: :countries)
      )
    end

    it "is idempotent" do
      repository.store_part(part)
      repository.store_part(part)

      expect(database.db[:part_applications].count).to eq(40)
      expect(database.db[:vehicles].count).to eq(40)
      expect(database.db[:vehicle_brands].count).to eq(2)
    end
  end

  describe "search results" do
    let(:part) do
      Autofacts::Parsers.parse_part_detail(
        read_fixture("part/hastings-manufacturing/2c4504/index.html"),
        url: "/part/hastings-manufacturing/2c4504/"
      )
    end

    it "stores search results as partial, then completes them when the detail is scraped" do
      result = Autofacts::SearchResult.new(brand_slug: "hastings-manufacturing", part_number: "2c4504")
      repository.store_search_results(Autofacts::SearchResults.new(query: "2C45", parts: [result]))

      expect(repository.search_results.first.status).to eq("partial")

      repository.store_part(part)

      expect(repository.search_results.first.status).to eq("complete")
    end

    it "marks search results complete even when the part was scraped first" do
      repository.store_part(part)

      result = Autofacts::SearchResult.new(brand_slug: "hastings-manufacturing", part_number: "2c4504")
      repository.store_search_results(Autofacts::SearchResults.new(query: "2C45", parts: [result]))

      expect(repository.search_results.first.status).to eq("complete")
    end

    it "persists the result attributes and applications" do
      result = Autofacts::SearchResult.new(
        brand_slug: "acme",
        part_number: "ab-1",
        description: "Widget",
        attributes: ["Color: Black"],
        applications: [{ year: 2020, vehicle: "Ford Focus", engine: "2.0L L4" }]
      )

      repository.store_search_results(Autofacts::SearchResults.new(query: "AB", parts: [result]))
      stored = repository.search_results.first

      expect(stored.description).to eq("Widget")
      expect(stored.attributes).to eq(["Color: Black"])
      expect(stored.applications).to eq([{ "year" => 2020, "vehicle" => "Ford Focus", "engine" => "2.0L L4" }])
    end
  end

  describe "translations" do
    it "stores and updates a translation by key" do
      repository.set_translation(translatable_type: "part", translatable_id: 1, field: "category", locale: "es", text: "Motor")
      repository.set_translation(translatable_type: "part", translatable_id: 1, field: "category", locale: "es", text: "Motor (revisado)")

      expect(repository.translation("part", 1, "category", "es")).to eq("Motor (revisado)")
      expect(repository.translations_for("part", 1).length).to eq(1)
    end

    it "returns category/subcategory translations and localizes attribute names" do
      part = Autofacts::Parsers.parse_part_detail(
        read_fixture("part/hastings-manufacturing/2c4504/index.html"),
        url: "/part/hastings-manufacturing/2c4504/"
      )
      repository.store_part(part)

      category = database.db[:categories].first
      subcategory = database.db[:subcategories].first
      attribute = database.db[:part_attributes].first

      repository.set_translation(translatable_type: "category", translatable_id: category[:id], field: "name", locale: "es", text: "Motor")
      repository.set_translation(translatable_type: "subcategory", translatable_id: subcategory[:id], field: "name", locale: "es", text: "Segmento de pistón")
      repository.set_translation(translatable_type: "part_attribute", translatable_id: attribute[:id], field: "name", locale: "es", text: "Juego completo")

      localized = repository.part("hastings-manufacturing", "2c4504", locale: "es")
      expect(localized.category).to eq({ name: "Engine", translations: { es: "Motor" } })
      expect(localized.subcategory).to eq({ name: "Piston Ring", translations: { es: "Segmento de pistón" } })
      expect(localized.attributes.first[:attribute]).to eq("Juego completo")
    end
  end

  describe "lookups by part number" do
    let(:part) do
      Autofacts::Parsers.parse_part_detail(
        read_fixture("part/hastings-manufacturing/2c4504/index.html"),
        url: "/part/hastings-manufacturing/2c4504/"
      )
    end

    it "finds parts by part number case-insensitively" do
      repository.store_part(part)

      found = repository.parts_by_part_number("2C4504")
      expect(found.length).to eq(1)
      expect(found.first.brand_slug).to eq("hastings-manufacturing")
    end

    it "finds search results by part number case-insensitively" do
      result = Autofacts::SearchResult.new(brand_slug: "acme", part_number: "ab-1")
      repository.store_search_results(Autofacts::SearchResults.new(query: "AB", parts: [result]))

      expect(repository.search_results_by_part_number("AB-1").length).to eq(1)
    end
  end
end
