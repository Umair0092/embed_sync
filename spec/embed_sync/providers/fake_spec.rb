# frozen_string_literal: true

RSpec.describe EmbedSync::Providers::Fake do
  subject(:provider) { described_class.new(dimensions: 4) }

  it "returns one vector per text with the configured dimensions" do
    vectors = provider.embed(%w[a b c], model: "m")

    expect(vectors.size).to eq(3)
    expect(vectors).to all(have_attributes(size: 4))
  end

  it "is deterministic for the same text and model" do
    expect(provider.embed(["hello"], model: "m")).to eq(provider.embed(["hello"], model: "m"))
  end

  it "gives different vectors for different texts or models" do
    base = provider.embed(["hello"], model: "m").first

    expect(provider.embed(["world"], model: "m").first).not_to eq(base)
    expect(provider.embed(["hello"], model: "other").first).not_to eq(base)
  end

  it "returns unit-length vectors" do
    vector = provider.embed(["hello"], model: "m").first

    expect(Math.sqrt(vector.sum { |x| x * x })).to be_within(1e-9).of(1.0)
  end

  it "records calls" do
    provider.embed(%w[a b], model: "m")

    expect(provider.calls).to eq([{ texts: %w[a b], model: "m" }])
  end
end

RSpec.describe EmbedSync::Providers::Base do
  it "requires subclasses to implement #embed" do
    expect { described_class.new.embed(["x"], model: "m") }.to raise_error(NotImplementedError)
  end
end
