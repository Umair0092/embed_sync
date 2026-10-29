# frozen_string_literal: true

require "rake"

RSpec.describe "Edge cases found in a real app" do
  before { EmbedSync.config.default_model = "test-model" }

  # Rejects any text containing "TOO LONG", like a model with an input limit.
  let(:picky_provider) do
    fake = EmbedSync::Providers::Fake.new
    Class.new do
      define_method(:calls) { fake.calls }
      define_method(:embed) do |texts, model:|
        raise EmbedSync::InvalidRequestError, "input length exceeds the context length" if texts.any?(/TOO LONG/)

        fake.embed(texts, model: model)
      end
    end.new
  end

  describe "texts the provider rejects" do
    before { EmbedSync.config.provider = picky_provider }

    it "backfill skips the rejected record and embeds the rest of the batch" do
      EmbedSync.without_sync do
        Product.create!(name: "Shoe")
        Product.create!(name: "TOO LONG")
        Product.create!(name: "Sock")
      end

      expect(EmbedSync.backfill(Product)).to eq(2)
      expect(Product.where.not(embedding_digest: nil).pluck(:name)).to contain_exactly("Shoe", "Sock")
      expect(EmbedSync.stale_report(Product)).to include(stale: 1)
    end

    it "backfill keeps going when a batch has only the rejected record" do
      EmbedSync.without_sync { Product.create!(name: "TOO LONG") }

      expect(EmbedSync.backfill(Product, batch_size: 1)).to eq(0)
    end

    it "refresh_embedding! still raises so the caller sees the problem" do
      product = EmbedSync.without_sync { Product.create!(name: "TOO LONG") }

      expect { product.refresh_embedding! }.to raise_error(EmbedSync::InvalidRequestError)
    end

    it "is not retried by the job" do
      expect(EmbedSync::InvalidRequestError).not_to be < EmbedSync::ProviderError
      product = EmbedSync.without_sync { Product.create!(name: "TOO LONG") }

      expect { EmbedSync::EmbedJob.perform_now(product, "embedding") }.not_to raise_error
      expect(product.reload.embedding_digest).to be_nil
    end
  end

  describe "sync: :inline" do
    before { EmbedSync.config.sync = :inline }

    it "doesn't raise from save when the provider fails after the row is committed" do
      EmbedSync.config.provider = Class.new { def embed(*, **) = raise(EmbedSync::ProviderError, "503") }.new

      product = nil
      expect { product = Product.create!(name: "Shoe") }.not_to raise_error
      expect(product).to be_persisted
      expect(product.reload).to be_embedding_stale
    end
  end

  describe "a record edited while its embedding is generated" do
    it "doesn't overwrite the newer text's embedding with the older one" do
      product = EmbedSync.without_sync { Product.create!(name: "v1") }
      fake = EmbedSync::Providers::Fake.new
      EmbedSync.config.provider = Class.new do
        define_method(:embed) do |texts, model:|
          # Someone saves new text while this request is in flight.
          Product.where(id: product.id).update_all(name: "v2")
          fake.embed(texts, model: model)
        end
      end.new

      EmbedSync::EmbedJob.perform_now(product, "embedding")

      expect(product.reload.embedding_digest).to be_nil
      expect(product).to be_embedding_stale
    end
  end

  describe "EmbedSync.without_sync inside a transaction" do
    it "skips records saved in the block even though after_commit runs after it" do
      EmbedSync.config.sync = :inline
      Product.transaction { EmbedSync.without_sync { Product.create!(name: "Imported") } }

      expect(EmbedSync.provider.calls).to be_empty
      expect(Product.last.embedding_digest).to be_nil
    end

    it "syncs later saves of the same record outside the block" do
      EmbedSync.config.sync = :inline
      product = Product.transaction { EmbedSync.without_sync { Product.create!(name: "Imported") } }
      product.update!(name: "Edited")

      expect(product.reload).not_to be_embedding_stale
    end
  end

  describe "provider_options[:dimensions]" do
    it "is part of the digest, so changing it marks records stale" do
      EmbedSync.config.provider_options = { dimensions: 8 }
      EmbedSync.config.sync = :inline
      product = Product.create!(name: "Shoe")
      expect(product.reload).not_to be_embedding_stale

      EmbedSync.config.provider_options = { dimensions: 4 }
      expect(product.reload).to be_embedding_stale
    end

    it "is part of the query cache key" do
      EmbedSync.config.query_cache = ActiveSupport::Cache::MemoryStore.new
      EmbedSync.config.provider_options = { dimensions: 8 }
      expect(Product.embed_query("shoe").size).to eq(8)

      EmbedSync.config.provider_options = { dimensions: 4 }
      expect(Product.embed_query("shoe").size).to eq(4)
    end

    it "is checked against the returned vectors" do
      EmbedSync.config.provider_options = { dimensions: 8 }
      definition = Product.embed_sync_definition
      expect { EmbedSync::Sync.check_dimensions!([[0.1]], definition) }.to raise_error(EmbedSync::DimensionMismatchError)
    end
  end

  describe "from: with a lambda that takes the record" do
    it "passes the record" do
      stub_const("Item", Class.new(ActiveRecord::Base) do
        self.table_name = "products"
        has_embedding :embedding, from: ->(item) { "#{item.name}!" }, sync: false
      end)

      expect(Item.new(name: "Shoe").embedding_source_text).to eq("Shoe!")
    end
  end

  describe "records loaded with select(...)" do
    it "still syncs after an update" do
      EmbedSync.config.sync = :inline
      id = EmbedSync.without_sync { Product.create!(name: "Shoe") }.id

      expect { Product.select(:id, :published).find(id).update!(published: false) }.not_to raise_error
      expect(Product.find(id)).not_to be_embedding_stale
    end
  end

  describe "rake tasks with single-table inheritance" do
    before(:all) do
      Rake.application = Rake::Application.new
      Rake::Task.define_task(:environment)
      load File.expand_path("../../lib/embed_sync/tasks/embed_sync.rake", __dir__)
    end

    after { Rake::Task.tasks.each(&:reenable) }

    it "visits an inherited embedding once, on the parent" do
      base = Class.new(ActiveRecord::Base) do
        self.table_name = "products"
        self.inheritance_column = "kind"
        has_embedding :embedding, from: :name, sync: false
      end
      stub_const("Listing", base)
      stub_const("Shoe", Class.new(Listing))
      allow(ActiveRecord::Base).to receive(:descendants).and_return([Listing, Shoe])
      Shoe.create!(name: "Boot")

      expect { Rake::Task["embed_sync:stale"].invoke }
        .to output("Listing#embedding: 1 total, 1 never embedded, 1 stale\n").to_stdout
    end

    it "skips models without the requested column when no model is given" do
      allow(ActiveRecord::Base).to receive(:descendants).and_return([Product])

      expect { Rake::Task["embed_sync:stale"].invoke(nil, "title_embedding") }.not_to raise_error
    end
  end
end
