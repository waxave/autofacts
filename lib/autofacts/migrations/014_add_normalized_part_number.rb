# frozen_string_literal: true

# Retain the caller/catalog part number as identity while recording the value
# sent to the provider after generic and brand-specific cleanup.
Sequel.migration do
  up do
    alter_table(:parts) do
      add_column :normalized_part_number, String, null: false, default: ""
    end
    run "UPDATE parts SET normalized_part_number = part_number"
  end

  down do
    alter_table(:parts) do
      drop_column :normalized_part_number
    end
  end
end
