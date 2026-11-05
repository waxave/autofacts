# frozen_string_literal: true

# Autofacts keeps its own SQLite catalog, separate from the Rails app database.
# `rails g autofacts:install` created db/autofacts.sqlite3 and seeded it.
Autofacts.database_path = Rails.root.join("db/autofacts.sqlite3")

# Build a client on demand:
#   client = Autofacts::Client.new(database: Autofacts.database_path)
