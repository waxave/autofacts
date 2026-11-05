# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:makes) do
      primary_key :id
      String :slug, null: false, unique: true
      String :name
    end

    create_table(:vehicles) do
      primary_key :id
      foreign_key :make_id, :makes, null: false, on_delete: :cascade
      Integer :year, null: false
      String :model, null: false
      String :engine
      index %i[make_id year model engine], unique: true
    end

    create_table(:parts) do
      primary_key :id
      String :brand_slug, null: false
      String :part_number, null: false
      String :brand
      String :description
      String :category
      String :subcategory
      String :grade
      String :url
      String :attributes           # JSON array
      Integer :applications_count
      String :years_range
      String :makes                # JSON array
      String :last_updated
      String :last_refreshed_at
      String :status, null: false, default: "partial"
      DateTime :first_seen_at
      DateTime :last_seen_at
      index %i[brand_slug part_number], unique: true
    end

    create_table(:applications) do
      foreign_key :part_id, :parts, null: false, on_delete: :cascade
      foreign_key :vehicle_id, :vehicles, null: false, on_delete: :cascade
      primary_key %i[part_id vehicle_id]
    end

    create_table(:part_countries) do
      foreign_key :part_id, :parts, null: false, on_delete: :cascade
      String :country_code, null: false
      primary_key %i[part_id country_code]
    end

    create_table(:search_results) do
      primary_key :id
      String :query
      String :brand_slug, null: false
      String :part_number, null: false
      String :brand
      String :description
      String :category
      String :subcategory
      String :url
      String :attributes           # JSON array
      String :applications         # JSON array of previews
      Integer :applications_count
      String :status, null: false, default: "partial"
      DateTime :first_seen_at
      DateTime :last_seen_at
      index %i[brand_slug part_number], unique: true
    end

    create_table(:translations) do
      primary_key :id
      String :translatable_type, null: false
      Integer :translatable_id, null: false
      String :field, null: false
      String :locale, null: false
      String :text
      DateTime :updated_at
      index %i[translatable_type translatable_id field locale], unique: true
    end
  end
end
