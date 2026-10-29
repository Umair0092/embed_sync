# frozen_string_literal: true

require "embed_sync/log_subscriber"

RSpec.describe "Production hardening" do
  before { EmbedSync.config.default_model = "test-model" }

  let(:failing_provider) do
    Class.new do
      def embed(*, **) = raise(EmbedSync::ProviderError, "429 Too Many Requests")
    end.new
  end

  describe "instrumentation" do
    it "publishes embed.embed_sync for each provider call" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("embed.embed_sync") { |event| events << event }
      products = EmbedSync.without_sync { Array.new(2) { |i| Product.create!(name: "P#{i}") } }
      EmbedSync::Sync.call(products, :embedding)

      expect(events.size).to eq(1)
      expect(events.first.payload).to eq(record_class: "Product", column: :embedding, model: "test-model", count: 2)
      expect(events.first.duration).to be >= 0
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "logs successful and failed calls" do
      io = StringIO.new
      ActiveSupport::LogSubscriber.logger = Logger.new(io)
      product = EmbedSync.without_sync { Product.create!(name: "Shoe") }
      EmbedSync::Sync.call([product], :embedding)
      EmbedSync.config.provider = failing_provider
      expect { product.refresh_embedding! }.to raise_error(EmbedSync::ProviderError)

      expect(io.string).to match(/EmbedSync \(\d+\.\dms\) embedded 1 Product#embedding texts with test-model/)
      expect(io.string).to include("failed to embed Product#embedding: EmbedSync::ProviderError: 429 Too Many Requests")
    ensure
      ActiveSupport::LogSubscriber.logger = nil
    end
  end

  describe EmbedSync::EmbedJob do
    let(:enqueued) { ActiveJob::Base.queue_adapter.enqueued_jobs }

    it "retries provider errors with backoff" do
      product = EmbedSync.without_sync { Product.create!(name: "Shoe") }
      EmbedSync.config.provider = failing_provider

      described_class.perform_now(product, "embedding")

      expect(enqueued.size).to eq(1)
      expect(enqueued.first[:job]).to eq(described_class)
      expect(enqueued.first[:at]).to be > Time.now.to_f
    end

    it "does not retry dimension mismatches" do
      klass = stub_const("Gadget", Class.new(Product) { has_embedding :title_embedding, from: :name, dimensions: 3 })
      product = EmbedSync.without_sync { klass.create!(name: "Shoe") }

      expect { described_class.perform_now(product, "title_embedding") }
        .to raise_error(EmbedSync::DimensionMismatchError)
      expect(enqueued).to be_empty
    end

    it "uses the configured priority" do
      EmbedSync.config.priority = 10
      Product.create!(name: "Shoe")

      expect(enqueued.first[:priority]).to eq(10)
    end

    describe ".apply_concurrency_limit" do
      it "uses Solid Queue's limits_concurrency" do
        job = Class.new(described_class)
        received = nil
        job.define_singleton_method(:limits_concurrency) { |**options| received = options }
        job.apply_concurrency_limit(2)

        expect(received).to include(to: 2, duration: 900)
        expect(received[:key].call).to eq("embed_sync")
      end

      it "explains that Solid Queue is needed" do
        expect { Class.new(described_class).apply_concurrency_limit(2) }
          .to raise_error(EmbedSync::ConfigurationError, /Solid Queue/)
      end
    end
  end
end
