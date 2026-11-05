# frozen_string_literal: true

require_relative "autofacts/version"
require_relative "autofacts/errors"
require_relative "autofacts/part_number"
require_relative "autofacts/model"
require_relative "autofacts/models"
require_relative "autofacts/parsers"
require_relative "autofacts/source/http_source"
require_relative "autofacts/source/fixture_source"
require_relative "autofacts/db"
require_relative "autofacts/repository"
require_relative "autofacts/brand_config"
require_relative "autofacts/scrapers"
require_relative "autofacts/seeder"
require_relative "autofacts/client"
require_relative "autofacts/install"

require_relative "autofacts/railtie" if defined?(Rails)

# Autofacts — fetch and persist the AutoFactsDB.com fitment catalog into a
# local SQLite database.
module Autofacts
end
