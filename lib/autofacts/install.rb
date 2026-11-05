# frozen_string_literal: true

module Autofacts
  class << self
    # Accepts a String or Pathname (e.g. Rails.root.join(...)).
    def database_path=(value)
      @database_path = value.to_s
    end

    # Default SQLite path used by `Autofacts.install` and the Rails initializer.
    def database_path
      @database_path ||= "autofacts.sqlite3"
    end

    # Create/migrate the SQLite database and optionally seed it.
    #
    # The gem keeps its own SQLite catalog (separate from a host app's database),
    # so the SQLite-only FTS5 tables never touch the app's schema.
    #
    # Returns a summary hash: `{ path:, countries:, brands:, categories: }`.
    def install(path: database_path, seed: true, brands_path: "config/brands.yml",
                categories_path: Seeder::CATEGORIES_PATH)
      database = Database.new(path.to_s)
      summary = { path: path.to_s }

      if seed
        repository = Repository.new(database.db)
        seeder = Seeder.new(repository, brands_path: existing_path(brands_path), categories_path: categories_path)
        summary.merge!(seeder.call)
      end

      summary
    ensure
      database&.close
    end

    private

    def existing_path(path)
      path && File.exist?(path.to_s) ? path : nil
    end
  end
end
