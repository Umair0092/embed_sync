# frozen_string_literal: true

module EmbedSync
  # Embeds a batch of records for one has_embedding column with a single provider call.
  module Sync
    module_function

    # Returns the number of records written. Fresh records are skipped unless force: true.
    # Records with blank source text get a nil vector without calling the provider.
    def call(records, column, force: false)
      return 0 if records.empty?

      definition = records.first.class.embed_sync_definition(column)
      pending = pending_records(records, definition, force)
      return 0 if pending.empty?

      vectors = embed_texts(pending.map(&:last).select(&:present?), definition).each
      pending.each do |record, text|
        vector = text.present? ? vectors.next : nil
        record.update_columns(definition.column => vector, definition.digest_column => definition.digest(text))
      end
      pending.size
    end

    def pending_records(records, definition, force)
      records.filter_map do |record|
        [record, definition.source_text(record)] if force || definition.stale?(record)
      end
    end

    def embed_texts(texts, definition)
      return [] if texts.empty?

      vectors = instrument(texts, definition) { EmbedSync.provider.embed(texts, model: definition.model_name) }
      unless vectors.is_a?(Array) && vectors.size == texts.size
        raise ProviderError, "Expected #{texts.size} vectors from the provider, got #{vectors.try(:size).inspect}"
      end

      check_dimensions!(vectors, definition)

      vectors
    end

    def check_dimensions!(vectors, definition)
      return unless definition.dimensions

      wrong = vectors.find { |vector| vector.size != definition.dimensions }
      return unless wrong

      raise DimensionMismatchError, "#{definition.column} expects #{definition.dimensions} dimensions, " \
                                    "but #{definition.model_name} returned #{wrong.size}"
    end

    # Publishes "embed.embed_sync" with record_class, column, model and count (and exception, if raised).
    def instrument(texts, definition, &)
      payload = { record_class: definition.owner&.name, column: definition.column,
                  model: definition.model_name, count: texts.size }
      ActiveSupport::Notifications.instrument("embed.embed_sync", payload, &)
    end
  end
end
