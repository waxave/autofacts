# frozen_string_literal: true

RSpec.describe Autofacts::Parsers do
  describe ".parse_part_detail" do
    let(:html) { read_fixture("part/hastings-manufacturing/2c4504/index.html") }
    let(:part) { described_class.parse_part_detail(html, url: "/part/hastings-manufacturing/2c4504/") }

    it "parses the core fields from the URL and quick facts" do
      expect(part).to be_a(Autofacts::Part)
      expect(part.brand_slug).to eq("hastings-manufacturing")
      expect(part.part_number).to eq("2c4504")
      expect(part.brand).to eq("Hastings Manufacturing")
      expect(part.description).to start_with("Hastings Manufacturing part number 2C4504")
      expect(part.category).to eq("Engine")
      expect(part.subcategory).to eq("Piston Ring")
      expect(part.grade).to eq("Standard Replacement")
      expect(part.status).to eq("complete")
    end

    it "parses the summary fields" do
      expect(part.applications_count).to eq(40)
      expect(part.years_range).to eq("2010 to 2022")
      expect(part.makes).to contain_exactly("KIA", "Hyundai")
    end

    it "parses countries as ISO codes" do
      expect(part.countries).to contain_exactly("US", "CA")
    end

    it "parses attributes as class/attribute/unit/value" do
      expect(part.attributes).to be_an(Array)
      expect(part.attributes).to include({ class: nil, attribute: "Full Set", unit: nil, value: nil })
      expect(part.attributes).to include({ class: nil, attribute: "Top Groove", unit: nil, value: "1.20 mm" })
      expect(part.attributes).to include({ class: nil, attribute: "Engine. Bore (in.)", unit: nil, value: "3.032" })
    end

    it "parses the fitment table into structured vehicles" do
      expect(part.applications.length).to eq(40)

      first = part.applications.first
      expect(first).to be_a(Autofacts::Vehicle)
      expect(first.year).to eq(2022)
      expect(first.make).to eq("Hyundai")
      expect(first.model).to eq("Accent")
      expect(first.engine).to eq("1.6L L4")
    end

    it "builds the absolute URL from the path" do
      expect(part.url).to eq("https://autofactsdb.com/part/hastings-manufacturing/2c4504/")
    end
  end
end
