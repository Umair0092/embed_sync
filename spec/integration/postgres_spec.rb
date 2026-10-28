# frozen_string_literal: true

# Runs against a real PostgreSQL with pgvector when DATABASE_URL is set, e.g.
#   docker run -d -p 54329:5432 -e POSTGRES_PASSWORD=postgres pgvector/pgvector:pg17
#   DATABASE_URL=postgres://postgres:postgres@localhost:54329/postgres bundle exec rspec spec/integration
if ENV["DATABASE_URL"]
  require "neighbor"
  require "tmpdir"
  require "rails/generators"
  require "generators/embed_sync/embed_sync_generator"

  class IntegrationRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  class Article < IntegrationRecord
    has_neighbors :embedding
    has_embedding :embedding, from: :body, model: "fake-model", dimensions: 8, sync: :inline
  end

  RSpec.describe "PostgreSQL + pgvector integration" do
    before(:all) do
      IntegrationRecord.establish_connection(ENV.fetch("DATABASE_URL"))
      connection = IntegrationRecord.connection
      connection.create_table(:articles, force: true) { |t| t.text :body }

      # Build the schema with the migration our generator writes, so the generator is tested for real.
      Dir.mktmpdir do |dir|
        EmbedSync::Generators::EmbedSyncGenerator.start(%w[Article body --dimensions=8 --quiet], destination_root: dir)
        load Dir["#{dir}/db/migrate/*.rb"].first
        AddEmbeddingToArticles.new.exec_migration(connection, :up)
      end
      Article.reset_column_information
    end

    before do
      EmbedSync.config.provider_options = { dimensions: 8 }
      Article.delete_all
    end

    it "creates a vector column with dimensions and an HNSW index" do
      column = Article.columns_hash["embedding"]
      index = IntegrationRecord.connection.indexes(:articles).find { |i| i.columns == ["embedding"] }

      expect(column.sql_type).to eq("vector(8)")
      expect(index.using).to eq(:hnsw)
    end

    it "stores vectors on save and finds the closest record" do
      Article.create!(body: "Ruby on Rails")
      Article.create!(body: "Gardening tips")
      target = Article.create!(body: "Vector search in Postgres")

      expect(target.reload.embedding.size).to eq(8)
      expect(target).not_to be_embedding_stale

      result = Article.semantic_search("Vector search in Postgres", limit: 2).to_a
      expect(result.first).to eq(target)
      expect(result.first.neighbor_distance).to be_within(1e-6).of(0)
    end

    it "keeps relation conditions when searching" do
      Article.create!(body: "Vector search in Postgres")
      other = Article.create!(body: "Ruby on Rails")

      expect(Article.where(id: other.id).semantic_search("Vector search in Postgres").to_a).to eq([other])
    end

    it "backfills and reports in batches" do
      EmbedSync.without_sync { Array.new(5) { |i| Article.create!(body: "Article #{i}") } }

      expect(EmbedSync.stale_report(Article)).to eq(total: 5, missing: 5, stale: 5)
      expect(EmbedSync.backfill(Article, batch_size: 2)).to eq(5)
      expect(EmbedSync.stale_report(Article)).to eq(total: 5, missing: 0, stale: 0)
    end
  end
end
