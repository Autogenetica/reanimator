# frozen_string_literal: true

require "frankenstein"
require "timecop"
require "tmpdir"
require "fileutils"

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.include RepositoryFixture

  # Every fixture repository is created under a temp dir tracked per-example
  # and removed afterward, so specs never leak working trees.
  config.after do
    Array(@fixture_dirs).each { |dir| FileUtils.remove_entry(dir, true) }
  end

  # Keep configuration hermetic: reset any per-test overrides.
  config.after do
    Frankenstein.configuration = nil
  end
end
