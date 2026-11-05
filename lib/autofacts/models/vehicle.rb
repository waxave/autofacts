# frozen_string_literal: true

module Autofacts
  # A vehicle configuration: a year + make + model + engine combination.
  class Vehicle < Model
    attribute :year
    attribute :make, default: nil   # make name, e.g. "Hyundai"
    attribute :model, default: nil  # e.g. "Accent"
    attribute :engine, default: nil # e.g. "1.6L L4"
  end
end
