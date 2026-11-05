# frozen_string_literal: true

# Link the junction tables to the countries catalog via a real foreign key, and
# keep the country codes referentially valid.
Sequel.migration do
  up do
    drop_table :part_countries
    create_table(:part_countries) do
      foreign_key :part_id, :parts, null: false, on_delete: :cascade
      foreign_key :country_code, :countries, key: :code, type: String, null: false, on_delete: :cascade
      primary_key %i[part_id country_code]
    end

    drop_table :brand_countries
    create_table(:brand_countries) do
      foreign_key :brand_id, :part_brands, null: false, on_delete: :cascade
      foreign_key :country_code, :countries, key: :code, type: String, null: false, on_delete: :cascade
      primary_key %i[brand_id country_code]
    end
  end

  down do
    drop_table :part_countries
    create_table(:part_countries) do
      foreign_key :part_id, :parts, null: false, on_delete: :cascade
      String :country_code, null: false
      primary_key %i[part_id country_code]
    end

    drop_table :brand_countries
    create_table(:brand_countries) do
      foreign_key :brand_id, :part_brands, null: false, on_delete: :cascade
      String :country_code, null: false
      primary_key %i[brand_id country_code]
    end
  end
end
