# frozen_string_literal: true

require "sequel"

module Autofacts
  # Owns the SQLite connection and applies schema migrations.
  class Database
    MIGRATIONS_PATH = File.expand_path("migrations", __dir__)

    attr_reader :db, :path

    # @param path [String, Symbol] SQLite file path, or :memory: for a
    #   transient in-memory database.
    def initialize(path = ":memory:")
      @path = path
      @db = Sequel.sqlite(path)
      run_migrations
    end

    def close
      @db.disconnect
    end

    private

    def run_migrations
      Sequel.extension :migration
      Sequel::Migrator.run(@db, MIGRATIONS_PATH)
    end
  end
end
