# frozen_string_literal: true

RSpec.describe Autofacts::Scrapers::Fraco do
  let(:source) { Autofacts::Source::FixtureSource.new(FIXTURES_DIR) }
  let(:config) do
    {
      "slug" => "fraco",
      "name" => "FRACO",
      "fixtures_dir" => "fraco",
      "source_url" => "https://simepa.mx/Simepa.mx/admin/buscador"
    }
  end

  subject(:scraper) { described_class.new(source: source, config: config) }

  describe "#parse_attributes" do
    let(:html) { read_fixture("fraco/FSX-5840301/attributes.html") }

    it "parses component attributes as class/attribute/unit/value" do
      attributes = scraper.parse_attributes(html)

      expect(attributes.length).to eq(12)
      expect(attributes).to include({ class: "HGX-5840301-SB", attribute: "Junta de Cabeza", unit: nil, value: "1" })
      expect(attributes).to include({ class: "S-5228-V", attribute: "Sello de Válvula - Admisión", unit: nil, value: "8" })
    end
  end

  describe "#parse_applications" do
    let(:html) { read_fixture("fraco/FSX-5840301/applications.html") }

    it "parses brand, model, years, engine and extra attributes" do
      first = scraper.parse_applications(html).first

      expect(first[:brand]).to eq("Nissan")
      expect(first[:model]).to eq("240SX")
      expect(first[:years]).to eq([1989, 1990])
      expect(first[:engine]).to eq("2.4 L L4")
      expect(first[:attributes]).to include({ class: nil, attribute: "SOHC, KA24E", unit: nil, value: nil })
      expect(first[:attributes]).to include({ class: nil, attribute: "12 Válvulas", unit: nil, value: nil })
    end

    it "expands multi-year ranges" do
      axxess = scraper.parse_applications(html).find { |a| a[:model] == "Axxess" }
      expect(axxess[:years]).to eq([1990, 1991, 1992, 1993, 1994, 1995])
    end
  end

  describe "#scrape" do
    it "builds a complete part with attributes and one application per year" do
      part = scraper.scrape("FSX-5840301")

      expect(part.brand_slug).to eq("fraco")
      expect(part.brand).to eq("FRACO")
      expect(part.part_number).to eq("FSX-5840301")
      expect(part.status).to eq("complete")
      expect(part.countries).to contain_exactly("MX", "US")
      expect(part.attributes).to include({ class: "HGX-5840301-SB", attribute: "Junta de Cabeza", unit: nil, value: "1" })
      expect(part.attributes).to include({ class: nil, attribute: "SOHC, KA24E", unit: nil, value: nil })
      expect(part.applications.length).to eq(22)
      expect(part.applications.map(&:year)).to include(1989, 1990)
      expect(part.applications.first.engine).to eq("2.4 L L4")
    end
  end
end

RSpec.describe Autofacts::BrandConfig do
  let(:config) { described_class.load("config/brands.yml") }

  it "resolves FRACO's source" do
    expect(config.source_for("fraco")).to eq("fraco")
  end

  it "defaults unknown brands to autofactsdb" do
    expect(config.source_for("unknown")).to eq("autofactsdb")
  end

  it "keeps bundled part-number rules when loading an application override" do
    hastings_rules = config.config_for("hastings-manufacturing").fetch("part_number_rules")
    cloyes_rules = config.config_for("cloyes").fetch("part_number_rules")

    expect(Autofacts::PartNumber.clean("HL-7025S+STD", rules: hastings_rules)).to eq("HL-7025S")
    expect(Autofacts::PartNumber.clean("9-1234", rules: cloyes_rules)).to eq("91234")
  end

  it "resolves the HASTING alias to the canonical catalog brand" do
    expect(config.find("HASTING")).to include(
      "slug" => "hastings-manufacturing",
      "name" => "Hastings Manufacturing"
    )
  end
end

RSpec.describe "multi-provider part lookup" do
  let(:database) { Autofacts::Database.new(":memory:") }

  it "dispatches a standalone brand to its scraper and persists" do
    source = Autofacts::Source::FixtureSource.new(FIXTURES_DIR)
    client = Autofacts::Client.new(database: database, source: source, brand_config_path: "config/brands.yml")

    part = client.part("FSX-5840301", brand: "fraco")

    expect(part.brand).to eq("FRACO")
    expect(part.countries).to contain_exactly("MX", "US")
    expect(part.applications.length).to eq(44) # 22 vehicles x 2 markets
    expect(part.applications.first).to include(:country_code, :country_alpha3)
    expect(database.db[:parts].where(part_number: "FSX-5840301").count).to eq(1)
    expect(database.db[:vehicle_brands].select_map(:name)).to include("Nissan")
  end
end
