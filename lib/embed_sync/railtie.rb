# frozen_string_literal: true

module EmbedSync
  # Hooks EmbedSync into Rails: rake tasks, logging and job settings.
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks/embed_sync.rake", __dir__)
    end

    initializer "embed_sync.log_subscriber" do
      require_relative "log_subscriber"
    end

    config.after_initialize do
      limit = EmbedSync.config.concurrency_limit
      EmbedSync::EmbedJob.apply_concurrency_limit(limit) if limit
    end
  end
end
