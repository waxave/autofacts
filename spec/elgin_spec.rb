# frozen_string_literal: true

RSpec.describe Autofacts::Scrapers::Elgin do
  let(:source) { Autofacts::Source::FixtureSource.new(FIXTURES_DIR) }
  let(:scraper) { described_class.new(source: source) }

  describe "#resolve_uuid" do
    it "resolves the part number through the autocomplete JSON" do
      expect(scraper.resolve_uuid("HL-7025S")).to eq("41add5cf-f231-4fc7-8d33-1ff2b890cb08")
    end
  end

  describe "#scrape_part" do
    let(:part) { scraper.scrape_part("elgin", "HL-7025S") }

    it "parses the part identity" do
      expect(part).to be_a(Autofacts::Part)
      expect(part.brand_slug).to eq("elgin")
      expect(part.brand).to eq("ELGIN")
      expect(part.part_number).to eq("HL-7025S")
      expect(part.category).to eq("Engine")
      expect(part.subcategory).to eq("Lifters/Tappets")
      expect(part.countries).to contain_exactly("MX", "US")
      expect(part.status).to eq("complete")
    end

    it "parses the marketing description" do
      expect(part.description).to start_with("Elevate your engine's performance")
    end

    it "parses list attributes and specifications, merging UOM into unit" do
      attributes = part.attributes

      expect(attributes).to include({ class: nil, attribute: "Product Line", unit: nil, value: "Engine Valve Lifter" })
      expect(attributes).to include({ class: nil, attribute: "UPC", unit: nil, value: "013122426245" })
      expect(attributes).to include({ class: nil, attribute: "Length", unit: "IN", value: "3.880" })
      expect(attributes).to include({ class: nil, attribute: "Maximum Outside Diameter", unit: "IN", value: "0.842" })
      expect(attributes).to include({ class: nil, attribute: "Lifter Type", unit: nil, value: "Hydraulic" })
      expect(attributes.map { |attribute| attribute[:attribute] }).not_to include("Length UOM")
    end

    it "expands year ranges into one application per year" do
      applications = part.applications

      expect(applications).to all(be_a(Autofacts::Vehicle))
      expect(applications.map(&:year).minmax).to eq([1999, 2025])
      expect(applications.map(&:make).uniq).to include("BUICK", "CADILLAC", "CHEVROLET")

      buick = applications.select { |application| application.make == "BUICK" }
      expect(buick.map(&:year)).to eq((1999..2016).to_a)
      expect(buick.first.engine).to include("325CID")
    end
  end
end

RSpec.describe "ELGIN client dispatch" do
  let(:database) { Autofacts::Database.new(":memory:") }

  it "resolves, scrapes and persists the part" do
    source = Autofacts::Source::FixtureSource.new(FIXTURES_DIR)
    client = Autofacts::Client.new(database: database, source: source, brand_config_path: "config/brands.yml")

    part = client.get_part("HL-7025S", brand: "elgin")

    expect(part).to be_a(Autofacts::Part)
    expect(part.brand_slug).to eq("elgin")
    expect(part.part_number).to eq("HL-7025S")
    expect(part.countries).to contain_exactly("MX", "US")
    expect(part.applications).not_to be_empty
    expect(part.applications.map { |application| application[:country_alpha3] }.uniq).to contain_exactly("MEX", "USA")
    expect(database.db[:part_brands].where(slug: "elgin").count).to eq(1)
    expect(database.db[:part_applications].count).to be_positive
  end
end
