# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "generators/embed_sync/install_generator"
require "generators/embed_sync/embed_sync_generator"

RSpec.describe "Generators" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  def run_generator(klass, args)
    klass.start(args + ["--quiet"], destination_root: @root)
  end

  def read(path)
    File.read(File.join(@root, path))
  end

  def migration_path
    Dir[File.join(@root, "db/migrate/*_add_embedding_to_products.rb")].first
  end

  describe EmbedSync::Generators::InstallGenerator do
    it "creates the initializer" do
      run_generator(described_class, [])

      expect(read("config/initializers/embed_sync.rb")).to include("EmbedSync.configure do |config|")
    end
  end

  describe EmbedSync::Generators::EmbedSyncGenerator do
    before do
      FileUtils.mkdir_p(File.join(@root, "app/models"))
      File.write(File.join(@root, "app/models/product.rb"), "class Product < ApplicationRecord\nend\n")
    end

    it "creates a pgvector migration with digest column and HNSW index" do
      run_generator(described_class, %w[Product name description --dimensions=3])
      migration = File.read(migration_path)

      expect(migration).to include("class AddEmbeddingToProducts < ActiveRecord::Migration[")
      expect(migration).to include('enable_extension "vector"')
      expect(migration).to include("add_column :products, :embedding, :vector, limit: 3")
      expect(migration).to include("add_column :products, :embedding_digest, :string")
      expect(migration).to include("add_index :products, :embedding, using: :hnsw, opclass: :vector_cosine_ops")
    end

    it "honors --column, --index and --distance" do
      run_generator(described_class, %w[Product name --column=title_embedding --index=ivfflat --distance=euclidean])
      migration = read(Dir.children(File.join(@root, "db/migrate")).map { |f| "db/migrate/#{f}" }.first)

      expect(migration).to include("add_column :products, :title_embedding, :vector, limit: 1536")
      expect(migration).to include("using: :ivfflat, opclass: :vector_l2_ops")
    end

    it "skips the index with --index=none" do
      run_generator(described_class, %w[Product name --index=none])

      expect(File.read(migration_path)).not_to include("add_index")
    end

    it "adds has_embedding to the model" do
      run_generator(described_class, %w[Product name description])

      expect(read("app/models/product.rb")).to include("  has_embedding :embedding, from: %i[name description]\n")
    end

    it "uses a symbol for a single attribute" do
      run_generator(described_class, %w[Product name])

      expect(read("app/models/product.rb")).to include("has_embedding :embedding, from: :name\n")
    end

    it "requires at least one attribute" do
      expect { run_generator(described_class, %w[Product]) }
        .to output(/Pass the attributes to embed/).to_stderr
      expect(migration_path).to be_nil
    end

    it "still creates the migration when the model file is missing" do
      FileUtils.rm(File.join(@root, "app/models/product.rb"))
      run_generator(described_class, %w[Product name])

      expect(migration_path).not_to be_nil
    end
  end
end
