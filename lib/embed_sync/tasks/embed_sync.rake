# frozen_string_literal: true

namespace :embed_sync do
  find_models = lambda do |name|
    if name.present?
      [name.constantize]
    else
      Rails.application.eager_load! if defined?(Rails.application)
      ActiveRecord::Base.descendants.select { |klass| klass.embed_sync_definitions.any? && !klass.abstract_class? }
    end
  end

  # Without a model name, each embedding is visited once, on the class that declared it: STI subclasses
  # inherit their parent's has_embedding and their rows are already covered by the parent's table scan.
  each_embedding = lambda do |args, &block|
    explicit = args[:model].present?
    find_models.call(args[:model]).each do |model|
      definitions = model.embed_sync_definitions.values
      definitions = definitions.select { |d| d.column.to_s == args[:column].to_s } if args[:column].present?
      definitions = definitions.select { |d| d.owner == model } unless explicit
      if explicit && definitions.empty?
        raise ArgumentError, "#{model.name} has no has_embedding for #{args[:column].inspect}"
      end

      definitions.each { |definition| block.call(model, definition.column) }
    end
  end

  desc "Embed records that are missing or out of date. Usage: embed_sync:backfill[Product,embedding]"
  task :backfill, %i[model column] => :environment do |_task, args|
    each_embedding.call(args) do |model, column|
      count = EmbedSync::Backfill.run(model, column: column) { |total| print "\r#{model.name}##{column}: #{total}" }
      puts "\r#{model.name}##{column}: embedded #{count} records"
    end
  end

  desc "Report records whose embedding is missing or out of date. Usage: embed_sync:stale[Product,embedding]"
  task :stale, %i[model column] => :environment do |_task, args|
    each_embedding.call(args) do |model, column|
      report = EmbedSync::Backfill.report(model, column: column)
      puts "#{model.name}##{column}: #{report[:total]} total, #{report[:missing]} never embedded, " \
           "#{report[:stale]} stale"
    end
  end
end
