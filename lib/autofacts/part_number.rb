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
    def clean(value, rules: nil)
      text = value.to_s.strip
      RULES.each { |rule| text = rule.call(text) }
      Array(rules.is_a?(Hash) ? rules[:remove] || rules["remove"] : nil).each do |token|
        token = token.to_s
        next if token.empty?

        text = text.gsub(/#{Regexp.escape(token)}/i, "")
      end
      text.strip.gsub(/\s+/, " ")
    end
  end
end
