# frozen_string_literal: true

module Autofacts
  module Scrapers
    # Generic, selector-driven scraper for standalone brands. Its behavior is
    # described by a brand's YAML config (selectors + fixtures directory), so a
    # brand can be added without writing a dedicated Ruby class.
    class SelectorScraper < Base
      SOURCE = "selector"

      def fixtures_dir
        config["fixtures_dir"]
      end

      def selectors
        config["selectors"] || {}
      end
    end
  end
end
