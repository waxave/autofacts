# frozen_string_literal: true

RSpec.describe Autofacts::Client do
  let(:database) { Autofacts::Database.new(":memory:") }

  describe "#get_part_brands" do
    it "fetches, persists and returns the brand index" do
      source = Autofacts::Source::FixtureSource.new(FIXTURES_DIR)
      client = described_class.new(database: database, source: source)

      index = client.get_part_brands

      expect(index).to be_a(Autofacts::BrandIndex)
      expect(index.brands.length).to eq(504)
      expect(index.brands.first.url).to match(%r{\Ahttps://autofactsdb\.com/part/})
    end

    it "does not re-fetch when the data is already stored" do
      source = instance_double(Autofacts::Source::FixtureSource)
      allow(source).to receive(:get).with("/part/").and_return(read_fixture("part/index.html"))
      client = described_class.new(database: database, source: source)

      2.times { client.get_part_brands }

      expect(source).to have_received(:get).with("/part/").once
    end

    it "re-fetches when force: true" do
      source = instance_double(Autofacts::Source::FixtureSource)
      allow(source).to receive(:get).with("/part/").and_return(read_fixture("part/index.html"))
      client = described_class.new(database: database, source: source)

      client.get_part_brands
      client.get_part_brands(force: true)

      expect(source).to have_received(:get).with("/part/").twice
    end
  end

  describe "#get_part" do
    it "fetches, persists and returns a complete part" do
      source = Autofacts::Source::FixtureSource.new(FIXTURES_DIR)
      client = described_class.new(database: database, source: source)

      part = client.get_part("/part/hastings-manufacturing/2c4504/")

      expect(part).to be_a(Autofacts::Part)
      expect(part.status).to eq("complete")
      expect(part.applications.length).to eq(80)
      expect(part.applications.first).to include(:country_code, :country_alpha3)
    end

    it "does not re-fetch when the part is already complete" do
      source = instance_double(Autofacts::Source::FixtureSource)
      allow(source).to receive(:get).and_return(read_fixture("part/hastings-manufacturing/2c4504/index.html"))
      client = described_class.new(database: database, source: source)

      client.get_part("/part/hastings-manufacturing/2c4504/")
      client.get_part("/part/hastings-manufacturing/2c4504/")

      expect(source).to have_received(:get).once
    end
  end

  describe "#get_part by part number" do
    it "returns a complete part from local storage without fetching" do
      source = instance_double(Autofacts::Source::FixtureSource)
      allow(source).to receive(:get).and_return(read_fixture("part/hastings-manufacturing/2c4504/index.html"))
      client = described_class.new(database: database, source: source)

      client.get_part("2c4504", brand: "hastings-manufacturing")
      client.get_part("2c4504", brand: "hastings-manufacturing")

      expect(source).to have_received(:get).once
    end

    it "resolves the brand from saved search results when only the part number is given" do
      source = Autofacts::Source::FixtureSource.new(FIXTURES_DIR)
      client = described_class.new(database: database, source: source)

      client.search_parts("2C45")
      part = client.get_part("2C4504")

      expect(part).to be_a(Autofacts::Part)
      expect(part.status).to eq("complete")
      expect(part.brand_slug).to eq("hastings-manufacturing")
    end

    it "raises when the brand cannot be determined" do
      source = instance_double(Autofacts::Source::FixtureSource)
      client = described_class.new(database: database, source: source)

      expect { client.get_part("UNKNOWN") }
        .to raise_error(Autofacts::Error, /Could not determine the brand/)
    end
  end

  describe "field selection" do
    let(:client) { described_class.new(database: database, source: Autofacts::Source::FixtureSource.new(FIXTURES_DIR)) }

    it "returns brand fields as symbol-keyed hashes" do
      brands = client.get_part_brands(fields: %i[slug name])

      expect(brands).to all(be_a(Hash))
      expect(brands.length).to eq(504)
      expect(brands.first.keys).to contain_exactly(:slug, :name)
    end

    it "returns search-result fields as symbol-keyed hashes" do
      parts = client.search_parts("2C45", fields: %i[part_number brand description])

      expect(parts).to all(be_a(Hash))
      expect(parts.map { |part| part[:part_number] }).to include("2c4504")
      expect(parts.first.keys).to contain_exactly(:part_number, :brand, :description)
    end

    it "returns a single part as a symbol-keyed hash and normalizes string fields" do
      part = client.get_part(
        "/part/hastings-manufacturing/2c4504/",
        fields: %w[part_number brand category unknown_field]
      )

      expect(part).to be_a(Hash)
      expect(part.keys).to contain_exactly(:part_number, :brand, :category)
      expect(part[:part_number]).to eq("2c4504")
      expect(part[:category]).to eq({ name: "Engine", translations: {} })
    end

    it "still returns the full wrapper when fields is omitted" do
      expect(client.search_parts("2C45")).to be_a(Autofacts::SearchResults)
    end
  end

  describe "part-number cleaning" do
    let(:client) do
      described_class.new(
        database: database,
        source: Autofacts::Source::FixtureSource.new(FIXTURES_DIR),
        brand_config_path: "config/brands.yml"
      )
    end

    it "cleans +STD from get_part before scraping" do
      part = client.get_part("HL-7025S+STD", brand: "elgin")

      expect(part.part_number).to eq("HL-7025S")
      expect(part.brand_slug).to eq("elgin")
    end

    it "cleans +STD from search queries" do
      results = client.search_parts("2C45+STD")

      expect(results.query).to eq("2C45")
      expect(results.parts).not_to be_empty
    end
  end
end
