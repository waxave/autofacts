# frozen_string_literal: true

RSpec.describe Autofacts::Client do
  let(:database) { Autofacts::Database.new(":memory:") }
  let(:source) { Autofacts::Source::FixtureSource.new(FIXTURES_DIR) }
  let(:repository) { Autofacts::Repository.new(database.db) }
  let(:client) { described_class.new(database: database, source: source) }

  describe "seeded data" do
    it "returns the brands seeded in the local catalog" do
      repository.store_brand_index(Autofacts::Parsers.parse_brand_index(read_fixture("part/index.html")))

      brands = client.brands

      expect(brands).to all(be_a(Autofacts::PartBrand))
      expect(brands.length).to eq(504)
    end

    it "returns categories and subcategories" do
      repository.store_category(slug: "engine", name: "Engine")
      repository.store_subcategory(category_slug: "engine", slug: "oil-filter", name: "Oil Filter")

      expect(client.categories.map(&:slug)).to eq(["engine"])
      expect(client.subcategories.map(&:slug)).to eq(["oil-filter"])
      expect(client.subcategories(category_slug: "engine").map(&:slug)).to eq(["oil-filter"])
    end

    it "returns countries" do
      Autofacts::Seeder.new(repository, brands_path: nil).seed_countries

      expect(client.countries.length).to eq(249)
    end
  end

  describe "full-text taxonomy and brand search" do
    before do
      repository.upsert_brand(Autofacts::PartBrand.new(slug: "denso", name: "DENSO"))
      Autofacts::Seeder.new(repository, brands_path: nil).seed_categories
    end

    it "searches brands through the client" do
      matches = client.search_brands("denso")

      expect(matches).to all(be_a(Autofacts::PartBrand))
      expect(matches.map(&:slug)).to eq(["denso"])
    end

    it "searches categories and subcategories with locale support" do
      categories = client.search_categories("motor", locale: "es")
      subcategories = client.search_subcategories("piston")

      expect(categories.map(&:slug)).to include("engine")
      expect(categories.find { |category| category.slug == "engine" }.name).to eq("Motor")
      expect(subcategories).to all(be_a(Autofacts::Subcategory))
      expect(subcategories.map(&:name)).to include("Piston Ring")
    end

    it "returns no matches for an unknown search term" do
      expect(client.search_brands("no-such-brand")).to eq([])
      expect(client.search_categories("no-such-category")).to eq([])
      expect(client.search_subcategories("no-such-subcategory")).to eq([])
    end
  end

  describe "#find" do
    it "searches the catalog by part number and persists the results" do
      results = client.find("2C45")

      expect(results).to be_a(Autofacts::SearchResults)
      expect(results.parts).not_to be_empty
      expect(repository.search_results.length).to be_positive
    end

    it "normalizes the part number before the request" do
      results = client.find("2C45+STD")

      expect(results.query).to eq("2C45")
    end

    it "returns selected fields as symbol-keyed hashes" do
      parts = client.find("2C45", fields: %i[part_number brand description])

      expect(parts).to all(be_a(Hash))
      expect(parts.map { |part| part[:part_number] }).to include("2c4504")
      expect(parts.first.keys).to contain_exactly(:part_number, :brand, :description)
    end
  end

  describe "#part" do
    before do
      repository.upsert_brand(Autofacts::PartBrand.new(slug: "hastings-manufacturing", name: "Hastings Manufacturing"))
    end

    it "fetches, persists and returns a complete part by part number + brand" do
      part = client.part("2c4504", brand: "hastings-manufacturing")

      expect(part).to be_a(Autofacts::Part)
      expect(part.status).to eq("complete")
      expect(part.applications.length).to eq(80)
    end

    it "accepts a URL and lets the scraper build the request path" do
      part = client.part(url: "/part/hastings-manufacturing/2c4504/")

      expect(part.part_number).to eq("2c4504")
      expect(part.brand_slug).to eq("hastings-manufacturing")
    end

    it "does not re-fetch a part that is already complete" do
      source = instance_double(Autofacts::Source::FixtureSource)
      allow(source).to receive(:get).and_return(read_fixture("part/hastings-manufacturing/2c4504/index.html"))
      client = described_class.new(database: database, source: source)

      client.part("2c4504", brand: "hastings-manufacturing")
      client.part("2c4504", brand: "hastings-manufacturing")

      expect(source).to have_received(:get).once
    end

    it "resolves a missing brand from the local catalog" do
      client.part("2c4504", brand: "hastings-manufacturing")

      part = client.part("2c4504")

      expect(part.brand_slug).to eq("hastings-manufacturing")
    end

    it "normalizes the part number before lookup" do
      part = client.part("HL-7025S+STD", brand: "ELGIN")

      expect(part.part_number).to eq("HL-7025S")
    end

    it "raises for an unknown brand without making a request" do
      source = instance_double(Autofacts::Source::FixtureSource)
      allow(source).to receive(:get)
      client = described_class.new(database: database, source: source)

      expect { client.part("2c4504", brand: "no-such-brand") }
        .to raise_error(Autofacts::Error, /Unknown brand/)
      expect(source).not_to have_received(:get)
    end

    it "resolves a partial brand name through full-text search" do
      part = client.part("2c4504", brand: "HASTING")

      expect(part.brand_slug).to eq("hastings-manufacturing")
    end

    it "resolves an exact brand alias through full-text search" do
      repository.upsert_brand(Autofacts::PartBrand.new(
        slug: "hastings-manufacturing",
        name: "Hastings Manufacturing",
        aliases: ["HASTING"]
      ))

      part = client.part("2c4504", brand: "hasting")

      expect(part.brand_slug).to eq("hastings-manufacturing")
    end

    it "raises for an ambiguous partial brand without making a request" do
      repository.upsert_brand(Autofacts::PartBrand.new(slug: "hastings-auto", name: "Hastings Auto"))
      source = instance_double(Autofacts::Source::FixtureSource)
      allow(source).to receive(:get)
      client = described_class.new(database: database, source: source)

      expect { client.part("2c4504", brand: "HASTING") }
        .to raise_error(Autofacts::Error, /Ambiguous brand.*Hastings Auto.*Hastings Manufacturing/)
      expect(source).not_to have_received(:get)
    end

    it "returns selected fields as a symbol-keyed hash and normalizes string fields" do
      part = client.part(
        "2c4504",
        brand: "hastings-manufacturing",
        fields: %w[part_number brand category unknown_field]
      )

      expect(part).to be_a(Hash)
      expect(part.keys).to contain_exactly(:part_number, :brand, :category)
      expect(part[:part_number]).to eq("2c4504")
      expect(part[:category]).to eq({ name: "Engine", translations: {} })
    end
  end

  describe "#vehicle" do
    before { Autofacts::Seeder.new(repository, brands_path: nil).seed_categories }

    it "resolves the category through the taxonomy full-text search" do
      listing = client.vehicle(make: "nissan", year: 2007, model: "altima", category: "engine")

      expect(listing).to be_a(Autofacts::VehicleCategory)
      expect(listing.count).to eq(768)
    end

    it "resolves a category alias" do
      listing = client.vehicle(make: "nissan", year: 2007, model: "altima", category: "motor")

      expect(listing.count).to eq(768)
    end

    it "raises for an unknown category without making a request" do
      source = instance_double(Autofacts::Source::FixtureSource)
      allow(source).to receive(:get)
      client = described_class.new(database: database, source: source)

      expect { client.vehicle(make: "nissan", year: 2007, model: "altima", category: "nope") }
        .to raise_error(Autofacts::Error, /Unknown category/)
      expect(source).not_to have_received(:get)
    end

    it "raises for an ambiguous category" do
      expect { client.vehicle(make: "nissan", year: 2007, model: "altima", category: "electrical") }
        .to raise_error(Autofacts::Error, /Ambiguous category/)
    end

    it "returns selected vehicle-part fields as symbol-keyed hashes" do
      parts = client.vehicle(
        make: "nissan", year: 2007, model: "altima", category: "engine",
        fields: %i[part_number brand subcategory]
      )

      expect(parts).to all(be_a(Hash))
      expect(parts.length).to eq(768)
      expect(parts.first.keys).to contain_exactly(:part_number, :brand, :subcategory)
    end
  end
end
