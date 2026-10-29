# frozen_string_literal: true

require "digest"

module EmbedSync
  module Providers
    # Deterministic, offline provider for tests: the same text and model always give the same
    # unit-length vector. Records every call in #calls so tests can assert on API usage.
    class Fake < Base
      attr_reader :dimensions, :calls

      def initialize(dimensions: 8)
        super()
        @dimensions = dimensions
        @calls = []
      end

      def embed(texts, model:)
        @calls << { texts: texts.dup, model: model }
        texts.map { |text| vector_for(text, model) }
      end

      private

      def vector_for(text, model)
        bytes = Digest::SHA256.digest("#{model}\n#{text}").bytes
        raw = Array.new(dimensions) { |i| (bytes[i % bytes.size] / 127.5) - 1.0 }
        norm = Math.sqrt(raw.sum { |x| x * x })
        norm.zero? ? raw : raw.map { |x| x / norm }
      end
    end
  end
end
