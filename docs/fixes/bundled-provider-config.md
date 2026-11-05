# Bundled provider configuration

## Status
In progress

## Bug Summary
ELGIN and FRACO are not recognized when Autofacts is run outside the source checkout.

## Branch
`fix/bundled-provider-config`

## Reproduction Steps
1. Run `bundle exec autofacts part HL-7025S --brand ELGIN --json` without a local `config/brands.yml`.
2. Observe `Unknown brand "ELGIN"`.

## Expected Behavior
The gem uses its bundled ELGIN and FRACO provider configuration by default. A local `config/brands.yml` may override it.

## Actual Behavior
Provider configuration is loaded only from the current working directory.

## Suspected Cause
`BrandConfig.load` and installation resolve `config/brands.yml` relative to the host directory, and the standalone configuration is not bundled as runtime data.

## Affected Areas
- `BrandConfig`
- `Seeder`
- `Autofacts.install`
- gem packaging

## Fix Plan
Bundle the standalone provider configuration, use it as the fallback, preserve explicit local overrides, and seed provider brands during installation.

## Regression Tests
- Installation from an unrelated directory seeds ELGIN and FRACO.
- Client dispatches ELGIN and FRACO using bundled configuration.

## Notes
The catalog brand seed remains separate from standalone provider configuration.
