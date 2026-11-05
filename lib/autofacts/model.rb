# frozen_string_literal: true

module Autofacts
  # Minimal declarative base class for the data models.
  #
  # Provides lightweight, validation-style model behaviour:
  #   * `attribute :name`                 -> required (missing key raises)
  #   * `attribute :name, default: value` -> optional with default
  #   * `attribute :name, default: -> {}` -> factory for mutable defaults
  #   * `hide :name`                      -> keep the attribute but exclude it
  #                                          from `to_h` / returned fields
  #   * unknown keyword arguments are silently ignored
  #
  # Subclasses may define a `validate!` method to normalize/validate input.
  class Model
    UNSET = Object.new.freeze

    class << self
      def attributes
        @attributes ||= {}
      end

      def hidden_attributes
        @hidden_attributes ||= []
      end

      # Keep attributes available on the object but out of `to_h`/serialization.
      def hide(*names)
        @hidden_attributes = hidden_attributes | names.map(&:to_sym)
      end

      def public_attributes
        attributes.keys - hidden_attributes
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@attributes, attributes.dup)
        subclass.instance_variable_set(:@hidden_attributes, hidden_attributes.dup)
      end

      def attribute(name, default: UNSET)
        attributes[name] = default
        attr_accessor name
      end
    end

    def initialize(**kwargs)
      self.class.attributes.each do |name, default|
        if kwargs.key?(name)
          instance_variable_set(:"@#{name}", kwargs[name])
        elsif !default.equal?(UNSET)
          instance_variable_set(:"@#{name}", default.respond_to?(:call) ? default.call : default)
        else
          raise ArgumentError, "missing keyword: #{name}"
        end
      end

      validate! if respond_to?(:validate!)
    end

    # Serialize the public attributes (hidden ones are internal-only).
    def to_h
      attribute_hash(self.class.public_attributes)
    end

    def ==(other)
      other.is_a?(self.class) && all_attributes_hash == other.all_attributes_hash
    end
    alias eql? ==

    def hash
      [self.class, all_attributes_hash].hash
    end

    def inspect
      "#<#{self.class.name} #{to_h.map { |k, v| "#{k}=#{v.inspect}" }.join(' ')}>"
    end

    protected

    def all_attributes_hash
      attribute_hash(self.class.attributes.keys)
    end

    def attribute_hash(keys)
      keys.to_h { |name| [name, public_send(name)] }
    end
  end
end
