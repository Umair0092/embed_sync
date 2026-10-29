# frozen_string_literal: true

module EmbedSync
  # Registry of embedding providers, looked up by name.
  module Providers
    @registry = {}

    class << self
      # The class is given as a string so a provider's dependencies only load when it is used.
      def register(name, class_name)
        @registry[name.to_sym] = class_name
      end

      def registered
        @registry.keys
      end

      def build(name, **)
        class_name = @registry.fetch(name.to_sym) do
          raise ConfigurationError,
                "Unknown provider #{name.inspect}. Registered providers: #{registered.join(", ")}"
        end
        require_relative "providers/ruby_llm" if class_name == "EmbedSync::Providers::RubyLLM"
        Object.const_get(class_name).new(**)
      end
    end
  end
end

require_relative "providers/base"
require_relative "providers/fake"

EmbedSync::Providers.register(:fake, "EmbedSync::Providers::Fake")
EmbedSync::Providers.register(:ruby_llm, "EmbedSync::Providers::RubyLLM")
