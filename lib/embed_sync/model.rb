# frozen_string_literal: true

module EmbedSync
  # Adds the has_embedding macro to ActiveRecord models.
  module Model
    extend ActiveSupport::Concern

    CALLBACK_OPTIONS = %i[if unless].freeze
    OPTIONS = (CALLBACK_OPTIONS + %i[model dimensions digest_column sync]).freeze

    included do
      class_attribute :embed_sync_definitions, instance_writer: false, default: {}
    end

    # True when the last save happened inside EmbedSync.without_sync. Captured at save time because
    # after_commit runs later, after a surrounding transaction (and the without_sync block) has ended.
    def embed_sync_skipped?
      @embed_sync_skipped == true
    end

    private

    def embed_sync_capture_sync_state
      @embed_sync_skipped = !EmbedSync.sync_enabled?
    end

    # Class methods added to every model (Concern extends the model with ClassMethods).
    module ClassMethods
      # has_embedding :embedding, from: %i[name description]
      # has_embedding :embedding, from: -> { "#{name}\n#{category&.name}" }, model: "text-embedding-3-small",
      #               dimensions: 1536, sync: :inline, if: :published?
      #
      # Options: model:, dimensions:, digest_column:, sync: (:async, :inline, false), if:, unless:
      def has_embedding(column = :embedding, from:, **options) # rubocop:disable Naming/PredicatePrefix
        unknown = options.keys - OPTIONS
        raise ArgumentError, "Unknown has_embedding options: #{unknown.join(", ")}" if unknown.any?

        callback_options = options.slice(*CALLBACK_OPTIONS)
        definition = Definition.new(column: column, from: from, owner: self, **options.except(*CALLBACK_OPTIONS))
        self.embed_sync_definitions = embed_sync_definitions.merge(definition.column => definition)
        define_embedding_methods(definition)
        after_save :embed_sync_capture_sync_state
        after_commit(on: %i[create update], **callback_options) { EmbedSync.sync_record(self, definition.column) }

        definition
      end

      # Looks up a has_embedding by column; the column can be omitted when the model has only one.
      def embed_sync_definition(column = nil)
        if column
          return embed_sync_definitions.fetch(column.to_sym) do
            raise ArgumentError, "#{name} has no has_embedding for #{column.inspect}"
          end
        end

        definitions = embed_sync_definitions.values
        return definitions.first if definitions.one?

        raise ArgumentError, "#{name} has #{definitions.size} embeddings; pass column: " \
                             "(one of #{definitions.map(&:column).join(", ")})"
      end

      # Embeds a search query with the same model as the column, so it can be compared to stored vectors.
      def embed_query(text, column: nil)
        EmbedSync::Query.embed(text, embed_sync_definition(column))
      end

      # Product.semantic_search("red running shoes", limit: 5)
      # Product.where(published: true).semantic_search("waterproof", column: :embedding, distance: "euclidean")
      # Needs the neighbor gem (has_neighbors :embedding). Records respond to #neighbor_distance.
      def semantic_search(query, column: nil, limit: 10, distance: "cosine")
        definition = embed_sync_definition(column)
        unless respond_to?(:nearest_neighbors)
          raise ConfigurationError, "semantic_search needs the neighbor gem. Add gem \"neighbor\" and " \
                                    "has_neighbors :#{definition.column} to #{name}."
        end

        nearest_neighbors(definition.column, embed_query(query, column: definition.column), distance: distance)
          .limit(limit)
      end

      private

      def define_embedding_methods(definition)
        column = definition.column
        define_method(:"#{column}_source_text") { definition.source_text(self) }
        define_method(:"#{column}_stale?") { definition.stale?(self) }
        define_method(:"refresh_#{column}!") { Sync.call([self], column, force: true) }
        scope :"#{column}_missing", -> { where(definition.digest_column => nil) }
      end
    end
  end
end
