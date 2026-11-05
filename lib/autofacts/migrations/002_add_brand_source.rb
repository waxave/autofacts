# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:part_brands) do
      add_column :source, String, null: false, default: "autofactsdb"
      add_column :source_url, String
    end
  end
end
