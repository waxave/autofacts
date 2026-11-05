# frozen_string_literal: true

module Autofacts
  # A part subcategory inside a category, e.g. "Balance Shaft Chain".
  class Subcategory < Model
    attribute :slug                   # e.g. "balance-shaft-chain"
    attribute :name, default: nil
    attribute :translations, default: -> { }
    attribute :category, default: nil # parent category slug
    attribute :category_name, default: nil
    attribute :category_translations, default: -> { }
  end
end
