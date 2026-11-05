# frozen_string_literal: true

require_relative "scrapers/base"
require_relative "scrapers/autofactsdb"
require_relative "scrapers/selector_scraper"
require_relative "scrapers/fraco"
require_relative "scrapers/elgin"

module Autofacts
  # Registry mapping a brand's `source` key to the scraper that handles it.
  module Scrapers
    REGISTRY = {
      AutofactsDb::SOURCE => AutofactsDb,
      SelectorScraper::SOURCE => SelectorScraper,
      Fraco::SOURCE => Fraco,
      Elgin::SOURCE => Elgin
    }.freeze

    module_function

    # Resolve the scraper class for a source key. Unknown sources use the
    # generic selector-driven scraper.
    def for(source)
      REGISTRY.fetch(source.to_s) { SelectorScraper }
    end

    # Build a scraper instance for a source key.
    def build(source_key, source:, config: {})
      self.for(source_key).new(source: source, config: config)
    end
  end
end
