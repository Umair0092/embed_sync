# frozen_string_literal: true

require_relative "embed_sync/version"
require_relative "embed_sync/errors"
require_relative "embed_sync/configuration"
require_relative "embed_sync/providers"

# Keeps vector embeddings in sync with ActiveRecord models.
module EmbedSync
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_config!
      @config = nil
    end

    def provider
      config.resolved_provider
    end
  end
end
