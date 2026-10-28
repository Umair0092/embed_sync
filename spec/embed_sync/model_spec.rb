# frozen_string_literal: true

RSpec.describe EmbedSync::Model do
  def store_digest(record)
    definition = record.class.embed_sync_definition(:embedding)
    record.update_columns(embedding: [0.1], embedding_digest: definition.digest(record.embedding_source_text))
  end

  it "registers the definition on the model" do
    definition = Product.embed_sync_definition(:embedding)

    expect(definition.column).to eq(:embedding)
    expect(definition.digest_column).to eq(:embedding_digest)
    expect(definition.model_name).to eq("test-model")
  end

  it "raises for an undeclared column" do
    expect { Product.embed_sync_definition(:nope) }.to raise_error(ArgumentError, /no has_embedding for :nope/)
  end

  describe "#embedding_source_text" do
    it "joins attribute values with newlines, skipping blanks" do
      expect(Product.new(name: "Shoe", description: "Red").embedding_source_text).to eq("Shoe\nRed")
      expect(Product.new(name: "Shoe", description: "").embedding_source_text).to eq("Shoe")
    end

    it "evaluates a proc in the record's context" do
      klass = Class.new(Product) { has_embedding :title_embedding, from: -> { "#{name} in #{category&.name}" } }
      record = klass.new(name: "Shoe", category: Category.new(name: "Footwear"))

      expect(record.title_embedding_source_text).to eq("Shoe in Footwear")
    end

    it "accepts a single attribute name" do
      klass = Class.new(Product) { has_embedding :title_embedding, from: :name }

      expect(klass.new(name: "Shoe").title_embedding_source_text).to eq("Shoe")
    end
  end

  describe "#embedding_stale?" do
    it "is stale when nothing has been embedded yet" do
      expect(Product.create!(name: "Shoe")).to be_embedding_stale
    end

    it "is fresh when the stored digest matches the current text" do
      product = Product.create!(name: "Shoe")
      store_digest(product)

      expect(product).not_to be_embedding_stale
    end

    it "becomes stale when a source attribute changes" do
      product = Product.create!(name: "Shoe")
      store_digest(product)
      product.description = "Now with laces"

      expect(product).to be_embedding_stale
    end

    it "is stale when the digest matches but the vector is missing" do
      product = Product.create!(name: "Shoe")
      store_digest(product)
      product.update_columns(embedding: nil)

      expect(product).to be_embedding_stale
    end

    it "is fresh for blank text once its digest is stored, even without a vector" do
      product = Product.create!
      product.update_columns(embedding_digest: Product.embed_sync_definition(:embedding).digest(""))

      expect(product).not_to be_embedding_stale
    end
  end

  it "keeps definitions separate between subclasses and parents" do
    Class.new(Product) { has_embedding :title_embedding, from: :name }

    expect(Product.embed_sync_definitions.keys).to eq([:embedding])
  end

  it "rejects an invalid from:" do
    expect { Class.new(Product) { has_embedding :title_embedding, from: [] } }
      .to raise_error(ArgumentError, /from:/)
  end

  it "falls back to the configured default model" do
    EmbedSync.config.default_model = "default-model"
    klass = Class.new(Product) { has_embedding :title_embedding, from: :name }

    expect(klass.embed_sync_definition(:title_embedding).model_name).to eq("default-model")
  end

  it "raises when no model is available" do
    klass = Class.new(Product) { has_embedding :title_embedding, from: :name }

    expect { klass.embed_sync_definition(:title_embedding).model_name }
      .to raise_error(EmbedSync::ConfigurationError, /No embedding model/)
  end
end
