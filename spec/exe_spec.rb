# frozen_string_literal: true

require "open3"

RSpec.describe "exe/autofacts" do
  let(:exe) { File.expand_path("../exe/autofacts", __dir__) }

  it "runs directly without needing -Ilib on the load path" do
    # Drop Bundler's environment so this reproduces running the executable
    # directly (as a user would after cloning the repo).
    clean_env = ENV.keys.grep(/\ABUNDLE/).to_h { |key| [key, nil] }
    clean_env.merge!("RUBYOPT" => nil, "RUBYLIB" => nil)

    stdout, status = Open3.capture2e(clean_env, "ruby", exe, "--help")

    expect(status).to be_success, stdout
    expect(stdout).to include("seed")
  end
end

