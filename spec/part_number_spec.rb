# frozen_string_literal: true

RSpec.describe Autofacts::PartNumber do
  describe ".clean" do
    it "removes +STD anywhere in the value" do
      expect(described_class.clean("HL-7025S+STD")).to eq("HL-7025S")
      expect(described_class.clean("HL+STD-7025S")).to eq("HL-7025S")
      expect(described_class.clean("+STD")).to eq("")
    end

    it "is case-insensitive" do
      expect(described_class.clean("hl-7025s+std")).to eq("hl-7025s")
    end

    it "applies configured brand-specific removal rules after generic rules" do
      expect(described_class.clean("HL-7025S+STD", rules: { remove: ["-"] })).to eq("HL7025S")
    end

    it "trims whitespace and collapses inner spaces" do
      expect(described_class.clean("  HL-7025S +STD  ")).to eq("HL-7025S")
      expect(described_class.clean("HL  7025S")).to eq("HL 7025S")
    end

    it "leaves clean part numbers unchanged" do
      expect(described_class.clean("FSX-5840301")).to eq("FSX-5840301")
    end

    it "handles nil and empty values" do
      expect(described_class.clean(nil)).to eq("")
      expect(described_class.clean("")).to eq("")
    end
  end
end
