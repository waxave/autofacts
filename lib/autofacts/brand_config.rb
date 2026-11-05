# frozen_string_literal: true

require "yaml"

module Autofacts
  # Loads brand definitions from the brands YAML (config/brands.yml). This is
  # what lets the client dispatch a brand to the right scraper/source.
  class BrandConfig
    def self.load(path)
      return empty unless path && File.exist?(path)

      data = YAML.safe_load_file(path) || {}
      new(Array(data["brands"]))
    end

    def self.empty
      new([])
    end

    def initialize(brands)
      @brands = brands
    end

    def find(slug)
      @brands.find { |brand| brand["slug"] == slug.to_s }
    end

    def config_for(slug)
      find(slug) || { "slug" => slug.to_s, "source" => "autofactsdb" }
    end

    def source_for(slug)
      config_for(slug).fetch("source", "autofactsdb")
    end
  end
end
