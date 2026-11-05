# frozen_string_literal: true

require "pathname"

RSpec.describe "Autofacts.install" do
  let(:dir) { Dir.mktmpdir("autofacts-install") }
  let(:path) { File.join(dir, "autofacts.sqlite3") }
  let(:brands_path) { File.join(CONFIG_FIXTURES_DIR, "brands.yml") }
  let(:categories_path) { File.expand_path("fixtures/data/categories.yml", __dir__) }

  it "creates, migrates and seeds the database" do
    summary = Autofacts.install(path: path, brands_path: brands_path, categories_path: categories_path)

    expect(File).to exist(path)
    expect(summary).to include(path: path, countries: 249, brands: 2)
    expect(summary[:categories]).to eq(categories: 2, subcategories: 1, translations: 3)

    database = Autofacts::Database.new(path)
    expect(database.db[:categories].count).to eq(2)
    expect(database.db[:part_brands].count).to eq(2)
    database.close
  end

  it "only runs migrations when seed is false" do
    summary = Autofacts.install(path: path, seed: false)

    expect(summary).to eq(path: path)
    database = Autofacts::Database.new(path)
    expect(database.db[:countries].count).to eq(0)
    database.close
  end

  it "ships a Rails initializer template" do
    template = File.expand_path("../lib/autofacts/generators/autofacts/templates/autofacts.rb", __dir__)

    expect(File.read(template)).to include("Autofacts.database_path")
  end

  describe "database_path" do
    after { Autofacts.database_path = "autofacts.sqlite3" }

    it "stores a Pathname as a string" do
      Autofacts.database_path = Pathname.new("/tmp/custom.sqlite3")

      expect(Autofacts.database_path).to eq("/tmp/custom.sqlite3")
    end
  end
end
