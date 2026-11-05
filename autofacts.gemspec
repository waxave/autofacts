# frozen_string_literal: true

require_relative "lib/autofacts/version"

Gem::Specification.new do |spec|
  spec.name          = "autofacts"
  spec.version       = Autofacts::VERSION
  spec.authors       = ["Jesus Urias"]
  spec.email         = ["xesvs@pm.me"]

  spec.summary       = "Ruby client and local catalog for AutoFactsDB.com"
  spec.description   = "Fetch and persist the AutoFactsDB.com automotive fitment " \
                       "catalog — part brands, makes, models, years, engine " \
                       "configurations and parts — into a local SQLite database, " \
                       "with incremental, resume-safe scraping."
  spec.homepage      = "https://github.com/waxave/autofacts"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["source_code_uri"] = "https://github.com/waxave/autofacts"
  spec.metadata["changelog_uri"]   = "https://github.com/waxave/autofacts/blob/main/CHANGELOG.md"
  spec.files = Dir.glob("lib/**/*.{rb,yml}") + %w[LICENSE README.md CHANGELOG.md exe/autofacts]
  spec.bindir        = "exe"
  spec.executables   = ["autofacts"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", ">= 2.0"
  spec.add_dependency "faraday-follow_redirects", ">= 0.3"
  spec.add_dependency "faraday-gzip", ">= 1.0"
  spec.add_dependency "nokogiri", ">= 1.13"
  spec.add_dependency "sequel", ">= 5.0"
  spec.add_dependency "sqlite3", ">= 1.4"
  spec.add_dependency "thor", ">= 1.2"

  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", ">= 3.0"
  spec.add_development_dependency "webmock", ">= 3.0"
end
