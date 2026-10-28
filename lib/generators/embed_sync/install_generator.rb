# frozen_string_literal: true

require "rails/generators/base"

module EmbedSync
  module Generators
    # rails g embed_sync:install
    class InstallGenerator < Rails::Generators::Base
      namespace "embed_sync:install"
      source_root File.expand_path("templates", __dir__)
      desc "Creates config/initializers/embed_sync.rb"

      def create_initializer
        template "initializer.rb.tt", "config/initializers/embed_sync.rb"
      end
    end
  end
end
