# frozen_string_literal: true

RSpec.describe Autofacts::Parsers do
  describe ".slug_from_url" do
    it "extracts the last path segment" do
      expect(described_class.slug_from_url("https://autofactsdb.com/part/gm-genuine/"))
        .to eq("gm-genuine")
    end

    it "handles a bare slug" do
      expect(described_class.slug_from_url("https://autofactsdb.com/part/3d/"))
        .to eq("3d")
    end

    it "returns an empty string for empty input" do
      expect(described_class.slug_from_url("")).to eq("")
      expect(described_class.slug_from_url(nil)).to eq("")
    end
  end

  describe ".parse_part_count" do
    it "parses a comma-separated count" do
      expect(described_class.parse_part_count("1,243,293 part numbers")).to eq(1_243_293)
    end

    it "returns nil when there is no count" do
      expect(described_class.parse_part_count("No count here")).to be_nil
    end
  end

  describe ".parse_brand_index" do
    let(:html) do
      <<~HTML
        <html><body>
          <main id="main">
            <div>
              <div>
                <p>
                  <span class="badge--verified" title="Application data last refreshed Sep 26, 2026 (UTC)">Catalog updated · Sep 2026</span>
                  <span>·</span><span>504 Brands</span><span>·</span><span>20,858,993 Part numbers</span>
                </p>
              </div>
            </div>
          </main>
          <div id="popular-brands-section">
            <div class="grid">
              <a class="brand-card" href="https://autofactsdb.com/part/gm-genuine/">
                <span class="brand-card-name">GM Genuine</span>
                <div class="small muted">1,243,293 part numbers</div>
              </a>
            </div>
          </div>
          <div id="all-brands">
            <div id="brands" class="grid">
              <a class="brand-card" href="https://autofactsdb.com/part/gm-genuine/">
                <span class="brand-card-name">GM Genuine</span>
                <div class="small muted">1,243,293 part numbers</div>
              </a>
              <a class="brand-card" href="https://autofactsdb.com/part/dorman/">
                <span class="brand-card-name">Dorman</span>
                <div class="small muted">1,072,977 part numbers</div>
              </a>
            </div>
          </div>
        </body></html>
      HTML
    end

    it "parses every brand with slug and url" do
      index = described_class.parse_brand_index(html)

      expect(index.brands.length).to eq(2)
      expect(index.count).to eq(2)

      gm = index.brands.find { |b| b.slug == "gm-genuine" }
      expect(gm.name).to eq("GM Genuine")
      expect(gm.url).to eq("https://autofactsdb.com/part/gm-genuine/")
      expect(gm.part_numbers_count).to eq(1_243_293)
      expect(gm.popular).to be(true)
    end

    it "marks only popular-section brands as popular" do
      index = described_class.parse_brand_index(html)
      dorman = index.brands.find { |b| b.slug == "dorman" }
      expect(dorman.popular).to be(false)
    end

    it "captures the catalog metadata" do
      index = described_class.parse_brand_index(html)

      expect(index.last_updated).to eq("Catalog updated · Sep 2026")
      expect(index.last_refreshed_at).to eq("Application data last refreshed Sep 26, 2026 (UTC)")
      expect(index.brand_count).to eq(504)
      expect(index.part_numbers_count).to eq(20_858_993)
    end
  end

  describe ".parse_brand_index against the real saved page" do
    it "parses the full A-Z brand list" do
      index = described_class.parse_brand_index(read_fixture("part/index.html"))

      expect(index.brands.length).to eq(504)
      expect(index.brand_count).to eq(504)
      expect(index.brands.map(&:slug).uniq.length).to eq(504)
      expect(index.brands.count(&:popular)).to eq(12)
    end

    it "captures URL and slug for a known brand" do
      index = described_class.parse_brand_index(read_fixture("part/index.html"))
      gm = index.brands.find { |b| b.slug == "gm-genuine" }

      expect(gm.name).to eq("GM Genuine")
      expect(gm.url).to eq("https://autofactsdb.com/part/gm-genuine/")
      expect(gm.part_numbers_count).to eq(1_243_293)
    end
  end
end
