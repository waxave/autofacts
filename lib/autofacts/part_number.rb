# frozen_string_literal: true

module Autofacts
  # Normalizes part numbers before they are used in lookups/requests.
  #
  # Rules are applied in order and can be extended as new catalog quirks are
  # found (e.g. vendor-specific suffixes).
  module PartNumber
    RULES = [
      # Drop the "+STD" variant marker wherever it appears (case-insensitive).
      ->(text) { text.gsub(/\+std/i, "") }
    ].freeze

    module_function

    # Return a cleaned part number ("HL-7025S+STD" -> "HL-7025S").
    def clean(value)
      text = value.to_s.strip
      RULES.each { |rule| text = rule.call(text) }
      text.strip.gsub(/\s+/, " ")
    end
  end
end
