# frozen_string_literal: true

RSpec.describe Autofacts::Parsers do
  describe ".parse_search_results" do
    let(:synthetic_html) do
      <<~HTML
        <html><body><main id="main"><section>
          <p class="muted small">2 parts · page 1</p>
          <div class="search-results">
            <div class="search-result">
              <a class="card" href="https://autofactsdb.com/part/acme/ab-123/">
                <strong>Acme AB-123 — Widget</strong>
                <div class="small muted">Engine · Widget</div>
                <div class="small">Fits: 2020 Ford Focus · 2.0L L4 <span class="muted"> +5 more — open for the full list</span></div>
                <div class="small muted">Color: Black; Size: Large</div>
              </a>
            </div>
            <div class="search-result">
              <a class="card" href="https://autofactsdb.com/part/acme/ab-456/">
                <strong>Acme AB-456 — Gadget</strong>
                <div class="small muted">Brake · Gadget</div>
                <div class="small">Fits: 2019 Honda Civic · 1.5L L4</div>
                <div class="small muted">Position: Front</div>
              </a>
            </div>
          </div>
          <nav class="chip-row">
            <span class="chip chip--static">Page 1</span>
            <a class="chip" href="https://autofactsdb.com/search/?q=AB&page=2" rel="next">Next →</a>
          </nav>
        </section></main></body></html>
      HTML
    end

    it "parses each result card into a Part with URL-derived identifiers" do
      results = described_class.parse_search_results(synthetic_html, query: "AB")

      expect(results).to be_a(Autofacts::SearchResults)
      expect(results.count).to eq(2)
      expect(results.result_count).to eq(2)
    end

    it "extracts brand_slug and part_number from the card URL" do
      part = described_class.parse_search_results(synthetic_html, query: "AB").parts.first

      expect(part.brand_slug).to eq("acme")
      expect(part.part_number).to eq("ab-123")
      expect(part.url).to eq("https://autofactsdb.com/part/acme/ab-123/")
    end

    it "extracts the brand, description, category and subcategory" do
      part = described_class.parse_search_results(synthetic_html, query: "AB").parts.first

      expect(part.brand).to eq("Acme")
      expect(part.description).to eq("Acme AB-123 — Widget")
      expect(part.category).to eq("Engine")
      expect(part.subcategory).to eq("Widget")
      expect(part.attributes).to eq(["Color: Black", "Size: Large"])
    end

    it "parses applications with year, vehicle and engine, plus the count" do
      parts = described_class.parse_search_results(synthetic_html, query: "AB").parts

      expect(parts[0].applications).to eq([
        { year: 2020, vehicle: "Ford Focus", engine: "2.0L L4" }
      ])
      expect(parts[0].applications_count).to eq(5)

      expect(parts[1].applications).to eq([
        { year: 2019, vehicle: "Honda Civic", engine: "1.5L L4" }
      ])
      expect(parts[1].applications_count).to be_nil
    end

    it "captures the next page URL" do
      results = described_class.parse_search_results(synthetic_html, query: "AB")

      expect(results.next_page_url).to eq("https://autofactsdb.com/search/?q=AB&page=2")
      expect(results.next_page?).to be(true)
    end

    describe "against the real saved search page" do
      let(:results) do
        described_class.parse_search_results(read_fixture("search/q-2C45.html"), query: "2C45")
      end

      it "parses all 20 results" do
        expect(results.count).to eq(20)
        expect(results.result_count).to eq(20)
      end

      it "extracts the first part's fields" do
        part = results.parts.first

        expect(part.brand_slug).to eq("hastings-manufacturing")
        expect(part.part_number).to eq("2c4504")
        expect(part.brand).to eq("Hastings Manufacturing")
        expect(part.description).to eq("Hastings Manufacturing 2C4504 — Piston Ring")
        expect(part.category).to eq("Engine")
        expect(part.subcategory).to eq("Piston Ring")
        expect(part.applications).to eq([
          { year: 2017, vehicle: "Hyundai Accent", engine: "1.6L L4" },
          { year: 2017, vehicle: "Hyundai Veloster", engine: "1.6L L4" },
          { year: 2016, vehicle: "Hyundai Accent", engine: "1.6L L4" },
          { year: 2016, vehicle: "Hyundai Veloster", engine: "1.6L L4" }
        ])
        expect(part.applications_count).to eq(33)
        expect(part.attributes).to include("Full Set")
      end

      it "parses multiple applications without a +N more suffix" do
        part = results.parts[15]

        expect(part.brand_slug).to eq("cardone")
        expect(part.part_number).to eq("2c4518")
        expect(part.applications).to eq([
          { year: 2002, vehicle: "Saturn SL Sedan", engine: "1.9L L4 SOHC" },
          { year: 1998, vehicle: "Saturn SC Coupe", engine: "1.9L L4 DOHC" }
        ])
        expect(part.applications_count).to be_nil
        expect(part.attributes).to eq(["Includes Bracket & Hardware", "Front Right", "with Metal Piston"])
      end

      it "exposes the next page" do
        expect(results.next_page_url).to include("page=2")
      end
    end
  end
end

RSpec.describe Autofacts::SearchResults do
  it "reports the number of parts and whether another page exists" do
    part = Autofacts::SearchResult.new(brand_slug: "acme", part_number: "ab-1")
    results = described_class.new(query: "AB", parts: [part], next_page_url: nil)

    expect(results.count).to eq(1)
    expect(results.next_page?).to be(false)
  end
end
