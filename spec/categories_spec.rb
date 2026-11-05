# frozen_string_literal: true

RSpec.describe "part taxonomy" do
  let(:database) { Autofacts::Database.new(":memory:") }
  let(:repository) { Autofacts::Repository.new(database.db) }

  before do
    engine = database.db[:categories].insert(slug: "engine", name: "Engine")
    database.db[:subcategories].insert(category_id: engine, slug: "balance-shaft-chain", name: "Balance Shaft Chain")
    brake = database.db[:categories].insert(slug: "brake", name: "Brake")
    database.db[:subcategories].insert(category_id: brake, slug: "brake-pads", name: "Brake Pads")
  end

  it "lists categories ordered by name" do
    expect(repository.categories.map(&:name)).to eq(["Brake", "Engine"])
    expect(repository.categories.map(&:slug)).to eq(["brake", "engine"])
  end

  it "lists subcategories with their parent category" do
    rows = repository.subcategories

    expect(rows.map(&:name)).to eq(["Brake Pads", "Balance Shaft Chain"])
    expect(rows.last.category).to eq("engine")
    expect(rows.last.category_name).to eq("Engine")
  end

  it "filters subcategories by category slug" do
    rows = repository.subcategories(category_slug: "engine")

    expect(rows.map(&:slug)).to eq(["balance-shaft-chain"])
  end

  it "localizes names when a locale is given" do
    category = database.db[:categories].where(slug: "engine").first
    repository.set_translation(translatable_type: "category", translatable_id: category[:id], field: "name", locale: "es", text: "Motor")

    expect(repository.categories(locale: "es").map(&:name)).to contain_exactly("Brake", "Motor")
  end

  describe "#store_category / #store_subcategory" do
    it "preserves explicit slugs and links the subcategory" do
      category_id = repository.store_category(slug: "body-lamp-assembly", name: "Body & Lamp Assembly")
      subcategory_id = repository.store_subcategory(
        category_slug: "body-lamp-assembly",
        slug: "touch-up-paint",
        name: "Touch-Up Paint"
      )

      expect(category_id).not_to be_nil
      expect(subcategory_id).not_to be_nil
      expect(repository.categories.map(&:slug)).to include("body-lamp-assembly")

      row = repository.subcategories.find { |subcategory| subcategory.slug == "touch-up-paint" }
      expect(row.category).to eq("body-lamp-assembly")
      expect(row.category_name).to eq("Body & Lamp Assembly")
    end

    it "updates rows by slug instead of duplicating them" do
      category_id = repository.store_category(slug: "engine", name: "Engine & Motor")

      expect(category_id).to eq(database.db[:categories].where(slug: "engine").get(:id))
      expect(database.db[:categories].where(slug: "engine").count).to eq(1)

      repository.store_subcategory(category_slug: "engine", slug: "balance-shaft-chain", name: "Balance Shaft Timing Chain")

      expect(database.db[:subcategories].where(slug: "balance-shaft-chain").count).to eq(1)
    end
  end

  describe "full-text search" do
    before do
      engine = database.db[:categories].where(slug: "engine").get(:id)
      brake = database.db[:categories].where(slug: "brake").get(:id)
      chain = database.db[:subcategories].where(slug: "balance-shaft-chain").get(:id)
      pads = database.db[:subcategories].where(slug: "brake-pads").get(:id)

      repository.clear_taxonomy_fts
      repository.index_category(engine, "engine", "engine motor propulsor")
      repository.index_category(brake, "brake", "brake frenos")
      repository.index_subcategory(chain, "balance-shaft-chain", "balance shaft chain cadena distribucion")
      repository.index_subcategory(pads, "brake-pads", "brake pads pastillas freno")
    end

    it "finds categories by name, translation or alias prefix" do
      expect(repository.search_categories("eng").map(&:slug)).to eq(["engine"])
      expect(repository.search_categories("motor").map(&:slug)).to eq(["engine"])
      expect(repository.search_categories("fren").map(&:slug)).to eq(["brake"])
    end

    it "finds subcategories and includes their parent category" do
      results = repository.search_subcategories("cad")

      expect(results.map(&:slug)).to eq(["balance-shaft-chain"])
      expect(results.first.category).to eq("engine")
      expect(results.first.category_name).to eq("Engine")
    end

    it "returns nothing for blank or operator-only terms" do
      expect(repository.search_categories("")).to eq([])
      expect(repository.search_categories('"*')).to eq([])
      expect(repository.search_subcategories("")).to eq([])
    end
  end
end
