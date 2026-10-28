# frozen_string_literal: true

module EmbedSync
  class Error < StandardError; end

  # Raised when EmbedSync is set up incorrectly (unknown provider, missing option, ...).
  class ConfigurationError < Error; end

  # Raised when an embedding provider fails or returns an unexpected response.
  class ProviderError < Error; end
end
