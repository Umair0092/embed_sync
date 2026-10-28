# frozen_string_literal: true

RSpec.describe "Background sync" do
  let(:enqueued) { ActiveJob::Base.queue_adapter.enqueued_jobs }

  before { EmbedSync.config.default_model = "test-model" }

  # Subclasses inherit Product's async callback, and jobs need a class name to serialize the record.
  def product_subclass(&)
    stub_const("Gadget", Class.new(Product, &))
  end

  def perform_enqueued_jobs
    jobs = enqueued.dup
    enqueued.clear
    jobs.each { |job| ActiveJob::Base.execute(job) }
  end

  describe "after commit" do
    it "enqueues one EmbedJob when a record is created" do
      product = Product.create!(name: "Shoe")

      expect(enqueued.size).to eq(1)
      expect(enqueued.first[:job]).to eq(EmbedSync::EmbedJob)
      expect(enqueued.first[:queue]).to eq("default")
      expect(enqueued.first[:args]).to eq([{ "_aj_globalid" => product.to_global_id.to_s }, "embedding"])
    end

    it "stores the vector and digest when the job runs" do
      product = Product.create!(name: "Shoe")
      perform_enqueued_jobs
      product.reload

      expect(product.embedding.size).to eq(8)
      expect(product).not_to be_embedding_stale
    end

    it "does not enqueue when an unrelated attribute changes" do
      product = Product.create!(name: "Shoe")
      perform_enqueued_jobs
      product.reload.update!(published: false)

      expect(enqueued).to be_empty
    end

    it "enqueues again when a source attribute changes" do
      product = Product.create!(name: "Shoe")
      perform_enqueued_jobs
      product.reload.update!(description: "Waterproof")

      expect(enqueued.size).to eq(1)
    end

    it "uses the configured queue" do
      EmbedSync.config.queue = :embeddings
      Product.create!(name: "Shoe")

      expect(enqueued.first[:queue]).to eq("embeddings")
    end

    it "does nothing inside without_sync" do
      EmbedSync.without_sync { Product.create!(name: "Shoe") }

      expect(enqueued).to be_empty
      expect(EmbedSync.sync_enabled?).to be(true)
    end

    it "does nothing when the transaction rolls back" do
      Product.transaction do
        Product.create!(name: "Shoe")
        raise ActiveRecord::Rollback
      end

      expect(enqueued).to be_empty
    end
  end

  describe "sync modes" do
    it "embeds immediately with sync: :inline" do
      klass = product_subclass { has_embedding :title_embedding, from: :name, sync: :inline }
      product = klass.create!(name: "Shoe")

      expect(product.reload.title_embedding.size).to eq(8)
    end

    it "skips syncing with sync: false" do
      EmbedSync.config.sync = false
      product = Product.create!(name: "Shoe")

      expect(enqueued).to be_empty
      expect(product.reload.embedding).to be_nil
    end

    it "rejects unknown modes" do
      expect { Class.new(Product) { has_embedding :title_embedding, from: :name, sync: :later } }
        .to raise_error(ArgumentError, /sync:/)
    end
  end

  describe "if: / unless:" do
    it "only syncs records matching the condition" do
      klass = product_subclass { has_embedding :title_embedding, from: :name, sync: :inline, if: :published? }

      expect(klass.create!(name: "Draft", published: false).reload.title_embedding).to be_nil
      expect(klass.create!(name: "Live", published: true).reload.title_embedding).to be_present
    end

    it "rejects unknown options" do
      expect { Class.new(Product) { has_embedding :title_embedding, from: :name, on: :create } }
        .to raise_error(ArgumentError, /Unknown has_embedding options: on/)
    end
  end

  describe EmbedSync::EmbedJob do
    it "skips records that are already fresh (e.g. a duplicate job)" do
      product = Product.create!(name: "Shoe")
      perform_enqueued_jobs
      EmbedSync.provider.calls.clear

      described_class.perform_now(product.reload, "embedding")

      expect(EmbedSync.provider.calls).to be_empty
    end

    it "is discarded when the record was deleted" do
      product = Product.create!(name: "Shoe")
      product.delete

      expect { perform_enqueued_jobs }.not_to raise_error
    end
  end

  describe EmbedSync::Sync do
    it "embeds a batch with a single provider call" do
      products = EmbedSync.without_sync { Array.new(3) { |i| Product.create!(name: "P#{i}") } }

      expect(described_class.call(products, :embedding)).to eq(3)
      expect(EmbedSync.provider.calls.size).to eq(1)
      expect(EmbedSync.provider.calls.first[:texts]).to eq(%w[P0 P1 P2])
    end

    it "stores nil for blank text without calling the provider" do
      product = EmbedSync.without_sync { Product.create! }

      expect(described_class.call([product], :embedding)).to eq(1)
      expect(EmbedSync.provider.calls).to be_empty
      expect(product.reload).not_to be_embedding_stale
    end

    it "raises when the provider returns the wrong number of vectors" do
      bad = Object.new
      def bad.embed(*, **) = []
      EmbedSync.config.provider = bad
      product = EmbedSync.without_sync { Product.create!(name: "Shoe") }

      expect { described_class.call([product], :embedding) }
        .to raise_error(EmbedSync::ProviderError, /Expected 1 vectors/)
    end

    it "re-embeds fresh records with refresh_<column>!" do
      product = Product.create!(name: "Shoe")
      perform_enqueued_jobs
      EmbedSync.provider.calls.clear

      product.reload.refresh_embedding!

      expect(EmbedSync.provider.calls.size).to eq(1)
    end
  end
end
