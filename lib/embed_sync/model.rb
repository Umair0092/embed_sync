# frozen_string_literal: true

module EmbedSync
  # Adds the has_embedding macro to ActiveRecord models.
  module Model
    extend ActiveSupport::Concern

    included do
      class_attribute :embed_sync_definitions, instance_writer: false, default: {}
    end

    class_methods do
      # has_embedding :embedding, from: %i[name description]
      # has_embedding :embedding, from: -> { "#{name}\n#{category&.name}" }, model: "text-embedding-3-small"
      def has_embedding(column = :embedding, from:, model: nil, digest_column: nil) # rubocop:disable Naming/PredicatePrefix
        definition = Definition.new(column: column, from: from, model: model, digest_column: digest_column)
        self.embed_sync_definitions = embed_sync_definitions.merge(definition.column => definition)

        define_method(:"#{definition.column}_source_text") { definition.source_text(self) }
        define_method(:"#{definition.column}_stale?") { definition.stale?(self) }

        definition
      end

      def embed_sync_definition(column)
        embed_sync_definitions.fetch(column.to_sym) do
          raise ArgumentError, "#{name} has no has_embedding for #{column.inspect}"
        end
      end
    end
  end
end
