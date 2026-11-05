# frozen_string_literal: true

# Add the ISO 3166-1 alpha-3 code alongside the existing alpha-2 `code`.
Sequel.migration do
  change do
    add_column :countries, :alpha_3, String
  end
end
