# frozen_string_literal: true

RSpec.describe "Changing the embedding model" do
  def define_product(model:, dimensions: nil)
    stub_const("Item", Class.new(ActiveRecord::Base) do
      self.table_name = "products"
      has_embedding :embedding, from: :name, model: model, dimensions: dimensions, sync: false
    end)
  end

  it "marks every record stale and re-embeds them with the new model" do
    define_product(model: "small")
    EmbedSync.config.provider_options = { dimensions: 8 }
    Array.new(3) { |i| Item.create!(name: "Item #{i}") }
    Item.create!
    EmbedSync.backfill(Item)
    expect(EmbedSync.stale_report(Item)).to eq(total: 4, missing: 0, stale: 0)

    define_product(model: "large")
    expect(EmbedSync.stale_report(Item)).to eq(total: 4, missing: 0, stale: 4)

    EmbedSync.provider.calls.clear
    expect(EmbedSync.backfill(Item)).to eq(4)
    expect(EmbedSync.provider.calls).to eq([{ texts: ["Item 0", "Item 1", "Item 2"], model: "large" }])
    expect(EmbedSync.stale_report(Item)[:stale]).to eq(0)
  end

  it "marks records stale when dimensions: changes" do
    define_product(model: "small", dimensions: 8)
    Item.create!(name: "Shoe")
    EmbedSync.backfill(Item)

    define_product(model: "small", dimensions: 4)
    expect(Item.first).to be_embedding_stale
  end

  it "uses the configured default model in the digest" do
    EmbedSync.config.default_model = "v1"
    define_product(model: nil)
    Item.create!(name: "Shoe")
    EmbedSync.backfill(Item)

    EmbedSync.config.default_model = "v2"
    expect(Item.first).to be_embedding_stale
  end
end
