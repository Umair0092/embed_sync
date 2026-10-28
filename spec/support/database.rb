# frozen_string_literal: true

require "active_record"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :categories, force: true do |t|
    t.string :name
  end

  create_table :products, force: true do |t|
    t.string :name
    t.text :description
    t.references :category
    t.json :embedding
    t.string :embedding_digest
    t.json :title_embedding
    t.string :title_embedding_digest
  end
end

class Category < ActiveRecord::Base
  has_many :products
end

class Product < ActiveRecord::Base
  belongs_to :category, optional: true

  has_embedding :embedding, from: %i[name description], model: "test-model"
end
