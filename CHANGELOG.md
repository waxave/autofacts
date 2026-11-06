# Changelog

## [2.3.0] - 2026-11-05

- Rails and CLI commands now share database-path resolution through
  `AUTOFACTS_DATABASE_PATH` and `config/autofacts.yml`.
- The Rails generator creates `config/autofacts.yml`, and `autofacts seed`
  reports the database path it uses.

- Require subcategory aliases to match complete normalized phrases while
  retaining prefix matching for names, slugs and translations.

- Catalog brands, countries, categories and subcategories are now returned in
  ascending display-name order, including localized taxonomy names.
- Expanded category and subcategory aliases improve full-text search coverage.

- Fixed standalone FRACO and ELGIN configuration when running the installed gem
  outside the source checkout. Provider defaults are now bundled, while local
  `config/brands.yml` files remain supported as overrides.
- Exposed local full-text catalog searches through `Client#search_brands`,
  `Client#search_categories` and `Client#search_subcategories`.
- Category and subcategory catalog results now expose all available
  translations, including parent-category translations on subcategories.

## [2.0.0] - 2026-11-05

- **Breaking:** redesigned the `Autofacts::Client` surface around data and
  lookups: `brands`, `categories`, `subcategories`, `countries`, `find`,
  `part` and `vehicle`.
  - Removed `get_part_brands`, `search_parts`, `get_part` and
    `get_vehicle_parts`.
  - `Client.new` no longer needs `database:`; it defaults to
    `Autofacts.database_path`.
- `part(part_number, brand:)` validates the brand against the configured
  standalone brands and the local catalog; unknown brands raise **before any
  request**. `part(url:)` is also accepted, and the request URL is always built
  by the scraper.
- `vehicle(...)` resolves the `category` through the seeded taxonomy full-text
  search (names/aliases/translations) and validates it before the request;
  unknown or ambiguous categories fail fast with no request.
- `vehicle` builds AutoFactsDB category URLs correctly (`&` → `and`,
  transmission categories reordered), e.g. `fuel` → `fuel-and-air-parts` and
  `brake` → `brake-and-wheel-hub-parts`.
- Removed the `autofacts scrape` CLI command.
- `brands`, `categories` and `subcategories` are seeded by `autofacts install`.
  The 504 AutoFactsDB catalog brands now live in
  `lib/autofacts/data/brands.yml` and are seeded from that bundled YAML (no
  HTML-fixture parsing), while standalone brands stay in `config/brands.yml`.
- `autofacts part` now takes a part number plus `--brand` (name) or `--url`;
  `autofacts find` takes only the part number.

## [1.0.1] - 2026-11-05

- Added `Autofacts::PartNumber.clean`; `get_part` and `search_parts` now remove
  the `+STD` variant marker (anywhere, case-insensitive) before requesting.

## [1.0.0] - 2026-11-05

- Renamed the search preview model to `SearchResult`; `Part` is now the
  persistent autopart.
- Added domain models and tables: `Part`, `VehicleBrand`, `Vehicle`,
  `part_applications` (part↔vehicle relation), `part_countries`, `Category`,
  `Subcategory`, and a generic `Translation` table for localizing
  category/subcategory/attribute names.
- Search results (`autofacts find`) are now saved as `partial` `search_results`;
  scraping their detail marks them `complete`.
- Added the part-detail scraper: `Parsers.parse_part_detail`,
  `Scrapers::AutofactsDb#part_detail`, `Client#get_part`, and `autofacts part
  <url>`. It stores the full part plus vehicle brands, vehicles, part
  applications, markets and summary fields (years, makes, application count).
- `find` gained `--database` (results are persisted) and `part` gained
  `--json`.
- Search results now become `complete` whether the detail is scraped before or
  after the search.
- `part_countries` references the `countries` catalog via a foreign key, and
  missing country codes are added to the catalog.
- `parts.description` now stores the detail page's prose description, and
  `search_results.description` stores the full search-card title
  ("Brand MPN — Type").
- Added the vehicle-category scraper: `Parsers.parse_vehicle_category`,
  `Scrapers::AutofactsDb#vehicle_category`, `Client#get_vehicle_parts`, and
  `autofacts vehicle <make> <year> <model> <category>`. It builds the URL,
  parses the subcategory/tier tables, expands "Fits: All engines", and
  persists vehicle brands, vehicles, parts, part applications, notes (part
  attributes) and markets (part countries).
- Part countries now link to real catalog countries (no more `name = code`
  placeholders) — missing ISO codes are filled from the built-in catalog.
- Vehicle-category parts are stored as `complete`.
- Part detail URLs are built from brand + part number (`--brand`), via the
  `part_path` helper.
- Added the multi-provider client: `config/brands.yml` now drives scraper
  dispatch. Standalone brands (e.g. FRACO) declare `source`/`source_url`/
  `fixtures_dir`; `find`/`part` dispatch to the registered scraper.
- Added `Scrapers::Fraco` (simepa.mx): parses the component attributes table
  and the fitment applications table (titleized makes, one application per
  year, engine from liters + motor type).
- Added `Scrapers::Elgin` (catalog.elginind.com): resolves the part UUID via
  `/part-autocomplete/`, parses `#specifications-table` (merging `… UOM` rows
  into `unit`), the marketing description and `main > div > ul` attributes,
  and expands Year ranges (`1999–16`) into one application per year.
- FRACO and ELGIN parts now record markets `MX` and `US` (configurable per
  brand via `countries:` in `config/brands.yml`), so their applications expand
  with alpha-2/alpha-3 country codes.
- Added `Autofacts.install` and `autofacts install` to create/migrate the
  SQLite catalog and seed it in one step.
- Added a Rails `autofacts:install` generator (Railtie) that creates
  `db/autofacts.sqlite3`, migrates/seeds it, writes
  `config/initializers/autofacts.rb`, and updates `.gitignore`. The gem keeps
  its own SQLite database, separate from the host app's database.
- Restructured `part_attributes` to `(class, attribute, unit, value)`
  (dropping `name`/`position`).
- Renamed relation tables for clarity: `makes` → `vehicle_brands` (model
  `Make` → `VehicleBrand`), `applications` → `part_applications`.
- Removed `brand_countries` (brand-level countries); part markets live in
  `part_countries`.
- Added full-text search for part brands (`part_brands_fts`, FTS5) with prefix
  matching; `autofacts search` uses it.
- Added `Category`/`Subcategory` read models and the `autofacts categories` /
  `autofacts subcategories [--category SLUG]` commands (`--locale` for
  translated names).
- Added `lib/autofacts/data/categories.yml` (22 categories / 453
  subcategories) and `Seeder#seed_categories`; `autofacts seed` now upserts the
  taxonomy by explicit slug, including machine-translated Spanish (`es`) names
  written to `translations`.
- Added `Repository#store_category` / `#store_subcategory` (slug-preserving
  upserts used by seeding).
- Added full-text search for categories and subcategories
  (`categories_fts` / `subcategories_fts`, FTS5) covering slug, name,
  translations and curated `aliases:` from `categories.yml` (aliases on all
  categories and common subcategories, e.g. `balatas`, `mofle`, `birlo`); the
  seeder rebuilds the index.
- `autofacts search` is now unified: it matches brands, categories and
  subcategories (prefix match) and labels each result by type; taxonomy
  results accept `--locale` for translated display names.
- Client lookups accept `fields:` to return only the requested attributes as
  symbol-keyed hashes (`get_part`, `search_parts`, `get_part_brands`,
  `get_vehicle_parts`); omitting it keeps the full model objects.
- Part reads now return `category`/`subcategory` as
  `{ name:, translations: { locale => text } }`, expose `attributes_count`,
  expand `applications` to one entry per vehicle × market with ISO alpha-2
  (`country_code`) and alpha-3 (`country_alpha3`), and return `years_range` as
  `[min, max]`. `status` and `makes` are internal-only and excluded from
  `to_h`/returned fields.
- Added ISO 3166-1 alpha-3 codes to the `countries` catalog (`alpha_3`) and
  `Country`.
- Normalized the part schema: `parts` stores only `brand_id`, `part_number`,
  `category_id`, `subcategory_id`, `grade`, `description`, `status` +
  timestamps. Brand, category and subcategory are relations (`part_brands`,
  `categories`, `subcategories`); attributes are normalized into
  `part_attributes` (`class`/`attribute`/`unit`/`value`); derived values
  (`brand`, `url`, `applications_count`, `years_range`, `makes`, `attributes`,
  `countries`) are computed on read. Category/subcategory translations are
  exposed on part reads; attribute names are localized via `translations`
  (read with `locale:`).
- Part lookups are local-first and accept a URL, `brand-slug/part-number`, or a
  bare part number (brand resolved from stored parts/search results when
  omitted). `complete` parts are returned without a request.

## [0.2.0] - Unreleased

- Added part-number search: `Autofacts::Parsers.parse_search_results`,
  `Autofacts::Scrapers::AutofactsDb#search`, `Client#search_parts`, and the
  `autofacts find <mpn>` command. `find` prints an aligned table by default,
  with `--verbose` for full details and `--json` for structured output.
  Search previews expose structured `applications` (`{ year, vehicle, engine }`)
  and `attributes` lists (the preview model became `SearchResult` in 0.3.0).
- `FixtureSource` encodes query strings into fixture filenames
  (`=` → `-`, `&` → `_`), e.g. `/search/?q=2C45` → `search/q-2C45.html`.

## [0.1.1] - Unreleased

- Brands now record **where to search**: `source` + `source_url`.
- Added a reusable `countries` table (ISO 3166-1), seeded from
  `lib/autofacts/data/countries.yml` (249 countries).
- Added `Autofacts::Seeder` for the built-in country list and `config/brands.yml`.
- Added a pluggable scraper registry (`Autofacts::Scrapers`) with the built-in
  `AutofactsDb` scraper and a generic, selector-driven `SelectorScraper` skeleton
  for standalone brands.
- Added a Thor-based CLI (`autofacts seed`, `scrape brands`, `brands`,
  `countries`, `search`).
- Documented the CLI, the `config/brands.yml` format and standalone brands.
- Fixed the `autofacts` executable so it loads when run directly from a checkout
  (added the gem's `lib/` to the load path).
- `autofacts seed` now also ingests the AutoFactsDB brand index from saved pages
  in `./fixtures` (configurable with `--fixtures`), so seeding works offline and
  produces the full catalog brand list.

## [0.1.0] - Unreleased

- Initial skeleton: declarative `Model` base, errors, Sequel-backed SQLite
  database with migrations, and the read-through `Client`.
- `part_brands` + `catalog_meta` + `scrape_state` tables.
- Part-brands index scraper (`/part/`) with URL/slug extraction and catalog
  "last updated" metadata capture.
- `HttpSource` (live) and `FixtureSource` (offline saved pages) fetch backends.
