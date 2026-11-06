# frozen_string_literal: true

module Autofacts
  # A parts brand (e.g. "DENSO", "Bosch") and the number of part numbers the
  # catalog lists for it.
  class PartBrand < Model
    DEFAULT_SOURCE = "autofactsdb"

    attribute :slug               # URL slug, e.g. "denso"
    attribute :name               # Display name, e.g. "DENSO"
    attribute :url, default: nil  # Absolute URL of the brand page
    attribute :part_numbers_count, default: nil # Integer, parsed from "N part numbers"
    attribute :popular, default: false          # Listed under "Most Listed Brands"
    attribute :source, default: DEFAULT_SOURCE  # Which scraper/site to search
    attribute :source_url, default: nil         # Base URL for standalone brands
    attribute :aliases, default: nil            # Exact-match alternate names
  end
end
