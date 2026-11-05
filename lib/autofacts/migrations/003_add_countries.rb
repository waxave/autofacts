# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:countries) do
      String :code, primary_key: true
      String :name, null: false
      String :description
    end

    create_table(:brand_countries) do
      foreign_key :brand_id, :part_brands, null: false, on_delete: :cascade
      String :country_code, null: false
      primary_key %i[brand_id country_code]
    end
  end
end
