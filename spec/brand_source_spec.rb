# frozen_string_literal: true

RSpec.describe "brand source persistence" do
  let(:database) { Autofacts::Database.new(":memory:") }
  let(:repository) { Autofacts::Repository.new(database.db) }

  it "defaults source to autofactsdb" do
    brand = Autofacts::PartBrand.new(slug: "denso", name: "DENSO")

    expect(brand.source).to eq("autofactsdb")
    expect(brand.source_url).to be_nil
  end

  it "stores source and source_url for a standalone brand" do
    brand = Autofacts::PartBrand.new(
      slug: "acme",
      name: "ACME Parts",
      url: "https://acmeparts.example.com/",
      source: "acme",
      source_url: "https://acmeparts.example.com"
    )

    repository.store_brand_index(Autofacts::BrandIndex.new(brands: [brand]))

    stored = repository.part_brands.first
    expect(stored.slug).to eq("acme")
    expect(stored.source).to eq("acme")
    expect(stored.source_url).to eq("https://acmeparts.example.com")
  end

  it "keeps the built-in brand source as autofactsdb when parsed from the index" do
    source = Autofacts::Source::FixtureSource.new(FIXTURES_DIR)
    index = Autofacts::Scrapers::AutofactsDb.new(source: source).scrape_brand_index

    repository.store_brand_index(index)

    expect(repository.part_brands.map(&:source).uniq).to eq(["autofactsdb"])
  end
end
