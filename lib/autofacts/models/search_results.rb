# frozen_string_literal: true

module Autofacts
  # The result of a part-number search: the matched parts plus pagination info.
  class SearchResults < Model
    attribute :query
    attribute :parts
    attribute :page, default: 1
    attribute :next_page_url, default: nil
    attribute :result_count, default: nil # reported "N parts"

    def count
      parts.length
    end

    def next_page?
      !next_page_url.nil?
    end
  end
end
