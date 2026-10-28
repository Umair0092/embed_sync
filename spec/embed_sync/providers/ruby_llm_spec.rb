# frozen_string_literal: true

RSpec.describe "EmbedSync::Providers::RubyLLM" do
  # A stand-in for the ruby_llm gem with the same embed API, so specs never hit the network.
  let(:ruby_llm) do
    Module.new do
      const_set(:Error, Class.new(StandardError))
      const_set(:Embedding, Struct.new(:vectors))
      class << self
        attr_accessor :last_call

        def embed(text, **options)
          self.last_call = { text: text, **options }
          vectors = Array(text).map { |t| [t.size.to_f, 1.0] }
          const_get(:Embedding).new(text.is_a?(Array) ? vectors : vectors.first)
        end
      end
    end
  end

  before { stub_const("RubyLLM", ruby_llm) }

  let(:provider) { EmbedSync::Providers.build(:ruby_llm, dimensions: 2, provider: :openai) }

  it "embeds a batch in one call, passing the model and options" do
    vectors = provider.embed(%w[a bb], model: "text-embedding-3-small")

    expect(vectors).to eq([[1.0, 1.0], [2.0, 1.0]])
    expect(RubyLLM.last_call).to eq(text: %w[a bb], model: "text-embedding-3-small", dimensions: 2, provider: :openai)
  end

  it "wraps a single flat vector into a list" do
    allow(RubyLLM).to receive(:embed).and_return(RubyLLM::Embedding.new([0.5, 0.5]))

    expect(provider.embed(["a"], model: "m")).to eq([[0.5, 0.5]])
  end

  it "turns ruby_llm errors into EmbedSync::ProviderError" do
    allow(RubyLLM).to receive(:embed).and_raise(RubyLLM::Error, "rate limited")

    expect { provider.embed(["a"], model: "m") }.to raise_error(EmbedSync::ProviderError, /rate limited/)
  end

  it "rejects unknown options" do
    expect { EmbedSync::Providers.build(:ruby_llm, temperature: 1) }
      .to raise_error(EmbedSync::ConfigurationError, /Unknown ruby_llm provider options: temperature/)
  end

  it "is the default provider" do
    expect(EmbedSync::Configuration.new.resolved_provider).to be_a(EmbedSync::Providers::RubyLLM)
  end

  it "explains how to install ruby_llm when it is missing" do
    hide_const("RubyLLM")

    expect { EmbedSync::Providers.build(:ruby_llm) }
      .to raise_error(EmbedSync::ConfigurationError, /Add gem "ruby_llm"/)
  end
end

RSpec.describe "has_embedding dimensions:" do
  before { EmbedSync.config.provider_options = { dimensions: 8 } }

  it "raises when the provider returns vectors of the wrong size" do
    klass = Class.new(Product) { has_embedding :title_embedding, from: :name, model: "m", dimensions: 3 }
    record = EmbedSync.without_sync { klass.create!(name: "Shoe") }

    expect { EmbedSync::Sync.call([record], :title_embedding) }
      .to raise_error(EmbedSync::ProviderError, /expects 3 dimensions, but m returned 8/)
  end
end
