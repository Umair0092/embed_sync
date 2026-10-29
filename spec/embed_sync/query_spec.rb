# frozen_string_literal: true

require "active_support/cache"

RSpec.describe "Query helpers" do
  describe ".embed_query" do
    it "embeds the text with the column's model" do
      vector = Product.embed_query("red shoes")

      expect(vector).to eq(EmbedSync::Providers::Fake.new.embed(["red shoes"], model: "test-model").first)
      expect(EmbedSync.provider.calls).to eq([{ texts: ["red shoes"], model: "test-model" }])
    end

    it "rejects blank queries" do
      expect { Product.embed_query(" ") }.to raise_error(ArgumentError, /can't be blank/)
    end

    it "caches query vectors when a cache store is configured" do
      EmbedSync.config.query_cache = ActiveSupport::Cache::MemoryStore.new
      2.times { Product.embed_query("red shoes") }

      expect(EmbedSync.provider.calls.size).to eq(1)
    end
  end

  describe ".semantic_search" do
    # neighbor's nearest_neighbors, recorded instead of querying pgvector.
    let(:searchable) do
      stub_const("SearchableProduct", Class.new(Product) do
        class << self
          attr_accessor :neighbor_args

          def nearest_neighbors(*args, **kwargs)
            self.neighbor_args = [args, kwargs]
            all
          end
        end
      end)
    end

    it "passes the query vector to nearest_neighbors and limits the results" do
      relation = searchable.semantic_search("red shoes", limit: 3, distance: "euclidean")
      args, kwargs = searchable.neighbor_args

      expect(args).to eq([:embedding, Product.embed_query("red shoes")])
      expect(kwargs).to eq(distance: "euclidean")
      expect(relation.limit_value).to eq(3)
    end

    it "explains that neighbor is required" do
      expect { Product.semantic_search("red shoes") }.to raise_error(EmbedSync::ConfigurationError, /neighbor gem/)
    end
  end
end
