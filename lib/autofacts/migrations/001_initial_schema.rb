# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:part_brands) do
      primary_key :id
      String :slug, null: false, unique: true
      String :name, null: false
      String :url
      Integer :part_numbers_count
      TrueClass :popular, null: false, default: false
      DateTime :first_seen_at
      DateTime :last_seen_at
    end

    create_table(:catalog_meta) do
      String :key, primary_key: true
      String :value
      DateTime :updated_at
    end

    create_table(:scrape_state) do
      String :entity_type, null: false
      String :key, null: false
      String :status, null: false
      Integer :row_count
      String :error
      DateTime :scraped_at
      primary_key %i[entity_type key]
    end
  end
end
