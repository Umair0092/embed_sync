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

    class_methods do
      # has_embedding :embedding, from: %i[name description]
      # has_embedding :embedding, from: -> { "#{name}\n#{category&.name}" }, model: "text-embedding-3-small",
      #               dimensions: 1536, sync: :inline, if: :published?
      #
      # Options: model:, dimensions:, digest_column:, sync: (:async, :inline, false), if:, unless:
      def has_embedding(column = :embedding, from:, **options) # rubocop:disable Naming/PredicatePrefix
        unknown = options.keys - OPTIONS
        raise ArgumentError, "Unknown has_embedding options: #{unknown.join(", ")}" if unknown.any?

        callback_options = options.slice(*CALLBACK_OPTIONS)
        definition = Definition.new(column: column, from: from, **options.except(*CALLBACK_OPTIONS))
        self.embed_sync_definitions = embed_sync_definitions.merge(definition.column => definition)
        define_embedding_methods(definition)
        after_commit(on: %i[create update], **callback_options) { EmbedSync.sync_record(self, definition.column) }

        definition
      end

      def embed_sync_definition(column)
        embed_sync_definitions.fetch(column.to_sym) do
          raise ArgumentError, "#{name} has no has_embedding for #{column.inspect}"
        end
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
