# frozen_string_literal: true

module Autofacts
  # The result of scraping a vehicle category page (parts that fit a car/year/
  # model/category).
  class VehicleCategory < Model
    attribute :make
    attribute :year
    attribute :model
    attribute :category
    attribute :make_name, default: nil
    attribute :model_name, default: nil
    attribute :category_name, default: nil
    attribute :title, default: nil
    attribute :parts_count, default: nil
    attribute :part_types_count, default: nil
    attribute :brands_count, default: nil
    attribute :engine_options_count, default: nil
    attribute :last_updated, default: nil
    attribute :parts, default: -> { [] } # Array<VehiclePart>

    def count
      parts.length
    end
  end
end
