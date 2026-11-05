# frozen_string_literal: true

module Autofacts
  # A full autopart (detail page). Uniquely identified by brand slug + part
  # number; `complete` once its detail page has been scraped.
  class Part < Model
    DEFAULT_STATUS = "partial"

    # `status` and `makes` are internal bookkeeping and stay out of `to_h`.
    hide :status, :makes

    attribute :brand_slug
    attribute :part_number
    attribute :brand, default: nil
    attribute :description, default: nil  # long prose description (detail page)
    attribute :category, default: nil     # { name:, translations: { locale => text } }
    attribute :subcategory, default: nil  # { name:, translations: { locale => text } }
    attribute :grade, default: nil
    attribute :url, default: nil
    attribute :attributes, default: -> { [] }   # Array<Hash> { class:, attribute:, unit:, value: }
    attribute :attributes_count, default: nil
    attribute :countries, default: -> { [] }    # Array<String> ISO alpha-2 codes
    attribute :applications, default: -> { [] } # Array<Hash> with country_code/country_alpha3
    attribute :applications_count, default: nil
    attribute :years_range, default: nil        # Array [min, max]
    attribute :makes, default: -> { [] }        # Array<String> (internal)
    attribute :status, default: DEFAULT_STATUS  # "partial" | "complete" (internal)
  end
end
