# frozen_string_literal: true

require "active_job"

module EmbedSync
  # Regenerates one record's embedding in the background.
  class EmbedJob < ActiveJob::Base
    queue_as { EmbedSync.config.queue }
    queue_with_priority { EmbedSync.config.priority }

    # Rate limits, timeouts and provider outages: back off and try again (3s, 18s, 83s, 258s).
    retry_on ProviderError, wait: :polynomially_longer, attempts: 5

    # The record was deleted before the job ran; nothing to embed.
    discard_on ActiveJob::DeserializationError

    def perform(record, column)
      Sync.call([record], column)
    end

    # With Solid Queue, caps how many EmbedJobs run at once across all workers, so a large import can't
    # exceed the provider's rate limit. Called at boot when config.concurrency_limit is set.
    def self.apply_concurrency_limit(limit)
      unless respond_to?(:limits_concurrency)
        raise ConfigurationError, "config.concurrency_limit needs Solid Queue (limits_concurrency)"
      end

      limits_concurrency(to: limit, key: ->(*) { "embed_sync" }, duration: 15 * 60)
    end
  end
end
