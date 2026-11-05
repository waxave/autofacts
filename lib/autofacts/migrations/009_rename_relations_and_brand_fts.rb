# frozen_string_literal: true

# Clarify the relation table names and add full-text search for part brands.
#   makes        -> vehicle_brands
#   applications -> part_applications
#   brand_countries is removed (part markets live in part_countries)
Sequel.migration do
  up do
    run "ALTER TABLE makes RENAME TO vehicle_brands"
    run "ALTER TABLE applications RENAME TO part_applications"
    drop_table :brand_countries

    run <<~SQL
      CREATE VIRTUAL TABLE part_brands_fts USING fts5(
        name, slug, content='part_brands', content_rowid='id'
      )
    SQL
    run "INSERT INTO part_brands_fts(rowid, name, slug) SELECT id, name, slug FROM part_brands"

    run <<~SQL
      CREATE TRIGGER part_brands_fts_ai AFTER INSERT ON part_brands BEGIN
        INSERT INTO part_brands_fts(rowid, name, slug) VALUES (new.id, new.name, new.slug);
      END
    SQL
    run <<~SQL
      CREATE TRIGGER part_brands_fts_ad AFTER DELETE ON part_brands BEGIN
        INSERT INTO part_brands_fts(part_brands_fts, rowid, name, slug)
        VALUES ('delete', old.id, old.name, old.slug);
      END
    SQL
    run <<~SQL
      CREATE TRIGGER part_brands_fts_au AFTER UPDATE ON part_brands BEGIN
        INSERT INTO part_brands_fts(part_brands_fts, rowid, name, slug)
        VALUES ('delete', old.id, old.name, old.slug);
        INSERT INTO part_brands_fts(rowid, name, slug) VALUES (new.id, new.name, new.slug);
      END
    SQL
  end

  down do
    run "DROP TRIGGER IF EXISTS part_brands_fts_ai"
    run "DROP TRIGGER IF EXISTS part_brands_fts_ad"
    run "DROP TRIGGER IF EXISTS part_brands_fts_au"
    drop_table :part_brands_fts

    run "ALTER TABLE vehicle_brands RENAME TO makes"
    run "ALTER TABLE part_applications RENAME TO applications"

    create_table(:brand_countries) do
      foreign_key :brand_id, :part_brands, null: false, on_delete: :cascade
      foreign_key :country_code, :countries, key: :code, type: String, null: false, on_delete: :cascade
      primary_key %i[brand_id country_code]
    end
  end
end
