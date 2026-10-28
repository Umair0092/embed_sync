# frozen_string_literal: true

require "rake"

RSpec.describe "embed_sync rake tasks" do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path("../../lib/embed_sync/tasks/embed_sync.rake", __dir__)
  end

  before { EmbedSync.config.default_model = "test-model" }
  after { Rake::Task.tasks.each(&:reenable) }

  it "backfills a model" do
    EmbedSync.without_sync { Product.create!(name: "Shoe") }

    expect { Rake::Task["embed_sync:backfill"].invoke("Product") }
      .to output(/Product#embedding: embedded 1 records/).to_stdout
    expect(Product.embedding_missing.count).to eq(0)
  end

  it "reports stale records" do
    EmbedSync.without_sync { Product.create!(name: "Shoe") }

    expect { Rake::Task["embed_sync:stale"].invoke("Product", "embedding") }
      .to output("Product#embedding: 1 total, 1 never embedded, 1 stale\n").to_stdout
  end
end
