# frozen_string_literal: true

require "faraday"
require "faraday/follow_redirects"
require "faraday/gzip"

module Autofacts
  module Source
    # Fetches catalog pages over HTTP.
    class HttpSource
      def initialize(base_url: Autofacts::BASE_URL)
        @base_url = base_url
        @session = Faraday.new(url: base_url, request: { timeout: 30, open_timeout: 30 }) do |conn|
          conn.request :gzip
          conn.response :follow_redirects
          conn.response :raise_error
          conn.adapter Faraday.default_adapter
        end
      end

      # Fetch the HTML body for a path relative to the base URL (e.g. "/part/").
      def get(path)
        response = @session.get(path)
        response.body.to_s
      rescue Faraday::Error => e
        raise RequestError, "HTTP request failed for #{path}: #{e.message}"
      end

      def close
        @session.close if @session.respond_to?(:close)
      end
    end
  end
end
