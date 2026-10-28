# frozen_string_literal: true

RSpec.describe EmbedSync::Backfill do
  before { EmbedSync.config.default_model = "test-model" }

  def create_products(count)
    EmbedSync.without_sync { Array.new(count) { |i| Product.create!(name: "Product #{i}") } }
  end

  describe ".run" do
    it "embeds all stale records with one provider call per batch" do
      create_products(25)

      expect(EmbedSync.backfill(Product, batch_size: 10)).to eq(25)
      expect(EmbedSync.provider.calls.map { |call| call[:texts].size }).to eq([10, 10, 5])
      expect(Product.embedding_missing.count).to eq(0)
    end

    it "is resumable: a second run makes no provider calls" do
      create_products(5)
      EmbedSync.backfill(Product)
      EmbedSync.provider.calls.clear

      expect(EmbedSync.backfill(Product)).to eq(0)
      expect(EmbedSync.provider.calls).to be_empty
    end

    it "re-embeds everything with force: true" do
      create_products(3)
      EmbedSync.backfill(Product)

      expect(EmbedSync.backfill(Product, force: true)).to eq(3)
    end

    it "accepts a relation" do
      create_products(3)
      EmbedSync.without_sync { Product.create!(name: "Special") }

      expect(EmbedSync.backfill(Product.where(name: "Special"))).to eq(1)
    end

    it "yields the running total" do
      create_products(5)
      totals = []
      EmbedSync.backfill(Product, batch_size: 2) { |total| totals << total }

      expect(totals).to eq([2, 4, 5])
    end

    it "requires column: when a model has several embeddings" do
      klass = stub_const("Gadget", Class.new(Product) { has_embedding :title_embedding, from: :name })

      expect { EmbedSync.backfill(klass) }.to raise_error(ArgumentError, /pass column:/)
      expect(EmbedSync.backfill(klass, column: :title_embedding)).to eq(0)
    end
  end

  describe ".report" do
    it "counts missing and stale records" do
      products = create_products(4)
      EmbedSync.backfill(Product)
      products.first.update_columns(name: "Renamed")
      EmbedSync.without_sync { Product.create!(name: "New") }

      expect(EmbedSync.stale_report(Product)).to eq(total: 5, missing: 1, stale: 2)
    end
  end
end
