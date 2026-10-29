# frozen_string_literal: true

require "rails/generators/named_base"
require "rails/generators/active_record"

module EmbedSync
  module Generators
    # rails g embed_sync Product name description [--column=embedding] [--dimensions=1536]
    class EmbedSyncGenerator < Rails::Generators::NamedBase
      include Rails::Generators::Migration

      OPCLASSES = { "cosine" => "vector_cosine_ops", "euclidean" => "vector_l2_ops",
                    "inner_product" => "vector_ip_ops" }.freeze

      namespace "embed_sync"
      source_root File.expand_path("templates", __dir__)
      desc "Adds an embedding column, digest column and vector index to a model (PostgreSQL + pgvector)"

      argument :source_attributes, type: :array, default: [], banner: "attribute attribute"

      class_option :column, type: :string, default: "embedding", desc: "Vector column name"
      class_option :dimensions, type: :numeric, default: 1536, desc: "Vector size of your embedding model"
      class_option :index, type: :string, default: "hnsw", enum: %w[hnsw ivfflat none], desc: "Vector index type"
      class_option :distance, type: :string, default: "cosine", enum: OPCLASSES.keys, desc: "Distance for the index"

      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def check_source_attributes
        return if source_attributes.any?

        raise Thor::Error, "Pass the attributes to embed, e.g. rails g embed_sync #{class_name} name description"
      end

      def create_migration_file
        migration_template "migration.rb.tt", "db/migrate/add_#{column}_to_#{table_name}.rb"
      end

      def add_has_embedding_to_model
        path = File.join("app/models", class_path, "#{file_name}.rb")
        unless File.exist?(File.join(destination_root, path))
          say_status :skip, "#{path} not found; add has_embedding to your model yourself", :yellow
          return
        end

        inject_into_class path, class_name.demodulize, model_lines
      end

      # Without neighbor, Rails doesn't know the vector type: it drops limit:, the index fails and
      # schema.rb can't dump the table.
      def warn_without_neighbor
        return if defined?(::Neighbor)

        say_status :warning, 'Add gem "neighbor" to your Gemfile before running this migration ' \
                             "(it teaches Rails the pgvector column type).", :yellow
      end

      private

      def column
        options[:column]
      end

      def index?
        options[:index] != "none"
      end

      def opclass
        OPCLASSES.fetch(options[:distance])
      end

      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      end

      def model_lines
        from = source_attributes.one? ? ":#{source_attributes.first}" : "%i[#{source_attributes.join(" ")}]"
        lines = []
        lines << "  has_neighbors :#{column}\n" if defined?(::Neighbor)
        lines << "  has_embedding :#{column}, from: #{from}\n"
        lines.join
      end
    end
  end
end
