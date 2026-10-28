# frozen_string_literal: true

require "active_support"
require "active_support/lazy_load_hooks"

require_relative "embed_sync/version"
require_relative "embed_sync/errors"
require_relative "embed_sync/configuration"
require_relative "embed_sync/providers"
require_relative "embed_sync/definition"

# Keeps vector embeddings in sync with ActiveRecord models.
module EmbedSync
  autoload :Model, "embed_sync/model"

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

ActiveSupport.on_load(:active_record) do
  include EmbedSync::Model
end
