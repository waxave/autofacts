# Autofacts

A Ruby client and local catalog for [AutoFactsDB.com](https://autofactsdb.com/)
— the free OEM & aftermarket fitment catalog. Autofacts fetches catalog data
(part brands, vehicle makes/models, years, engine configurations and parts) and
persists it into a local SQLite database, incrementally and without
re-requesting data it already has.

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
# Seeded 504 catalog brands
# Seeded 22 categories and 453 subcategories (475 translations)
```

`autofacts install` runs the migrations and seeds countries, the catalog
brands, the categories/subcategories and the brands in `config/brands.yml`.
Use `--database PATH`, `--brands PATH`, or `--no-seed` as needed.

### Rails

Autofacts keeps its **own SQLite catalog**, separate from the Rails app
database. This works with any Rails database (PostgreSQL, MySQL or SQLite) and
keeps the SQLite-only FTS5 tables out of your app schema.

```sh
rails generate autofacts:install
```

The generator creates `db/autofacts.sqlite3`, migrates and seeds it, writes
`config/initializers/autofacts.rb`, and adds the database to `.gitignore`. Then
just build a client:

```ruby
client = Autofacts::Client.new
```

## Quick start

```ruby
require "autofacts"

client = Autofacts::Client.new

client.brands.length      # => 506 (504 catalog + 2 standalone)
client.categories.length  # => 22
```

The database path is an implementation detail: `Autofacts::Client.new` uses
`Autofacts.database_path` (default `"autofacts.sqlite3"`, or
`db/autofacts.sqlite3` in Rails after the generator runs).

## Client

All methods below are on `Autofacts::Client`. Every lookup is **local-first**:
already-scraped data is returned from SQLite without a request.

### Seeded data (no network)

These come from the catalog created by `autofacts install`:

```ruby
client.brands                              # => [Autofacts::PartBrand]
client.categories                          # => [Autofacts::Category]
client.subcategories(category_slug: "engine") # => [Autofacts::Subcategory]
client.countries                           # => [Autofacts::Country]

brand = client.brands.first
brand.slug                 # => "3d"
brand.name                 # => "3D"
brand.part_numbers_count   # => 23348
brand.popular              # => false

category = client.categories.find { |c| c.slug == "engine" }
category.name              # => "Engine"

client.subcategories(category_slug: "engine").map(&:name).first
# => "Balance Shaft Bearing"
```

You can localize taxonomy names with `locale:`:

```ruby
client.categories(locale: "es").find { |c| c.slug == "engine" }.name
# => "Motor"
```

### Find a part by number

```ruby
results = client.find("2C45")

results.query          # => "2C45"
results.result_count   # => 20
results.parts.first    # => Autofacts::SearchResult
results.parts.first.part_number  # => "2c4504"
results.parts.first.brand        # => "Hastings Manufacturing"

results.parts.each { |p| puts "#{p.part_number} #{p.brand} — #{p.description}" }
```

Results are saved as `partial` search results. Paginate with `page:`:

```ruby
client.find("2C45", page: 2)
```

### Get a part

Pass the part number and the brand name. The scraper builds the URL; you never
construct paths or slugs.

```ruby
part = client.part("2c4504", brand: "Hastings Manufacturing")

part.part_number       # => "2c4504"
part.brand             # => "Hastings Manufacturing"
part.category          # => { name: "Engine", translations: { es: "Motor" } }
part.subcategory       # => { name: "Piston Ring", translations: { es: "Anillo del pistón" } }
part.attributes_count  # => 7
part.attributes        # => [{ class:, attribute:, unit:, value: }, ...]
part.applications_count # => 80
part.applications      # => [{ year:, make:, model:, engine:, country_code:, country_alpha3: }, ...]
part.years_range       # => [2010, 2022]
part.countries         # => ["US", "CA"]
part.url               # => "https://autofactsdb.com/part/hastings-manufacturing/2c4504/"
```

If you already have a part URL, pass it instead:

```ruby
client.part(url: "https://autofactsdb.com/part/hastings-manufacturing/2c4504/")
```

The brand is **validated before any request** against `config/brands.yml` and
the seeded catalog. An unknown brand raises immediately, without hitting the
network. If you omit the brand, it is resolved from stored parts/search results.

### Parts for a vehicle

```ruby
listing = client.vehicle(make: "nissan", year: 2007, model: "altima", category: "engine")

listing.title         # => "2007 Nissan Altima Engine Parts"
listing.parts_count   # => 768
listing.parts.length  # => 768
listing.parts.first.part_number  # => "ISBD42"
listing.parts.first.brand        # => "Topline"
```

`category` is a category name **or alias**, resolved through the taxonomy
full-text search and validated before the request:

```ruby
client.vehicle(make: "nissan", year: 2007, model: "altima", category: "motor")
# "motor" is an alias -> Engine
```

An unknown category raises (`Unknown category …; no request was made.`) and an
ambiguous one raises with the candidates.

### Selecting fields

By default the client returns model objects. Pass `fields:` to `find`, `part`
and `vehicle` to get plain **symbol-keyed hashes** with only what you need:

```ruby
client.part("2c4504", brand: "Hastings Manufacturing",
            fields: %i[part_number brand category])
# => { part_number: "2c4504", brand: "Hastings Manufacturing",
#      category: { name: "Engine", translations: { es: "Motor" } } }

client.find("2C45", fields: %i[part_number brand description])
# => [{ part_number: "...", brand: "...", description: "..." }, ...]

client.vehicle(make: "nissan", year: 2007, model: "altima",
               category: "engine", fields: %i[part_number brand subcategory])
# => [{ part_number: "...", brand: "...", subcategory: "..." }, ...]
```

Field names may be symbols or strings; unknown names are ignored.

### Part-number cleaning

Incoming part numbers are normalized before any lookup or request. The first
rule removes the `+STD` variant marker (anywhere, case-insensitive):

```ruby
client.part("HL-7025S+STD", brand: "ELGIN")   # looks up HL-7025S
client.find("2C45+STD")                       # searches 2C45
```

### Standalone brands

`config/brands.yml` decides which scraper handles a brand (default
`autofactsdb`). Standalone brands (FRACO, ELGIN) dispatch automatically:

```ruby
client.part("FSX-5840301", brand: "FRACO")
client.part("HL-7025S", brand: "ELGIN")
```

### Force refresh

Pass `force: true` to bypass the local cache and re-scrape:

```ruby
client.part("2c4504", brand: "Hastings Manufacturing", force: true)
```

## Brands and sources

Each brand records **where to search**:

- `source` — the scraper/source key (`"autofactsdb"` for the built-in catalog).
- `source_url` — the base URL to search (used by standalone brands).
- `countries` — optional ISO alpha-2 markets the scraper attaches to parts
  (FRACO and ELGIN use `[MX, US]`).

`config/brands.yml` drives which scraper handles a brand:

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

The `countries` table is a reusable, normalized lookup seeded from the
[ISO 3166-1 list](https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes).
A part's markets are stored in `part_countries` (`country_code` →
`countries.code`); missing codes are added to the catalog on write.

## Seed data

`autofacts install` / `autofacts seed` upsert the built-in data files:

- `lib/autofacts/data/countries.yml` — ISO 3166-1 countries (alpha-2 + alpha-3).
- `lib/autofacts/data/brands.yml` — 504 AutoFactsDB catalog brands (slug, name,
  URL, part-number count, popular flag).
- `lib/autofacts/data/categories.yml` — 22 categories + 453 subcategories,
  each with a `translations:` map (`es`) plus curated `aliases:` on categories
  and common subcategories (search synonyms such as `balatas`, `mofle`,
  `birlo`, `rin`, `clutch`, `cadena de tiempo`).
- `config/brands.yml` — configured / standalone brands.

Translations are stored in the `translations` table. Part reads expose them on
`category`/`subcategory` via the nested `translations` map; `locale:` localizes
part attribute names. Seeding also rebuilds the taxonomy full-text index
(`categories_fts` / `subcategories_fts`) from each entry's slug, name,
translations and aliases. Edit `categories.yml` and re-run `autofacts seed` to
correct a translation or add an alias.

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
  markets, notes, engines). Returned by `client.vehicle`.
- `Country` — `code` (ISO alpha-2), `alpha_3` (ISO alpha-3), `name`,
  `description`; the catalog that `part_countries` references via a
  `country_code` foreign key.
- `Category` — a part category (`slug`, `name`), seeded from `categories.yml`.
- `Subcategory` — a subcategory inside a category (`slug`, `name`, `category`
  = parent slug, `category_name`), seeded from `categories.yml`.
- `Translation` — localized text for any translatable field
  (`translatable_type`, `translatable_id`, `field`, `locale`, `text`).

## Development

Advanced usage and internals.

### CLI

```sh
# Create/migrate the database and seed countries, taxonomy, configured brands
# and the AutoFactsDB catalog brands
autofacts install

# Re-seed later (same data; safe to re-run)
autofacts seed

# Inspect what is stored
autofacts brands
autofacts countries
autofacts categories
autofacts subcategories
autofacts subcategories --category engine   # filter by category slug
autofacts categories --locale es            # translated names
autofacts subcategories --category engine --locale es

# Unified full-text search across brands, categories and subcategories
autofacts search toyota
autofacts search den
autofacts search balatas                 # category alias -> Brake & Wheel Hub
autofacts search balance --locale es     # subcategories, translated names

# Search the catalog by part number
autofacts find 2C45
autofacts find 2C45 --verbose          # full details per part
autofacts find 2C45 --json             # structured JSON
autofacts find 2C45 --page 2

# Fetch a part detail: part number + brand (name), or a URL
autofacts part 2c4504 --brand "Hastings Manufacturing"
autofacts part 2c4504                    # brand resolved from local data
autofacts part --url /part/hastings-manufacturing/2c4504/
autofacts part FSX-5840301 --brand FRACO
autofacts part HL-7025S --brand ELGIN
autofacts part 2c4504 --brand "Hastings Manufacturing" --json

# Scrape parts that fit a vehicle. CATEGORY is a category name or alias
# (resolved via full-text search and validated before the request)
autofacts vehicle nissan 2007 altima engine
autofacts vehicle nissan 2007 altima motor          # alias -> Engine
```

All commands accept `--database PATH` (default `./autofacts.sqlite3`).
`install`/`seed` also accept `--brands PATH` (default `./config/brands.yml`).
Run `autofacts help [COMMAND]` for usage or `autofacts tree` for the command
tree.

You can also call the CLI from Ruby:

```ruby
Autofacts::CLI.start(["part", "2c4504", "--brand", "Hastings Manufacturing"])
```

### How scraping works

Every fetch is **read-through**: the client checks the local database first and
skips the request when that page has already been scraped (`scrape_state` marks
it `complete`). Empty results are remembered too, so they aren't re-requested.
Pass `force: true` (client) to re-fetch and refresh.

### Repository (low-level)

The client is the recommended API. If you need direct reads, use the
repository:

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

### Running the tests

```sh
bundle install
bundle exec rspec
```

## Playground

Experiment with the scrapers against saved pages instead of the live site.

### Running offline from saved pages

Pass `--fixtures DIR` (CLI) or a `FixtureSource` (Ruby) to read saved HTML
files. The directory layout mirrors the site's URL paths.

```ruby
source = Autofacts::Source::FixtureSource.new("fixtures")
client = Autofacts::Client.new(database: ":memory:", source: source)
```

```sh
autofacts find 2C45 --fixtures fixtures
autofacts part 2c4504 --brand "Hastings Manufacturing" --fixtures fixtures
autofacts part HL-7025S --brand ELGIN --fixtures fixtures
autofacts vehicle nissan 2007 altima engine --fixtures fixtures --json
```

| Command | Fixture file |
|---|---|
| `autofacts find 2C45 --fixtures fixtures` | `fixtures/search/q-2C45.html` |
| `autofacts part 2c4504 --brand "Hastings Manufacturing" --fixtures fixtures` | `fixtures/part/hastings-manufacturing/2c4504/index.html` |
| `autofacts part HL-7025S --brand ELGIN --fixtures fixtures` | `fixtures/elgin/HL-7025S/index.html` + `autocomplete.html` |
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

## Disclaimer

This client is for educational and legitimate research purposes. Respect
AutoFactsDB's terms of service, implement appropriate rate limiting, and do not
abuse the service or scrape large datasets without permission.
