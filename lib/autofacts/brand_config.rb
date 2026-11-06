# frozen_string_literal: true

require "yaml"

module Autofacts
  # Loads brand definitions from the brands YAML (config/brands.yml). This is
  # what lets the client dispatch a brand to the right scraper/source.
  class BrandConfig
    DEFAULT_PATH = File.expand_path("data/brands_config.yml", __dir__)

    def self.load(path = nil)
      configured_path = path && File.exist?(path.to_s) ? path.to_s : nil
      defaults = Array((YAML.safe_load_file(DEFAULT_PATH) || {})["brands"])
      overrides =
        if configured_path && File.expand_path(configured_path) != DEFAULT_PATH
          Array((YAML.safe_load_file(configured_path) || {})["brands"])
        else
          []
        end

      merged = defaults.map do |default|
        override = overrides.find { |brand| brand["slug"].to_s.casecmp?(default["slug"].to_s) }
        override ? default.merge(override) : default
      end
      default_slugs = defaults.map { |brand| brand["slug"].to_s.downcase }
      merged.concat(overrides.reject { |brand| default_slugs.include?(brand["slug"].to_s.downcase) })
      new(merged)
    end

    def self.empty
      new([])
    end

    def initialize(brands)
      @brands = brands
    end

    # Match a brand by slug, display name or exact alias (case-insensitive).
    def find(value)
      needle = value.to_s.strip.downcase
      return nil if needle.empty?

      @brands.find do |brand|
        brand["slug"].to_s.downcase == needle || brand["name"].to_s.downcase == needle ||
          Array(brand["aliases"]).any? { |alias_name| alias_name.to_s.downcase == needle }
      end
    end

    def config_for(slug)
      find(slug) || { "slug" => slug.to_s, "source" => "autofactsdb" }
    end

    def source_for(slug)
      config_for(slug).fetch("source", "autofactsdb")
    end
  end
end
