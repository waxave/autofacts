# frozen_string_literal: true

module Autofacts
  # Base error for all Autofacts errors.
  class Error < StandardError; end

  # Raised when an HTTP request fails.
  class RequestError < Error; end

  # Raised when a fetched page cannot be parsed.
  class ParseError < Error; end
end
