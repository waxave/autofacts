# frozen_string_literal: true

module Autofacts
  # A country from the ISO 3166-1 list. Reusable across catalog tables.
  class Country < Model
    attribute :code          # ISO 3166-1 alpha-2, e.g. "US"
    attribute :alpha_3, default: nil # ISO 3166-1 alpha-3, e.g. "USA"
    attribute :name          # Short name, e.g. "United States of America"
    attribute :description, default: nil # Full ISO name, e.g. "United States of America (the)"
  end
end
