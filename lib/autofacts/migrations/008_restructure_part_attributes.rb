# frozen_string_literal: true

# Restructure part attributes to (class, attribute, unit, value). `name` and
# `position` are dropped.
Sequel.migration do
  up do
    drop_table :part_attributes
    create_table(:part_attributes) do
      primary_key :id
      foreign_key :part_id, :parts, null: false, on_delete: :cascade
      String :class
      String :attribute
      String :unit
      String :value
      index :part_id
    end
  end

  down do
    drop_table :part_attributes
    create_table(:part_attributes) do
      primary_key :id
      foreign_key :part_id, :parts, null: false, on_delete: :cascade
      String :name
      String :value
      Integer :position
      index :part_id
    end
  end
end
