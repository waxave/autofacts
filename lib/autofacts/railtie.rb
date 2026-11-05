# frozen_string_literal: true

require "rails/railtie"

module Autofacts
  # Registers the Autofacts generator with Rails. Only loaded when Rails is
  # present, so plain-Ruby usage is unaffected.
  class Railtie < Rails::Railtie
    generators do
      require_relative "generators/autofacts/install_generator"
    end
  end
end
