# frozen_string_literal: true

# Stores subcategory aliases separately from the prefix-search index so aliases
# can be matched as complete phrases instead of individual FTS tokens.
Sequel.migration do
  up do
    create_table :taxonomy_aliases do
      primary_key :id
      String :entity_type, null: false
      Integer :entity_id, null: false
      String :alias_text, null: false
      String :normalized_text, null: false
      unique [:entity_type, :entity_id, :normalized_text]
    end
  end

  down do
    drop_table :taxonomy_aliases
  end
end
