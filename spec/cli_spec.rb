# frozen_string_literal: true

require "autofacts/cli"

RSpec.describe Autofacts::CLI do
  let(:database_path) { File.join(Dir.mktmpdir("autofacts-cli"), "cli.sqlite3") }
  let(:brands_path) { File.join(CONFIG_FIXTURES_DIR, "brands.yml") }

  def run(*args)
    capture_io { described_class.start(args, debug: false) }
  end

  def seed!
    run("seed", "--database", database_path, "--brands", brands_path)
  end

  describe "seed" do
    it "seeds countries, configured brands, catalog brands and taxonomy" do
      output = seed!

      expect(output).to include("Seeded 249 countries")
      expect(output).to include("Seeded 2 configured brands")
      expect(output).to include("Seeded 504 catalog brands")
      expect(output).to include("Seeded 22 categories and 453 subcategories")
    end

    it "loads bundled providers outside the checkout" do
      Dir.mktmpdir("autofacts-cli-app") do |app_dir|
        output = Dir.chdir(app_dir) do
          run("seed", "--database", database_path)
        end

        expect(output).to include("Seeded 2 configured brands")
      end
    end
  end

  describe "install" do
    it "creates, migrates and seeds the database" do
      output = run("install", "--database", database_path, "--brands", brands_path)

      expect(output).to include("Database ready at #{database_path}")
      expect(output).to include("Seeded 249 countries")
      expect(output).to include("Seeded 2 configured brands")
      expect(output).to include("Seeded 504 catalog brands")
      expect(output).to include("Seeded 22 categories and 453 subcategories")
    end

    it "skips seeding with --no-seed" do
      output = run("install", "--database", database_path, "--no-seed")

      expect(output).to include("Database ready at #{database_path}")
      expect(output).not_to include("Seeded")
    end
  end

  describe "brands" do
    it "lists seeded brands with their source" do
      seed!
      output = run("brands", "--database", database_path)

      expect(output).to include("ACME Parts")
      expect(output).to include("acme")
    end
  end

  describe "countries" do
    it "lists seeded countries" do
      seed!
      output = run("countries", "--database", database_path)

      expect(output).to include("United States of America")
    end
  end

  describe "categories" do
    def seed_taxonomy!
      database = Autofacts::Database.new(database_path)
      engine = database.db[:categories].insert(slug: "engine", name: "Engine")
      database.db[:subcategories].insert(category_id: engine, slug: "balance-shaft-chain", name: "Balance Shaft Chain")
      database.close
    end

    it "lists part categories" do
      seed_taxonomy!
      output = run("categories", "--database", database_path)

      expect(output).to include("engine")
      expect(output).to include("Engine")
    end

    it "lists subcategories, optionally filtered by category" do
      seed_taxonomy!
      output = run("subcategories", "--database", database_path, "--category", "engine")

      expect(output).to include("CATEGORY")
      expect(output).to include("balance-shaft-chain")
      expect(output).to include("Balance Shaft Chain")
    end
  end

  describe "search" do
    it "finds brands by name" do
      seed!
      output = run("search", "acme", "--database", database_path)

      expect(output).to include("brand:")
      expect(output).to include("ACME Parts")
    end

    it "finds categories and subcategories by name, translation or alias" do
      seed!

      translated = run("search", "motor", "--database", database_path, "--locale", "es")
      expect(translated).to include("category:")
      expect(translated).to include("Motor")

      aliased = run("search", "balatas", "--database", database_path)
      expect(aliased).to include("category:")
      expect(aliased).to include("brake-wheel-hub")

      subcategory = run("search", "balance", "--database", database_path)
      expect(subcategory).to include("subcategory:")
      expect(subcategory).to include("Balance Shaft Chain")
    end

    it "searches categories directly with locale and JSON output" do
      seed!
      output = run("category", "motor", "--database", database_path, "--locale", "es", "--json")
      data = JSON.parse(output)

      expect(data).to include(hash_including("slug" => "engine", "name" => "Motor"))
      expect(data.first["translations"]).to include("es" => "Motor")
    end

    it "searches subcategories directly with parent category details" do
      seed!
      output = run("subcategory", "piston", "--database", database_path, "--json")
      data = JSON.parse(output)

      result = data.find { |row| row["slug"] == "piston-ring" }
      expect(result).to include(
        "category" => "engine",
        "category_name" => "Engine",
        "category_translations" => { "es" => "Motor" }
      )
      expect(result["translations"]).to include("es" => "Anillo del pistón")
    end

    it "reports when nothing matches" do
      seed!
      output = run("search", "zzzz", "--database", database_path)

      expect(output).to include("No matches")
    end
  end

  describe "find" do
    def run_find(*args)
      run("find", *args, "--database", database_path, "--fixtures", FIXTURES_DIR)
    end

    it "prints an aligned table by default" do
      output = run_find("2C45")

      expect(output).to include("PART #")
      expect(output).to include("SUB-CATEGORY")
      expect(output).to include("Hastings Manufacturing")
      expect(output).to include("2c4504")
      expect(output).to include("20 parts")
    end

    it "shows separate category and sub-category lines with --verbose" do
      output = run_find("2C45", "--verbose")

      expect(output).to match(/Category:\s+Engine/)
      expect(output).to match(/Sub-category:\s+Piston Ring/)
      expect(output).to include("Applications:")
      expect(output).to include("- 2017 Hyundai Accent · 1.6L L4")
      expect(output).to include("https://autofactsdb.com/part/hastings-manufacturing/2c4504/")
    end

    it "outputs structured JSON with --json" do
      output = run_find("2C45", "--json")
      data = JSON.parse(output)

      expect(data["query"]).to eq("2C45")
      expect(data["result_count"]).to eq(20)
      expect(data["parts"].length).to eq(20)
      expect(data["parts"].first).to include(
        "brand_slug" => "hastings-manufacturing",
        "part_number" => "2c4504",
        "brand" => "Hastings Manufacturing",
        "description" => "Hastings Manufacturing 2C4504 — Piston Ring",
        "category" => "Engine",
        "subcategory" => "Piston Ring"
      )
      expect(data["next_page_url"]).to include("page=2")
      expect(data["parts"].first["applications"]).to be_an(Array)
      expect(data["parts"].first["applications"].first).to include(
        "year" => 2017, "vehicle" => "Hyundai Accent", "engine" => "1.6L L4"
      )
      expect(data["parts"].first["applications_count"]).to eq(33)
      expect(data["parts"].first["attributes"]).to be_an(Array)
    end

    it "reports when nothing matches" do
      output = run_find("EMPTY")

      expect(output).to include("No parts found")
    end

    it "returns an empty parts array as JSON when nothing matches" do
      output = run_find("EMPTY", "--json")
      data = JSON.parse(output)

      expect(data["parts"]).to eq([])
    end
  end

  describe "part" do
    before do
      database = Autofacts::Database.new(database_path)
      Autofacts::Repository.new(database.db).upsert_brand(
        Autofacts::PartBrand.new(slug: "hastings-manufacturing", name: "Hastings Manufacturing")
      )
      database.close
    end

    def run_part(*args)
      run("part", *args, "--database", database_path, "--fixtures", FIXTURES_DIR)
    end

    it "scrapes and saves a part by part number + brand" do
      output = run_part("2c4504", "--brand", "hastings-manufacturing")

      expect(output).to include("Hastings Manufacturing")
      expect(output).to include("Piston Ring")
      expect(output).to include("Applications: 80")
      expect(output).to include("Status:       complete")
    end

    it "accepts a part URL" do
      output = run_part("--url", "/part/hastings-manufacturing/2c4504/")

      expect(output).to include("Hastings Manufacturing")
      expect(output).to include("Status:       complete")
    end

    it "outputs the part as JSON" do
      output = run_part("2c4504", "--brand", "hastings-manufacturing", "--json")
      data = JSON.parse(output)

      expect(data["part_number"]).to eq("2c4504")
      expect(data).not_to have_key("status")
      expect(data).not_to have_key("makes")
      expect(data["description"]).to start_with("Hastings Manufacturing part number 2C4504")
      expect(data["category"]).to eq({ "name" => "Engine", "translations" => {} })
      expect(data["applications"].length).to eq(80)
      expect(data["applications"].first).to include("country_code", "country_alpha3")
      expect(data["applications"].map { |application| application["country_alpha3"] }.uniq).to contain_exactly("CAN", "USA")
      expect(data["attributes_count"]).to eq(7)
      expect(data["years_range"]).to eq([2010, 2022])
      expect(data["countries"]).to contain_exactly("US", "CA")
    end

    it "looks up a part by part number after a search" do
      run("find", "2C45", "--database", database_path, "--fixtures", FIXTURES_DIR)
      output = run_part("2c4504")

      expect(output).to include("Hastings Manufacturing")
      expect(output).to include("Status:       complete")
    end

    it "persists the part into the target database" do
      run_part("2c4504", "--brand", "hastings-manufacturing")

      database = Autofacts::Database.new(database_path)
      repository = Autofacts::Repository.new(database.db)
      stored = repository.part("hastings-manufacturing", "2c4504")

      expect(stored).not_to be_nil
      expect(stored.status).to eq("complete")
      expect(stored.applications.length).to eq(80)
      expect(database.db[:categories].count).to eq(1)
      expect(database.db[:part_attributes].count).to eq(7)
      database.close
    end
  end

  describe "vehicle" do
    before do
      database = Autofacts::Database.new(database_path)
      Autofacts::Seeder.new(Autofacts::Repository.new(database.db), brands_path: nil).seed_categories
      database.close
    end

    def run_vehicle(*args)
      run("vehicle", "nissan", "2007", "altima", "engine", *args,
          "--database", database_path, "--fixtures", FIXTURES_DIR)
    end

    it "scrapes and saves a vehicle category" do
      output = run_vehicle

      expect(output).to include("2007 Nissan Altima Engine Parts")
      expect(output).to include("Parsed 768 parts")
    end

    it "resolves the category by alias" do
      output = run("vehicle", "nissan", "2007", "altima", "motor",
                   "--database", database_path, "--fixtures", FIXTURES_DIR)

      expect(output).to include("Parsed 768 parts")
    end

    it "outputs JSON" do
      output = run_vehicle("--json")
      data = JSON.parse(output)

      expect(data["parts"].length).to eq(768)
      expect(data["make_name"]).to eq("Nissan")
      expect(data["category_name"]).to eq("Engine")
    end
  end

  describe "part with a standalone brand" do
    it "scrapes FRACO from fixtures" do
      output = run("part", "FSX-5840301", "--brand", "fraco",
                   "--database", database_path, "--fixtures", FIXTURES_DIR)

      expect(output).to include("FRACO")
      expect(output).to include("FSX-5840301")
      expect(output).to include("Junta de Cabeza")
    end
  end
end
