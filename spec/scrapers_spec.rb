# frozen_string_literal: true

RSpec.describe Autofacts::Scrapers do
  describe ".for" do
    it "resolves the built-in autofactsdb scraper" do
      expect(described_class.for("autofactsdb")).to eq(Autofacts::Scrapers::AutofactsDb)
    end

    it "falls back to the selector scraper for unknown sources" do
      expect(described_class.for("acme")).to eq(Autofacts::Scrapers::SelectorScraper)
    end
  end

  describe Autofacts::Scrapers::AutofactsDb do
    subject(:scraper) { described_class.new(source: Autofacts::Source::FixtureSource.new(FIXTURES_DIR)) }

    it "scrapes the brand index from the source" do
      index = scraper.scrape_brand_index

      expect(index).to be_a(Autofacts::BrandIndex)
      expect(index.brands.length).to eq(504)
    end

    it "tags scraped brands with the autofactsdb source" do
      index = scraper.scrape_brand_index

      expect(index.brands.map(&:source).uniq).to eq(["autofactsdb"])
    end

    it "searches the catalog by part number" do
      results = scraper.search("2C45")

      expect(results).to be_a(Autofacts::SearchResults)
      expect(results.count).to eq(20)
      expect(results.parts.first.brand).to eq("Hastings Manufacturing")
    end
  end

  describe Autofacts::Scrapers::SelectorScraper do
    it "exposes the configured selectors and fixtures directory" do
      scraper = described_class.new(
        source: Autofacts::Source::FixtureSource.new(FIXTURES_DIR),
        config: { "fixtures_dir" => "fixtures/acme", "selectors" => { "part" => ".part" } }
      )

      expect(scraper.fixtures_dir).to eq("fixtures/acme")
      expect(scraper.selectors).to eq("part" => ".part")
    end
  end
end
