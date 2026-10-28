# frozen_string_literal: true

require "active_support/log_subscriber"

module EmbedSync
  # Logs each provider call, e.g.
  #   EmbedSync (182.4ms) embedded 100 Product#embedding texts with text-embedding-3-small
  class LogSubscriber < ActiveSupport::LogSubscriber
    def embed(event)
      payload = event.payload
      prefix = "EmbedSync (#{event.duration.round(1)}ms)"
      target = [payload[:record_class], payload[:column]].compact.join("#")
      if payload[:exception]
        error { "#{prefix} failed to embed #{target}: #{payload[:exception].join(": ")}" }
      else
        info { "#{prefix} embedded #{payload[:count]} #{target} texts with #{payload[:model]}" }
      end
    end
  end
end

EmbedSync::LogSubscriber.attach_to :embed_sync
