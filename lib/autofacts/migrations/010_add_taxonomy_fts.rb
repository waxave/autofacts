# frozen_string_literal: true

# Full-text search for the part taxonomy. Each FTS row keeps the source
# category/subcategory id plus a `terms` bag containing the slug, name,
# translations and curated aliases. The seeder rebuilds these tables so search
# stays in sync with the YAML taxonomy.
Sequel.migration do
  up do
    run <<~SQL
      CREATE VIRTUAL TABLE categories_fts USING fts5(
        category_id UNINDEXED, slug, terms
      )
    SQL
    run <<~SQL
      CREATE VIRTUAL TABLE subcategories_fts USING fts5(
        subcategory_id UNINDEXED, slug, terms
      )
    SQL

    # Best-effort backfill so search works before the first re-seed.
    run "INSERT INTO categories_fts(category_id, slug, terms) SELECT id, slug, name FROM categories"
    run "INSERT INTO subcategories_fts(subcategory_id, slug, terms) SELECT id, slug, name FROM subcategories"
  end

  down do
    drop_table :subcategories_fts
    drop_table :categories_fts
  end
end
