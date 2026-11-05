# frozen_string_literal: true

module Autofacts
  # The result of scraping the part-brands index page (/part/): the full list
  # of brands plus the catalog metadata shown on the page.
  class BrandIndex < Model
    attribute :brands                     # Array<PartBrand>
    attribute :last_updated, default: nil         # e.g. "Catalog updated · Sep 2026"
    attribute :last_refreshed_at, default: nil    # Precise refresh stamp from the page title
    attribute :brand_count, default: nil          # e.g. 504
    attribute :part_numbers_count, default: nil   # e.g. 20_858_993

    def count
      brands.length
    end
  end
end
