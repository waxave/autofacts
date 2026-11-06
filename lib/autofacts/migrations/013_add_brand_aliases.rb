# frozen_string_literal: true

# Stores exact-match aliases for part brands separately from the token-prefix
# full-text index.
Sequel.migration do
  up do
    create_table :brand_aliases do
      primary_key :id
      foreign_key :brand_id, :part_brands, null: false, on_delete: :cascade
      String :alias_text, null: false
      String :normalized_text, null: false
      unique [:brand_id, :normalized_text]
    end
  end

  down do
    drop_table :brand_aliases
  end
end
