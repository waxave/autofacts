# frozen_string_literal: true

# Rework the parts model into a normalized relational schema:
#   * brand / category / subcategory become relations (FKs)
#   * attributes become a part_attributes table (name/value pairs)
#   * derived columns (description, url, years_range, makes, applications_count,
#     last_updated) are dropped and computed on read
Sequel.migration do
  up do
    drop_table :part_countries
    drop_table :applications
    drop_table :parts

    create_table(:categories) do
      primary_key :id
      String :slug, null: false, unique: true
      String :name
    end

    create_table(:subcategories) do
      primary_key :id
      foreign_key :category_id, :categories, null: false, on_delete: :cascade
      String :slug, null: false
      String :name
      index %i[category_id slug], unique: true
    end

    create_table(:parts) do
      primary_key :id
      foreign_key :brand_id, :part_brands, null: false, on_delete: :cascade
      String :part_number, null: false
      foreign_key :category_id, :categories, on_delete: :set_null
      foreign_key :subcategory_id, :subcategories, on_delete: :set_null
      String :grade
      String :status, null: false, default: "partial"
      DateTime :first_seen_at
      DateTime :last_seen_at
      index %i[brand_id part_number], unique: true
    end

    create_table(:part_attributes) do
      primary_key :id
      foreign_key :part_id, :parts, null: false, on_delete: :cascade
      String :name
      String :value
      Integer :position
      index :part_id
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
  end

  down do
    drop_table :part_countries
    drop_table :applications
    drop_table :part_attributes
    drop_table :parts
    drop_table :subcategories
    drop_table :categories
  end
end
