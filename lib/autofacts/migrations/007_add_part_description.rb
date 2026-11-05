# frozen_string_literal: true

# The part detail page carries a prose description that we want to keep.
Sequel.migration do
  change do
    alter_table(:parts) do
      add_column :description, String
    end
  end
end
