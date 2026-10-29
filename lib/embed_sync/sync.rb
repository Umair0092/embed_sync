# frozen_string_literal: true

module EmbedSync
  # Embeds a batch of records for one has_embedding column with a single provider call.
  module Sync
    module_function

    # Returns the number of records written. Fresh records are skipped unless force: true.
    # Records with blank source text get a nil vector without calling the provider.
    # skip_invalid: records the provider rejects (e.g. text too long) are left stale instead of raising.
    # recheck: before writing, reload the record under a row lock and skip it if its text changed while the
    # provider was working (the save that changed it queues its own embedding).
    def call(records, column, force: false, skip_invalid: false, recheck: false)
      return 0 if records.empty?

      definition = records.first.class.embed_sync_definition(column)
      pending = pending_records(records, definition, force)
      return 0 if pending.empty?

      vectors = embed_pending(pending.map(&:last), definition, skip_invalid)
      pending.zip(vectors).count do |(record, text), vector|
        vector != :rejected && write(record, definition, text, vector, recheck)
      end
    end

    def pending_records(records, definition, force)
      records.filter_map do |record|
        [record, definition.source_text(record)] if force || definition.stale?(record)
      end
    end

    # One provider call for the whole batch. If the provider rejects it, embed the texts one at a time so
    # a single bad record doesn't block the others; the rejected ones come back as :rejected.
    def embed_pending(texts, definition, skip_invalid)
      embed_with_blanks(texts, definition)
    rescue InvalidRequestError
      raise unless skip_invalid
      return [:rejected] if texts.one?

      texts.map { |text| embed_pending([text], definition, skip_invalid).first }
    end

    # Blank texts get nil without being sent to the provider.
    def embed_with_blanks(texts, definition)
      vectors = embed_texts(texts.select(&:present?), definition).each
      texts.map { |text| text.present? ? vectors.next : nil }
    end

    def write(record, definition, text, vector, recheck)
      attributes = { definition.column => vector, definition.digest_column => definition.digest(text) }
      return record.update_columns(attributes) unless recheck

      record.with_lock do
        next false unless definition.source_text(record) == text

        record.update_columns(attributes)
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
