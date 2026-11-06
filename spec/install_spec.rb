# frozen_string_literal: true

require "pathname"
require "fileutils"

RSpec.describe "Autofacts.install" do
  let(:dir) { Dir.mktmpdir("autofacts-install") }
  let(:path) { File.join(dir, "autofacts.sqlite3") }
  let(:brands_path) { File.join(CONFIG_FIXTURES_DIR, "brands.yml") }
  let(:categories_path) { File.expand_path("fixtures/data/categories.yml", __dir__) }

  it "creates, migrates and seeds the database" do
    summary = Autofacts.install(path: path, brands_path: brands_path, categories_path: categories_path)

    expect(File).to exist(path)
    expect(summary).to include(path: path, countries: 249, brands: 2, catalog_brands: 504)
    expect(summary[:categories]).to eq(categories: 2, subcategories: 1, translations: 3)

    database = Autofacts::Database.new(path)
    expect(database.db[:categories].count).to eq(2)
    # 504 catalog brands plus the configured "acme" (gm-genuine overlaps the catalog).
    expect(database.db[:part_brands].count).to eq(505)
    database.close
  end

  it "seeds the catalog brands from the bundled YAML" do
    Autofacts.install(path: path, brands_path: brands_path, categories_path: categories_path)

    database = Autofacts::Database.new(path)
    expect(database.db[:part_brands].where(slug: "3d").count).to eq(1)
    expect(database.db[:part_brands].where(popular: true).count).to eq(12)
    database.close
  end

  it "seeds standalone providers when installed outside the checkout" do
    Dir.mktmpdir("autofacts-app") do |app_dir|
      Dir.chdir(app_dir) do
        summary = Autofacts.install(path: path, categories_path: categories_path)

        expect(summary[:brands]).to eq(2)
        database = Autofacts::Database.new(path)
        expect(database.db[:part_brands].where(slug: %w[elgin fraco]).count).to eq(2)
        database.close
      end
    end
  end

  it "only runs migrations when seed is false" do
    summary = Autofacts.install(path: path, seed: false)

    expect(summary).to eq(path: path)
    database = Autofacts::Database.new(path)
    expect(database.db[:countries].count).to eq(0)
    expect(database.db[:part_brands].count).to eq(0)
    database.close
  end

  it "ships a Rails initializer template" do
    template = File.expand_path("../lib/autofacts/generators/autofacts/templates/autofacts.rb", __dir__)
    generator = File.expand_path("../lib/autofacts/generators/autofacts/install_generator.rb", __dir__)

    expect(File.read(template)).to include("Autofacts.database_path")
    expect(File.read(generator)).to include("config/autofacts.yml")
  end

  describe "database_path" do
    after do
      Autofacts.database_path = "autofacts.sqlite3"
      ENV.delete("AUTOFACTS_DATABASE_PATH")
    end

    it "stores a Pathname as a string" do
      Autofacts.database_path = Pathname.new("/tmp/custom.sqlite3")

      expect(Autofacts.database_path).to eq("/tmp/custom.sqlite3")
    end

    it "uses the shared environment setting" do
      ENV["AUTOFACTS_DATABASE_PATH"] = "/tmp/shared.sqlite3"

      Autofacts.database_path = nil

      expect(Autofacts.database_path).to eq("/tmp/shared.sqlite3")
    end

    it "reads the Rails project setting when no explicit path is configured" do
      Dir.mktmpdir("autofacts-config") do |root|
        FileUtils.mkdir_p(File.join(root, "config"))
        File.write(File.join(root, "config", "autofacts.yml"), "database_path: db/shared.sqlite3\n")

        Dir.chdir(root) do
          ENV.delete("AUTOFACTS_DATABASE_PATH")
          Autofacts.database_path = nil

          expect(Autofacts.database_path).to eq("db/shared.sqlite3")
        end
      end
    end
  end
end
