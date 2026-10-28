# frozen_string_literal: true

require "embed_sync"
require_relative "support/database"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    EmbedSync.config.provider = :fake
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  # Delete rows instead of wrapping examples in a transaction, so after_commit callbacks fire.
  config.after do
    EmbedSync.reset_config!
    [Product, Category].each(&:delete_all)
  end
end
