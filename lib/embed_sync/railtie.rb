# frozen_string_literal: true

module EmbedSync
  # Loads the rake tasks into Rails apps.
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks/embed_sync.rake", __dir__)
    end
  end
end
