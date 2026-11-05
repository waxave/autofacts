# frozen_string_literal: true

module Autofacts
  # A top-level part category, e.g. "Engine".
  class Category < Model
    attribute :slug          # e.g. "engine"
    attribute :name, default: nil
    attribute :translations, default: -> { }
  end
end
