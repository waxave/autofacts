# frozen_string_literal: true

module Autofacts
  # A part row on a vehicle category page (a part that fits this vehicle).
  class VehiclePart < Model
    attribute :brand_slug
    attribute :part_number
    attribute :brand, default: nil
    attribute :url, default: nil
    attribute :subcategory, default: nil
    attribute :subcategory_slug, default: nil
    attribute :tier, default: nil                 # Economy / Standard Replacement / Premium
    attribute :markets, default: -> { [] }        # Array<String> ISO country codes
    attribute :notes, default: -> { [] }          # Array<Hash> { name:, value: }
    attribute :engines, default: -> { [] }        # Array<String>, e.g. ["2.5L L4"]
  end
end
