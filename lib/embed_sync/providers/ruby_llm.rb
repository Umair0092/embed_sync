# frozen_string_literal: true

module EmbedSync
  module Providers
    # Generates embeddings with the ruby_llm gem (OpenAI, Gemini, Voyage, Bedrock, Ollama, ...).
    # API keys are configured through RubyLLM.configure, not here.
    #
    #   EmbedSync.config.provider = :ruby_llm
    #   EmbedSync.config.provider_options = { dimensions: 512, provider: :openai }
    class RubyLLM < Base
      EMBED_OPTIONS = %i[dimensions provider assume_model_exists task_type provider_options].freeze

      def initialize(**options)
        super()
        unknown = options.keys - EMBED_OPTIONS
        raise ConfigurationError, "Unknown ruby_llm provider options: #{unknown.join(", ")}" if unknown.any?

        @options = options.compact
        load_ruby_llm
      end

      def embed(texts, model:)
        vectors = ::RubyLLM.embed(texts, model: model, **@options).vectors
        # RubyLLM returns a flat vector when it embedded a single text.
        vectors.first.is_a?(Numeric) ? [vectors] : vectors
      rescue *retryable_errors => e
        raise ProviderError, "#{e.class}: #{e.message}"
      end

      private

      # API errors (rate limits, 5xx, bad keys) plus network failures, which ruby_llm lets through from Faraday.
      def retryable_errors
        [::RubyLLM::Error, (::Faraday::Error if defined?(::Faraday::Error))].compact
      end

      def load_ruby_llm
        require "ruby_llm" unless defined?(::RubyLLM.embed)
      rescue LoadError
        raise ConfigurationError, 'The :ruby_llm provider needs the ruby_llm gem. Add gem "ruby_llm" to your Gemfile.'
      end
    end
  end
end
