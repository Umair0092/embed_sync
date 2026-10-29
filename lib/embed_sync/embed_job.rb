# frozen_string_literal: true

require "active_job"

module EmbedSync
  # Regenerates one record's embedding in the background.
  class EmbedJob < ActiveJob::Base
    queue_as { EmbedSync.config.queue }

    # The record was deleted before the job ran; nothing to embed.
    discard_on ActiveJob::DeserializationError

    def perform(record, column)
      Sync.call([record], column)
    end
  end
end
