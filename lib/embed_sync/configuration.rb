# frozen_string_literal: true

module EmbedSync
  # Global settings, changed through EmbedSync.configure.
  class Configuration
    attr_accessor :default_model, :queue, :priority, :batch_size, :query_cache, :query_cache_expires_in,
                  :concurrency_limit
    attr_reader :sync, :provider, :provider_options

    def initialize
      @provider = :ruby_llm
      @provider_options = {}
      @default_model = nil
      @queue = :default
      @batch_size = 100
      @sync = :async
      @query_cache = nil
      @query_cache_expires_in = 86_400
      @priority = nil
      @concurrency_limit = nil
    end

    SYNC_MODES = [:async, :inline, false].freeze

    # :async enqueues EmbedSync::EmbedJob after commit, :inline embeds right away, false turns syncing off.
    def sync=(mode)
      raise ConfigurationError, "sync must be one of #{SYNC_MODES.inspect}" unless SYNC_MODES.include?(mode)

      @sync = mode
    end

    # Accepts a registered provider name (e.g. :fake) or any object that responds to #embed.
    def provider=(value)
      @provider = value
      @resolved_provider = nil
    end

    def provider_options=(options)
      @provider_options = (options || {}).to_h.transform_keys(&:to_sym)
      @resolved_provider = nil
    end

    def resolved_provider
      @resolved_provider ||= build_provider
    end

    private

    def build_provider
      case provider
      when nil
        raise ConfigurationError, "No embedding provider configured. Set EmbedSync.config.provider."
      when Symbol, String
        Providers.build(provider, **provider_options)
      else
        raise ConfigurationError, "#{provider.inspect} does not respond to #embed" unless provider.respond_to?(:embed)

        provider
      end
    end
  end
end
