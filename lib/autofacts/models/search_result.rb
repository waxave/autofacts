# frozen_string_literal: true

module Autofacts
  # A part as shown in a search-results card (a preview). Saved search results
  # are `partial`; they become `complete` once the part detail is scraped.
  class SearchResult < Model
    DEFAULT_STATUS = "partial"

    attribute :brand_slug              # e.g. "hastings-manufacturing"
    attribute :part_number             # e.g. "2c4504" (from the URL)
    attribute :brand, default: nil             # e.g. "Hastings Manufacturing"
    attribute :description, default: nil       # e.g. "Piston Ring"
    attribute :category, default: nil          # e.g. "Engine"
    attribute :subcategory, default: nil       # e.g. "Piston Ring"
    attribute :url, default: nil               # full part-detail URL
    attribute :applications, default: -> { [] }     # preview { year, vehicle, engine }
    attribute :applications_count, default: nil     # the N from "+N more"
    attribute :attributes, default: -> { [] }       # Array<String>
    attribute :status, default: DEFAULT_STATUS      # "partial" | "complete"
  end
end
