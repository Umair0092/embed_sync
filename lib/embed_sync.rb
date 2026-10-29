# frozen_string_literal: true

require "active_support"
require "active_support/lazy_load_hooks"
require "active_support/isolated_execution_state"

require_relative "embed_sync/version"
require_relative "embed_sync/errors"
require_relative "embed_sync/configuration"
require_relative "embed_sync/providers"
require_relative "embed_sync/definition"
require_relative "embed_sync/sync"
require_relative "embed_sync/backfill"
require_relative "embed_sync/query"

# Keeps vector embeddings in sync with ActiveRecord models.
module EmbedSync
  autoload :Model, "embed_sync/model"
  autoload :EmbedJob, "embed_sync/embed_job"

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

    # Turns off automatic syncing inside the block (e.g. bulk imports), on this thread only.
    def without_sync
      previous = ActiveSupport::IsolatedExecutionState[:embed_sync_disabled]
      ActiveSupport::IsolatedExecutionState[:embed_sync_disabled] = true
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[:embed_sync_disabled] = previous
    end

    def sync_enabled?
      !ActiveSupport::IsolatedExecutionState[:embed_sync_disabled]
    end

    # EmbedSync.backfill(Product) / EmbedSync.backfill(Product.includes(:category), column: :embedding)
    def backfill(scope, **, &)
      Backfill.run(scope, **, &)
    end

    def stale_report(scope, **)
      Backfill.report(scope, **)
    end

    # Called after commit: queues or runs the embedding when the record's text changed.
    def sync_record(record, column)
      return unless sync_enabled?

      definition = record.class.embed_sync_definition(column)
      return unless definition.stale?(record)

      case definition.sync_mode
      when :async then EmbedJob.perform_later(record, column.to_s)
      when :inline then Sync.call([record], column)
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  include EmbedSync::Model
end

require_relative "embed_sync/railtie" if defined?(Rails::Railtie)
