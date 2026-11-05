# frozen_string_literal: true

module Autofacts
  # A vehicle brand/make (car manufacturer), e.g. "Nissan".
  class VehicleBrand < Model
    attribute :slug          # e.g. "nissan"
    attribute :name, default: nil
  end
end
