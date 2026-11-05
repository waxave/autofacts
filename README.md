# Autofacts

A Ruby client and local catalog for [AutoFactsDB.com](https://autofactsdb.com/)
— the free OEM & aftermarket fitment catalog. Autofacts fetches catalog data
(part brands, vehicle makes/models, years, engine configurations and parts) and
persists it into a local SQLite database, incrementally and without
re-requesting data it already has.

It also ships a small CLI for seeding that database and searching it.

## Installation

```ruby
gem "autofacts"
```

Create (or migrate) the gem's SQLite catalog and seed it:

```sh
autofacts install
# Database ready at autofacts.sqlite3
# Seeded 249 countries
# Seeded 2 configured brands
# Seeded 22 categories and 453 subcategories (475 translations)
```

`autofacts install` runs the migrations and seeds countries, categories and the
brands in `config/brands.yml`. Use `--database PATH`, `--brands PATH`, or
`--no-seed` as needed.

### Rails

Autofacts keeps its **own SQLite catalog**, separate from the Rails app
database. This works with any Rails database (PostgreSQL, MySQL or SQLite) and
keeps the SQLite-only FTS5 tables out of your app schema.

```sh
rails generate autofacts:install
```

The generator creates `db/autofacts.sqlite3`, migrates and seeds it, writes
`config/initializers/autofacts.rb`, and adds the database to `.gitignore`. Then:

```ruby
client = Autofacts::Client.new(database: Autofacts.database_path)
```

## Quick start

```ruby
require "autofacts"

client = Autofacts::Client.new(database: "autofacts.sqlite3")

brands = client.get_part_brands
puts "Stored #{brands.count} part brands"
puts "Catalog updated: #{brands.last_updated}"
```

By default the client talks to the live site. To scrape from saved pages
instead (offline), pass a `FixtureSource` rooted at a directory that mirrors the
site's URL paths:

```ruby
source = Autofacts::Source::FixtureSource.new("fixtures")
client = Autofacts::Client.new(database: ":memory:", source: source)
```

## Using in another app

Add the gem to your `Gemfile` (from the repo while it's unpublished):

```ruby
gem "autofacts", path: "/path/to/autofacts"
```

```ruby
require "autofacts"

# One client per process; everything is persisted to the SQLite file.
client = Autofacts::Client.new(database: "autofacts.sqlite3")

# Brand index (writes part_brands)
client.get_part_brands

# Part-number search (writes partial search_results)
results = client.search_parts("2C45")
results.parts.each { |p| puts "#{p.part_number} #{p.brand} — #{p.description}" }

# Full part detail (writes part, attributes, part applications, markets)
part = client.get_part("2c4504", brand: "hastings-manufacturing")
part.attributes       # => [{ class:, attribute:, unit:, value: }, ...]
part.attributes_count # => 7
part.category         # => { name: "Engine", translations: { es: "Motor" } }
part.applications     # => [{ year:, make:, model:, engine:, country_code:, country_alpha3: }, ...]
part.years_range      # => [2010, 2022]
part.countries        # => ["US", "CA"]

# Parts that fit a vehicle/category (writes parts + part applications)
listing = client.get_vehicle_parts(make: "nissan", year: 2007, model: "altima", category: "engine")
client.close
```

### Selecting fields

By default the client returns model objects. Pass `fields:` to any lookup to get
plain **symbol-keyed hashes** with only the attributes you need:

```ruby
client.get_part("2c4504", brand: "hastings-manufacturing",
                fields: %i[part_number brand category])
# => { part_number: "2c4504", brand: "Hastings Manufacturing",
#      category: { name: "Engine", translations: { es: "Motor" } } }

client.search_parts("2C45", fields: %i[part_number brand description])
# => [{ part_number: "...", brand: "...", description: "..." }, ...]

client.get_part_brands(fields: %i[slug name part_numbers_count])
# => [{ slug: "denso", name: "DENSO", part_numbers_count: ... }, ...]

client.get_vehicle_parts(make: "nissan", year: 2007, model: "altima",
                         category: "engine", fields: %i[part_number brand subcategory])
# => [{ part_number: "...", brand: "...", subcategory: "..." }, ...]
```

`fields:` selects the **leaf records** (`Part`, `PartBrand`, `SearchResult`,
`VehiclePart`) and drops the wrapper metadata. Omit it when you need the full
objects (pagination, counts, `last_updated`). Field names may be symbols or
strings; unknown names are ignored.

### Part-number cleaning

Incoming part numbers are normalized before any lookup or request. The first
rule removes the `+STD` variant marker (anywhere, case-insensitive), so
`client.get_part("HL-7025S+STD", brand: "elgin")` looks up `HL-7025S`.
`search_parts` cleans its query the same way.

Read straight from the local database without scraping:

```ruby
db   = Autofacts::Database.new("autofacts.sqlite3")
repo = Autofacts::Repository.new(db.db)

repo.part("hastings-manufacturing", "2c4504")                # => Autofacts::Part
repo.part("hastings-manufacturing", "2c4504", locale: "es")  # localized attributes
repo.parts_by_part_number("2c4504")                          # => [Autofacts::Part]
repo.search_results                                          # => [Autofacts::SearchResult]
repo.countries                                               # => [Autofacts::Country]
repo.categories                                              # => [Autofacts::Category]
repo.subcategories(category_slug: "engine")                  # => [Autofacts::Subcategory]
repo.search_categories("balatas")                            # => [Autofacts::Category]
repo.search_subcategories("balance")                         # => [Autofacts::Subcategory]
```

### Standalone brands

`config/brands.yml` decides which scraper handles a brand (default
`autofactsdb`). Point the client at your seed file; `part`/`find` then dispatch by
brand automatically:

```ruby
client = Autofacts::Client.new(
  database: "autofacts.sqlite3",
  brand_config_path: "config/brands.yml"
)

part = client.get_part("FSX-5840301", brand: "fraco")
```

### CLI from your app

```ruby
Autofacts::CLI.start(["part", "2c4504", "--brand", "hastings-manufacturing"])
```

## CLI

```sh
# Seed the ISO country list, the brands in config/brands.yml, the category
# taxonomy (with Spanish translations) and the AutoFactsDB brand index from
# the saved pages in ./fixtures
autofacts seed

# Point at a different saved-pages directory (or a subset of pages)
autofacts seed --fixtures ~/Downloads/autofacts

# Re-scrape the brand index (use --fixtures to stay offline)
autofacts scrape brands
autofacts scrape brands --fixtures fixtures

# Inspect what is stored
autofacts brands
autofacts countries
autofacts categories
autofacts subcategories
autofacts subcategories --category engine   # filter by category slug
autofacts categories --locale es            # translated names
autofacts subcategories --category engine --locale es
autofacts search toyota
autofacts search den
autofacts search balatas                 # category alias -> Brake & Wheel Hub
autofacts search balance --locale es     # subcategories, translated names

# Search the catalog by part number (live, or offline from saved pages)
autofacts find 2C45
autofacts find 2C45 --fixtures fixtures
autofacts find 2C45 --verbose          # full details per part
autofacts find 2C45 --json             # structured JSON
autofacts find 2C45 --page 2

# Scrape + save a full part detail (complete fitment)
autofacts part /part/hastings-manufacturing/2c4504/
autofacts part hastings-manufacturing/2c4504
autofacts part 2c4504                    # brand resolved from local data
autofacts part 2c4504 --brand hastings-manufacturing   # build the URL from brand + part number
autofacts part FSX-5840301 --brand fraco --fixtures fixtures   # standalone brand
autofacts part 2c4504 --fixtures fixtures --json

# Scrape parts that fit a vehicle (builds /vehicles/MAKE/YEAR/MODEL/CATEGORY-parts/)
autofacts vehicle nissan 2007 altima engine
autofacts vehicle nissan 2007 altima engine --fixtures fixtures --json
```

`find` prints an aligned table by default (`PART #`, `BRAND`, `CATEGORY`,
`SUB-CATEGORY`); `--verbose`/`--json` are also available. It saves each result
as a `partial` search result. `part <url>` scrapes the detail page, stores the
full `Part` (with vehicle brands, vehicles, part applications and markets), and
marks the matching search result `complete`.

`part` also accepts `brand-slug/part-number` or a bare part number. Lookups are
**local-first**: a stored `complete` part is returned without a network request.
When only a part number is given, the brand is resolved from stored parts (or
saved search results) to complete the lookup.

All commands accept `--database PATH` (default `./autofacts.sqlite3`). `seed`
also accepts `--brands PATH` (default `./config/brands.yml`) and `--fixtures DIR`
(default `./fixtures`). Run `autofacts help [COMMAND]` for usage or
`autofacts tree` to list every command.

### Running offline from saved pages

Pass `--fixtures DIR` to any scrape command to read saved HTML files instead of
the live site. The layout mirrors the URL paths:

| Command | Fixture file |
|---|---|
| `autofacts seed` / `scrape brands` | `fixtures/part/index.html` |
| `autofacts find 2C45 --fixtures fixtures` | `fixtures/search/q-2C45.html` |
| `autofacts part hastings-manufacturing/2c4504 --fixtures fixtures` | `fixtures/part/hastings-manufacturing/2c4504/index.html` |
| `autofacts part HL-7025S --brand elgin --fixtures fixtures` | `fixtures/elgin/HL-7025S/index.html` + `autocomplete.html` |
| `autofacts vehicle nissan 2007 altima engine --fixtures fixtures` | `fixtures/vehicles/nissan/2007/altima/engine-parts/index.html` |

So the vehicle category example, fully offline:

```sh
autofacts vehicle nissan 2007 altima engine --fixtures fixtures
# builds /vehicles/nissan/2007/altima/engine-parts/ and reads
# fixtures/vehicles/nissan/2007/altima/engine-parts/index.html
# prints the summary + first 20 parts (use --limit N, or --json for all 768)
```

Query-string pages are encoded into the filename (`=` → `-`, `&` → `_`), e.g.
`/search/?q=2C45` → `fixtures/search/q-2C45.html` and
`/search/?q=2C45&page=2` → `fixtures/search/q-2C45_page-2.html`.

## How scraping works

Every fetch is **read-through**: the client checks the local database first and
skips the request when that page has already been scraped (`scrape_state` marks
it `complete`). Empty results are remembered too, so they aren't re-requested.
Pass `force: true` to re-fetch and refresh:

```ruby
client.get_part_brands(force: true)
```

## Brands and sources

Each brand records **where to search**:

- `source` — the scraper/source key (`"autofactsdb"` for the built-in catalog).
- `source_url` — the base URL to search (used by standalone brands).
- `countries` — optional ISO alpha-2 markets the scraper attaches to parts
  (FRACO and ELGIN use `[MX, US]`).

`config/brands.yml` drives which scraper handles a brand. Brands default to
`source: autofactsdb`; standalone brands declare their own `source`,
`source_url`, `scraper` and `fixtures_dir`, and the client dispatches `find` /
`part` by brand:

```yaml
brands:
  - slug: gm-genuine
    name: GM Genuine
    source: autofactsdb

  - slug: fraco
    name: FRACO
    source: fraco
    scraper: fraco
    source_url: https://simepa.mx/Simepa.mx/admin/buscador
    fixtures_dir: fraco
    countries: [MX, US]

  - slug: elgin
    name: ELGIN
    source: elgin
    scraper: elgin
    source_url: https://catalog.elginind.com
    fixtures_dir: elgin
    countries: [MX, US]

  - slug: acme
    name: ACME Parts
    source: acme
    source_url: https://acmeparts.example.com
    scraper: selector
    fixtures_dir: fixtures/acme/
    selectors:
      part: ".part-listing"
      mpn: ".mpn"
      name: ".part-name"
```

```sh
autofacts part FSX-5840301 --brand fraco --fixtures fixtures
autofacts part HL-7025S --brand elgin --fixtures fixtures
```

`search` is a unified full-text lookup (prefix match) across **brands,
categories and subcategories**. It matches slugs, names, translations and the
curated `aliases` in `categories.yml`:

```sh
autofacts search den          # brand:       DENSO (denso)
autofacts search balatas      # category:    Brake & Wheel Hub (brake-wheel-hub)
autofacts search motor -l es  # category:    Motor (engine) + matching subcategories
```

Taxonomy results are labeled `category:` / `subcategory:`; subcategories include
their parent category for context.

The `countries` table is a reusable, normalized lookup seeded from the
[ISO 3166-1 list](https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes).
A part's markets are stored in `part_countries` (`country_code` →
`countries.code`); missing codes are added to the catalog on write.

## Seed data

`autofacts seed` upserts the built-in data files and the configured brands:

- `lib/autofacts/data/countries.yml` — ISO 3166-1 countries (alpha-2 + alpha-3).
- `lib/autofacts/data/categories.yml` — 22 categories + 453 subcategories,
  each with a `translations:` map (`es`) plus curated `aliases:` on categories
  and common subcategories (search synonyms such as `balatas`, `mofle`,
  `birlo`, `rin`, `clutch`, `cadena de tiempo`).
- `config/brands.yml` — configured / standalone brands.

Translations are stored in the `translations` table. Part reads expose them on
`category`/`subcategory` via the nested `translations` map; `--locale` (CLI) and
`locale:` (repository) localize part attribute names. Seeding also rebuilds the
taxonomy full-text index (`categories_fts` / `subcategories_fts`) from each
entry's slug, name, translations and aliases, so `autofacts search` finds them.
Edit `categories.yml` and re-run `autofacts seed` to correct a translation or
add an alias.

## Data model

- `Part` — the autopart. Stored: `part_number`, `description`, `grade`, `status`,
  plus relations to `part_brands` (brand), `categories`, `subcategories`,
  `part_attributes` (`class`/`attribute`/`unit`/`value`), `part_countries`
  (markets), and `part_applications` (vehicles). On read it exposes `brand`,
  `category`/`subcategory` as `{ name:, translations: { locale => text } }`,
  `attributes` + `attributes_count`, `countries`, `applications` (one flat hash
  per vehicle × market with `year`/`make`/`model`/`engine`, `country_code`
  alpha-2 and `country_alpha3`), `applications_count`, `url`, and `years_range`
  as `[min, max]`. `status` and `makes` are internal and excluded from `to_h`.
- `SearchResult` — a saved search preview (`brand_slug`, `part_number`, `brand`,
  `description` = the full card title, `category`, `subcategory`, `attributes`,
  `applications`, `applications_count`, `status`: `partial` → `complete`).
- `SearchResults` — `query`, `page`, `parts`, `next_page_url`, `result_count`.
- `VehicleBrand` — a vehicle brand/make (`slug`, `name`).
- `Vehicle` — a year + brand + model + engine configuration.
- `VehicleCategory` — a vehicle category listing (make/year/model/category +
  meta) with `VehiclePart` entries (brand, part number, subcategory, tier,
  markets, notes, engines). Scraped with `autofacts vehicle`.
- `Country` — `code` (ISO alpha-2), `alpha_3` (ISO alpha-3), `name`,
  `description`; the catalog that `part_countries` references via a
  `country_code` foreign key (missing codes are added to the catalog on write).
- `Category` — a part category (`slug`, `name`), listed with
  `autofacts categories`, searched with `autofacts search`, and seeded from
  `lib/autofacts/data/categories.yml`.
- `Subcategory` — a subcategory inside a category (`slug`, `name`, `category`
  = parent slug, `category_name`), listed with `autofacts subcategories` or
  filtered with `--category SLUG`. Also seeded from `categories.yml` and
  searchable via `autofacts search`.
- `Translation` — localized text for any translatable field
  (`translatable_type`, `translatable_id`, `field`, `locale`, `text`).
  `categories.yml` ships machine-translated Spanish (`es`) names for every
  category and subcategory; `autofacts seed` writes them.

Search results are persisted as `partial`; scraping the detail with
`autofacts part` stores the full `Part` and marks the matching result `complete`.
Category, subcategory and attribute names are localized through `translations`
(read a part with `locale:` to get translated names). The `categories`,
`subcategories` and `search` CLI commands accept `--locale` too.

## Development

```sh
bundle install
bundle exec rspec
```

## Disclaimer

This client is for educational and legitimate research purposes. Respect
AutoFactsDB's terms of service, implement appropriate rate limiting, and do not
abuse the service or scrape large datasets without permission.
