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

  each_embedding = lambda do |args, &block|
    find_models.call(args[:model]).each do |model|
      columns = args[:column].present? ? [args[:column]] : model.embed_sync_definitions.keys
      columns.each { |column| block.call(model, column) }
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
