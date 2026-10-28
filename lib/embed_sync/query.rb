# frozen_string_literal: true

module EmbedSync
  # Embeds search queries, optionally caching them (config.query_cache = Rails.cache).
  module Query
    module_function

    def embed(text, definition)
      raise ArgumentError, "Search query can't be blank" if text.blank?

      cache = EmbedSync.config.query_cache
      return embed_now(text, definition) unless cache

      cache.fetch(cache_key(text, definition), expires_in: EmbedSync.config.query_cache_expires_in) do
        embed_now(text, definition)
      end
    end

    def embed_now(text, definition)
      Sync.embed_texts([text.to_s], definition).first
    end

    def cache_key(text, definition)
      "embed_sync/query/#{definition.model_name}/#{definition.dimensions}/#{Digest::SHA256.hexdigest(text.to_s)}"
    end
  end
end
