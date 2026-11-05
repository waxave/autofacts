# frozen_string_literal: true

RSpec.describe Autofacts::Source::FixtureSource do
  subject(:source) { described_class.new(FIXTURES_DIR) }

  it "reads a page whose path mirrors its URL" do
    expect(source.get("/part/")).to include("Auto Parts Brands")
  end

  it "reads by absolute URL too" do
    expect(source.get("https://autofactsdb.com/part/")).to include("Auto Parts Brands")
  end

  it "raises RequestError when the fixture is missing" do
    expect { source.get("/vehicles/toyota/") }
      .to raise_error(Autofacts::RequestError, /Fixture not found/)
  end

  describe "URL to path translation" do
    it "maps a trailing-slash path to index.html" do
      path = source.send(:file_path_for, "/part/")
      expect(path).to end_with("part/index.html")
    end

    it "maps the root to index.html" do
      path = source.send(:file_path_for, "/")
      expect(path).to end_with("index.html")
    end

    it "encodes a query string into the filename" do
      expect(source.get("/search/?q=2C45")).to include("Results for")
    end

    it "maps query parameters with = to - and & to _" do
      expect(source.send(:file_path_for, "/search/?q=2C45&page=2"))
        .to end_with("search/q-2C45_page-2.html")
    end
  end
end
