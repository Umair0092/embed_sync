# frozen_string_literal: true

module EmbedSync
  # Batch operations over whole tables: embed what's missing or out of date, and report on it.
  module Backfill
    module_function

    # Embeds every stale record in batches, one provider call per batch. Safe to re-run: records
    # embedded by an earlier (possibly interrupted) run are fresh and get skipped. Records the provider
    # rejects (e.g. text too long) are logged and left stale instead of stopping the backfill.
    # Accepts a model or a relation, e.g. Product.includes(:category). Yields the running total.
    def run(scope, column: nil, batch_size: nil, force: false)
      relation = scope.all
      definition = relation.klass.embed_sync_definition(column)
      written = 0
      relation.find_in_batches(batch_size: batch_size || EmbedSync.config.batch_size) do |batch|
        written += Sync.call(batch, definition.column, force: force, skip_invalid: true)
        yield written if block_given?
      end
      written
    end

    # Returns { total:, missing:, stale: }. "missing" rows were never embedded; "stale" includes
    # them plus rows whose text changed since. Loads every record, so it can take a while.
    def report(scope, column: nil)
      relation = scope.all
      definition = relation.klass.embed_sync_definition(column)
      stale = 0
      relation.find_each { |record| stale += 1 if definition.stale?(record) }
      { total: relation.count, missing: relation.where(definition.digest_column => nil).count, stale: stale }
    end
  end
end
