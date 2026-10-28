# frozen_string_literal: true

require "digest"

module EmbedSync
  # Describes one embedding declared with has_embedding: which column holds the vector,
  # where its text comes from, and which column stores the digest of that text.
  class Definition
    attr_reader :column, :source, :digest_column

    def initialize(column:, from:, model: nil, digest_column: nil)
      @column = column.to_sym
      @source = from
      @model = model
      @digest_column = (digest_column || "#{column}_digest").to_sym
      validate_source!
    end

    def model_name
      @model || EmbedSync.config.default_model ||
        raise(ConfigurationError,
              "No embedding model for #{column}. Pass model: or set EmbedSync.config.default_model.")
    end

    def source_text(record)
      text = case source
             when Proc then record.instance_exec(&source)
             when Array then source.filter_map { |attr| record.public_send(attr).presence }.join("\n")
             else record.public_send(source)
             end
      text.to_s
    end

    def digest(text)
      Digest::SHA256.hexdigest(text)
    end

    def stale?(record)
      text = source_text(record)
      return true if record[digest_column] != digest(text)

      text.present? && record[column].nil?
    end

    private

    def validate_source!
      return if source.is_a?(Proc) || source.is_a?(Symbol) || source.is_a?(String)
      return if source.is_a?(Array) && source.any?

      raise ArgumentError, "has_embedding from: must be an attribute name, an array of names or a proc"
    end
  end
end
