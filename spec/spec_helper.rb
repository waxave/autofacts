# frozen_string_literal: true

require "autofacts"
require "webmock/rspec"
require "json"
require "nokogiri"
require "stringio"
require "tmpdir"

WebMock.disable_net_connect!(allow_localhost: true)

# Root of the saved-page fixtures. Relative paths mirror site URLs:
#   /part/ -> <FIXTURES_DIR>/part/index.html
FIXTURES_DIR = File.expand_path("../fixtures", __dir__)

# Root of config fixtures (brands.yml, etc.).
CONFIG_FIXTURES_DIR = File.expand_path("fixtures/config", __dir__)

def read_fixture(relative)
  File.read(File.join(FIXTURES_DIR, relative))
end

# Capture the block's $stdout (returned) and $stderr (discarded separately).
def capture_io
  original_stdout = $stdout
  original_stderr = $stderr
  stdout = StringIO.new
  stderr = StringIO.new
  $stdout = stdout
  $stderr = stderr
  yield
  stdout.string
ensure
  $stdout = original_stdout
  $stderr = original_stderr
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
