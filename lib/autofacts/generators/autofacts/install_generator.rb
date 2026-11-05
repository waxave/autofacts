# frozen_string_literal: true

require "rails/generators"

module Autofacts
  module Generators
    # `rails generate autofacts:install`
    #
    # Creates the gem's own SQLite catalog (migrated + seeded) and an initializer
    # that points Autofacts.database_path at it.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install Autofacts: create/migrate/seed the SQLite catalog and add an initializer."

      def create_initializer
        copy_file "autofacts.rb", "config/initializers/autofacts.rb"
      end

      def install_database
        summary = Autofacts.install(path: database_path, seed: true)
        say "Autofacts database ready at #{summary[:path]}"
      end

      def update_gitignore
        append_to_file ".gitignore", "\n# Autofacts local catalog\ndb/autofacts.sqlite3\n"
      end

      private

      def database_path
        Rails.root.join("db/autofacts.sqlite3")
      end
    end
  end
end
