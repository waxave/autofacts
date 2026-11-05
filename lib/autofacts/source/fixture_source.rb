# frozen_string_literal: true

module Autofacts
  module Source
    # Reads saved HTML pages from a local directory whose layout mirrors the
    # site's URL paths (e.g. "/part/" -> "<root>/part/index.html").
    class FixtureSource
      def initialize(root)
        @root = File.expand_path(root)
      end

      # Fetch the HTML body for a URL path, reading the matching local file.
      def get(path)
        File.read(file_path_for(path))
      rescue Errno::ENOENT
        raise RequestError, "Fixture not found for #{path.inspect} (expected #{file_path_for(path)})"
      end

      private

      # Translate a URL path (or absolute URL) to a local file path.
      #
      # Query strings are encoded into the filename so multiple saved searches can
      # coexist: "/search/?q=2C45&page=2" -> "search/q-2C45_page-2.html".
      def file_path_for(path)
        uri = path.to_s.sub(%r{\Ahttps?://[^/]+}, "").sub(%r{\A/}, "")
        path_part, query = uri.split("?", 2)
        path_part = path_part.to_s
        query = query.to_s

        relative =
          if query && !query.empty?
            encoded = query.tr("=", "-").tr("&", "_")
            base = path_part.end_with?("/") ? path_part : "#{path_part}/"
            "#{base}#{encoded}.html"
          elsif path_part.empty?
            "index.html"
          elsif path_part.end_with?("/")
            "#{path_part}index.html"
          elsif path_part.end_with?(".html")
            path_part
          else
            "#{path_part}.html"
          end

        File.join(@root, relative)
      end
    end
  end
end
