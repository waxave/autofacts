# frozen_string_literal: true

module Autofacts
  # A localized string for a translatable field of another record, e.g. a
  # category/subcategory name or an attribute in a given locale.
  class Translation < Model
    attribute :translatable_type   # e.g. "part"
    attribute :translatable_id
    attribute :field               # e.g. "category", "subcategory", "attributes"
    attribute :locale              # e.g. "es"
    attribute :text
  end
end
