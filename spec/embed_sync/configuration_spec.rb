# frozen_string_literal: true

RSpec.describe EmbedSync::Configuration do
  it "has sensible defaults" do
    config = described_class.new

    expect(config.provider).to eq(:ruby_llm)
    expect(config.queue).to eq(:default)
    expect(config.batch_size).to eq(100)
    expect(config.sync).to eq(:async)
  end

  it "validates the sync mode" do
    expect { described_class.new.sync = :later }.to raise_error(EmbedSync::ConfigurationError, /sync must be/)
  end

  describe "EmbedSync.configure" do
    it "yields the global configuration" do
      EmbedSync.configure do |c|
        c.provider = :fake
        c.default_model = "test-model"
      end

      expect(EmbedSync.config.default_model).to eq("test-model")
      expect(EmbedSync.provider).to be_a(EmbedSync::Providers::Fake)
    end
  end

  describe "#resolved_provider" do
    it "raises when no provider is configured" do
      EmbedSync.config.provider = nil

      expect { EmbedSync.provider }.to raise_error(EmbedSync::ConfigurationError, /No embedding provider/)
    end

    it "builds a registered provider with options" do
      EmbedSync.configure do |c|
        c.provider = :fake
        c.provider_options = { dimensions: 3 }
      end

      expect(EmbedSync.provider.dimensions).to eq(3)
    end

    it "memoizes the provider until the setting changes" do
      EmbedSync.config.provider = :fake
      first = EmbedSync.provider

      expect(EmbedSync.provider).to be(first)

      EmbedSync.config.provider = :fake
      expect(EmbedSync.provider).not_to be(first)
    end

    it "accepts any object that responds to #embed" do
      custom = Object.new
      def custom.embed(texts, **) = texts.map { [0.0] }
      EmbedSync.config.provider = custom

      expect(EmbedSync.provider).to be(custom)
    end

    it "rejects objects that cannot embed" do
      EmbedSync.config.provider = Object.new

      expect { EmbedSync.provider }.to raise_error(EmbedSync::ConfigurationError, /does not respond to #embed/)
    end

    it "rejects unknown provider names" do
      EmbedSync.config.provider = :nope

      expect { EmbedSync.provider }.to raise_error(EmbedSync::ConfigurationError, /Unknown provider :nope/)
    end
  end
end
