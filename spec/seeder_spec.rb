# frozen_string_literal: true

RSpec.describe Autofacts::Seeder do
  let(:database) { Autofacts::Database.new(":memory:") }
  let(:repository) { Autofacts::Repository.new(database.db) }
  let(:brands_path) { File.join(CONFIG_FIXTURES_DIR, "brands.yml") }
  let(:categories_path) { File.expand_path("fixtures/data/categories.yml", __dir__) }

  subject(:seeder) { described_class.new(repository, brands_path: brands_path, categories_path: categories_path) }

  describe "#seed_countries" do
    it "loads the built-in ISO country data" do
      seeder.seed_countries

      expect(repository.countries.length).to eq(249)
    end
  end

  describe "#seed_brands" do
    it "upserts the brands declared in the YAML file" do
      seeder.seed_brands

      slugs = repository.part_brands.map(&:slug)
      expect(slugs).to contain_exactly("gm-genuine", "acme")
    end

    it "persists standalone brand source and url" do
      seeder.seed_brands

      acme = repository.part_brands.find { |b| b.slug == "acme" }
      expect(acme.name).to eq("ACME Parts")
      expect(acme.source).to eq("acme")
      expect(acme.source_url).to eq("https://acmeparts.example.com")
    end

    it "defaults brands without a source to autofactsdb" do
      seeder.seed_brands

      gm = repository.part_brands.find { |b| b.slug == "gm-genuine" }
      expect(gm.source).to eq("autofactsdb")
    end
  end

  describe "#seed_categories" do
    it "upserts categories, subcategories and their translations" do
      counts = seeder.seed_categories

      expect(counts).to eq(categories: 2, subcategories: 1, translations: 3)
      expect(repository.categories(locale: "es").map(&:name)).to contain_exactly("Motor", "Literatura")
      expect(repository.subcategories(locale: "es").map(&:name)).to contain_exactly("Filtro de aceite")
      expect(repository.subcategories.first.category).to eq("engine")
    end

    it "indexes names, translations and aliases for full-text search" do
      seeder.seed_categories

      expect(repository.search_categories("motor").map(&:slug)).to eq(["engine"])
      expect(repository.search_categories("propulsor").map(&:slug)).to eq(["engine"])
      expect(repository.search_subcategories("filtro").map(&:slug)).to eq(["oil-filter"])
      expect(repository.search_subcategories("lubricant").map(&:slug)).to eq(["oil-filter"])
    end

    it "is idempotent" do
      2.times { seeder.seed_categories }

      expect(repository.categories.length).to eq(2)
      expect(repository.subcategories.length).to eq(1)
      expect(database.db[:translations].count).to eq(3)
      expect(database.db[:categories_fts].count).to eq(2)
      expect(database.db[:subcategories_fts].count).to eq(1)
    end
  end

  describe "#call" do
    it "seeds countries, brands and taxonomy" do
      seeder.call

      expect(repository.countries.length).to eq(249)
      expect(repository.part_brands.length).to eq(2)
      expect(repository.categories.length).to eq(2)
      expect(repository.subcategories.length).to eq(1)
    end
  end
end
