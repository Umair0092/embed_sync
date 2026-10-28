# frozen_string_literal: true

module EmbedSync
  class Error < StandardError; end

  # Raised when EmbedSync is set up incorrectly (unknown provider, missing option, ...).
  class ConfigurationError < Error; end

  # Raised when an embedding provider fails or returns an unexpected response. EmbedJob retries these.
  class ProviderError < Error; end

  # Raised when vectors don't match has_embedding's dimensions:. Not retried: the setup has to change.
  class DimensionMismatchError < Error; end
end
