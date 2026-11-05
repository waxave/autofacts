# frozen_string_literal: true

RSpec.describe "vehicle category" do
  let(:url) { "/vehicles/nissan/2007/altima/engine-parts/" }
  let(:html) { read_fixture("vehicles/nissan/2007/altima/engine-parts/index.html") }
  let(:listing) { Autofacts::Parsers.parse_vehicle_category(html, url: url) }

  describe ".parse_vehicle_category" do
    it "parses the vehicle context" do
      expect(listing.make).to eq("nissan")
      expect(listing.make_name).to eq("Nissan")
      expect(listing.year).to eq(2007)
      expect(listing.model).to eq("altima")
      expect(listing.model_name).to eq("Altima")
      expect(listing.category).to eq("engine-parts")
      expect(listing.category_name).to eq("Engine")
    end

    it "parses the header metadata" do
      expect(listing.parts_count).to eq(768)
      expect(listing.part_types_count).to eq(71)
      expect(listing.brands_count).to eq(73)
      expect(listing.engine_options_count).to eq(3)
      expect(listing.last_updated).to eq("Catalog updated · Sep 2026")
    end

    it "parses every part across subcategories" do
      expect(listing.count).to eq(768)
      expect(listing.parts.map(&:subcategory).uniq.length).to eq(71)
    end

    it "parses a part with markets, engines, tier and notes" do
      part = listing.parts.find { |p| p.part_number == "76319PS" }

      expect(part.brand_slug).to eq("s-a-gear")
      expect(part.brand).to eq("S.a. Gear")
      expect(part.subcategory).to eq("Balance Shaft Chain")
      expect(part.tier).to eq("Chain Only")
      expect(part.markets).to include("US", "CA", "MX")
      expect(part.engines).to contain_exactly("2.5L L4", "2.5L L4 ELECTRIC/GAS")
      expect(part.notes).to include({ class: nil, attribute: "Includes Chain, Tensioner", unit: nil, value: nil })
      expect(part.notes).to include({ class: nil, attribute: "Does Not Include Sprockets", unit: nil, value: nil })
    end

    it "expands 'Fits: All engines' to every engine option" do
      part = listing.parts.find { |p| p.part_number == "11412" }

      expect(part.engines).to contain_exactly("2.5L L4", "2.5L L4 ELECTRIC/GAS", "3.5L V6")
    end
  end

  describe "scraper" do
    subject(:scraper) { Autofacts::Scrapers::AutofactsDb.new(source: Autofacts::Source::FixtureSource.new(FIXTURES_DIR)) }

    it "builds the path and parses" do
      result = scraper.vehicle_category(make: "nissan", year: 2007, model: "altima", category: "engine")

      expect(result.count).to eq(768)
      expect(result.category_name).to eq("Engine")
      expect(result.category).to eq("engine-parts")
    end
  end

  describe "repository persistence" do
    let(:database) { Autofacts::Database.new(":memory:") }
    let(:repository) { Autofacts::Repository.new(database.db) }

    it "persists makes, vehicles, parts, applications, notes and markets" do
      repository.store_vehicle_category(listing)

      expect(database.db[:vehicle_brands].select_map(:name)).to include("Nissan")
      expect(database.db[:vehicles].count).to eq(3)
      expect(database.db[:parts].count).to eq(768)
      expect(database.db[:part_applications].count).to be > 0
      expect(database.db[:part_attributes].count).to be > 0
      expect(database.db[:part_countries].count).to be > 0

      part = repository.part("s-a-gear", "76319ps")
      expect(part).not_to be_nil
      expect(part.subcategory).to eq({ name: "Balance Shaft Chain", translations: {} })
      expect(part.status).to eq("complete")
      expect(part.applications.length).to eq(6) # 2 engines x 3 markets
      expect(part.applications.map { |application| application[:country_alpha3] }.uniq).to contain_exactly("CAN", "MEX", "USA")

      # Countries are linked to the real catalog (proper names, not the code).
      expect(database.db[:part_countries].count).to be > 0
      us = database.db[:countries].where(code: "US").first
      expect(us[:name]).to eq("United States of America")
    end
  end

  describe "client" do
    let(:database) { Autofacts::Database.new(":memory:") }

    before do
      Autofacts::Seeder.new(Autofacts::Repository.new(database.db), brands_path: nil).seed_categories
    end

    it "scrapes and persists a vehicle category" do
      source = Autofacts::Source::FixtureSource.new(FIXTURES_DIR)
      client = Autofacts::Client.new(database: database, source: source)

      result = client.vehicle(make: "nissan", year: 2007, model: "altima", category: "engine")

      expect(result).to be_a(Autofacts::VehicleCategory)
      expect(result.count).to eq(768)
      expect(database.db[:parts].count).to eq(768)
    end

    it "returns selected vehicle-part fields as symbol-keyed hashes" do
      source = Autofacts::Source::FixtureSource.new(FIXTURES_DIR)
      client = Autofacts::Client.new(database: database, source: source)

      parts = client.vehicle(
        make: "nissan", year: 2007, model: "altima", category: "engine",
        fields: %i[part_number brand subcategory]
      )

      expect(parts).to all(be_a(Hash))
      expect(parts.length).to eq(768)
      expect(parts.first.keys).to contain_exactly(:part_number, :brand, :subcategory)
    end
  end

  describe "category URL slugs" do
    let(:scraper) do
      Autofacts::Scrapers::AutofactsDb.new(source: Autofacts::Source::FixtureSource.new(FIXTURES_DIR))
    end

    def slug_for(name)
      scraper.send(:vehicle_category_slug, name)
    end

    it "uses 'and' for ampersand categories" do
      expect(slug_for("Fuel & Air")).to eq("fuel-and-air-parts")
      expect(slug_for("Body & Lamp Assembly")).to eq("body-and-lamp-assembly-parts")
      expect(slug_for("Brake & Wheel Hub")).to eq("brake-and-wheel-hub-parts")
    end

    it "reorders the transmission categories" do
      expect(slug_for("Automatic Transmission")).to eq("transmission-automatic-parts")
      expect(slug_for("Manual Transmission")).to eq("transmission-manual-parts")
    end

    it "keeps simple category slugs" do
      expect(slug_for("Engine")).to eq("engine-parts")
      expect(slug_for("Cooling System")).to eq("cooling-system-parts")
    end
  end
end
