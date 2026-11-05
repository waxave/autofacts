# frozen_string_literal: true

module Autofacts
  module Scrapers
    # Base class for source-specific scrapers. A scraper reads pages from a
    # Source (live HTTP or saved fixtures) and returns model objects.
    class Base
      attr_reader :source

      def initialize(source:, config: {})
        @source = source
        @config = config || {}
      end

      def scrape_brand_index
        raise NotImplementedError, "#{self.class}#scrape_brand_index is not implemented"
      end

      def scrape_brand(_brand)
        raise NotImplementedError, "#{self.class}#scrape_brand is not implemented"
      end

      def scrape_part(_brand_slug, _part_number)
        raise NotImplementedError, "#{self.class}#scrape_part is not implemented"
      end

      private

      attr_reader :config
    end
  end
end
