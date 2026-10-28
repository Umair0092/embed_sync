# frozen_string_literal: true

module EmbedSync
  module Providers
    # Interface every provider implements.
    class Base
      # Returns one vector (Array of Floats) per text, in the same order as +texts+.
      def embed(texts, model:)
        raise NotImplementedError, "#{self.class} must implement #embed(texts, model:)"
      end
    end
  end
end
