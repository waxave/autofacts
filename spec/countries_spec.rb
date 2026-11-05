# frozen_string_literal: true

RSpec.describe Autofacts::Country do
  it "exposes code, name and description" do
    country = described_class.new(code: "US", name: "United States", description: "United States of America")

    expect(country.code).to eq("US")
    expect(country.name).to eq("United States")
    expect(country.description).to eq("United States of America")
  end
end

RSpec.describe "country persistence" do
  let(:database) { Autofacts::Database.new(":memory:") }
  let(:repository) { Autofacts::Repository.new(database.db) }

  it "is empty before seeding" do
    expect(repository.countries).to be_empty
  end

  it "seeds the full ISO 3166 list (249 countries)" do
    Autofacts::Seeder.new(repository, brands_path: nil).seed_countries

    expect(repository.countries.length).to eq(249)
  end

  it "finds a country by its ISO code" do
    Autofacts::Seeder.new(repository, brands_path: nil).seed_countries

    united_states = repository.country("US")
    expect(united_states).to be_a(Autofacts::Country)
    expect(united_states.name).to eq("United States of America")
    expect(united_states.description).to eq("United States of America (the)")
  end

  it "is idempotent" do
    seeder = Autofacts::Seeder.new(repository, brands_path: nil)
    2.times { seeder.seed_countries }

    expect(repository.countries.length).to eq(249)
  end
end
