# EmbedSync

[![Gem Version](https://badge.fury.io/rb/embed_sync.svg)](https://rubygems.org/gems/embed_sync)
[![CI](https://github.com/Umair0092/embed_sync/actions/workflows/main.yml/badge.svg)](https://github.com/Umair0092/embed_sync/actions/workflows/main.yml)

> Keep vector embeddings in sync with your ActiveRecord models.

[neighbor](https://github.com/ankane/neighbor) lets you **search** vectors, and [ruby_llm](https://github.com/crmne/ruby_llm) lets you **generate** them. EmbedSync connects the two:

- regenerates a record's embedding in a background job when the text it's built from changes
- skips unchanged saves without calling the API again (it stores a digest of the text)
- backfills existing tables in batches, safely re-runnable, with one API call per batch
- re-embeds automatically when you switch embedding models
- one-line semantic search

```ruby
class Product < ApplicationRecord
  has_neighbors :embedding
  has_embedding :embedding, from: %i[name description]
end

Product.create!(name: "Trail runner", description: "Waterproof running shoe")  # embedded in the background
Product.semantic_search("shoes for rainy hikes", limit: 5)
```

## When to use it

Use EmbedSync if your Rails app stores embeddings in Postgres (pgvector) for semantic search or RAG, and you're writing the glue code yourself:

- embeddings go stale when records are edited, and you re-embed by hand or on a schedule
- an `after_save` callback calls the embeddings API on every save, even when the text didn't change
- you need to backfill embeddings for an existing table without blocking deploys or blowing past rate limits
- you switched embedding models (or dimensions) and need to find and re-embed every affected row

It's not a vector database client or an LLM framework: it keeps one thing correct, the vectors in your own tables.

## How it compares

| Gem | What it does | Use it with EmbedSync? |
|---|---|---|
| [neighbor](https://github.com/ankane/neighbor) | Nearest neighbor search and vector column types for Rails | Yes: EmbedSync fills the columns, neighbor searches them |
| [ruby_llm](https://github.com/crmne/ruby_llm) | One API for many LLM providers, including embeddings | Yes: it's the default provider EmbedSync calls |
| [pgvector](https://github.com/pgvector/pgvector-ruby) | Low-level pgvector support for Ruby | Not needed for Rails apps that use neighbor |
| [langchainrb_rails](https://github.com/patterns-ai-core/langchainrb_rails) | LLM toolkit for Rails: vector search over pgvector, Pinecone or Qdrant, plus Q&A over your records | Pick one: langchainrb_rails if you want the wider toolkit or an external vector store; EmbedSync if you want pgvector columns kept up to date with change detection, background jobs and stale-record reports |

## Requirements

- Ruby 3.2+, Rails 7.1+ (tested on 7.1, 7.2, 8.0 and 8.1)
- PostgreSQL with [pgvector](https://github.com/pgvector/pgvector), plus the `neighbor` gem for the `vector` column type and search
- An embedding provider: [ruby_llm](https://github.com/crmne/ruby_llm) (default) or your own

## Installation

```ruby
# Gemfile
gem "embed_sync"
gem "neighbor"
gem "ruby_llm"
```

```bash
bundle install
bin/rails g embed_sync:install                    # config/initializers/embed_sync.rb
bin/rails g embed_sync Product name description   # migration + has_embedding in app/models/product.rb
bin/rails db:migrate
bin/rails embed_sync:backfill                     # embed existing rows
```

Configure your API key for ruby_llm:

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure { |c| c.openai_api_key = Rails.application.credentials.openai_api_key }
```

## Usage

### Declaring embeddings

```ruby
class Product < ApplicationRecord
  belongs_to :category

  has_neighbors :embedding

  # Attribute names are joined with newlines (blank values are skipped)
  has_embedding :embedding, from: %i[name description]

  # ...or build the text yourself; the lambda runs on the record (or takes it: ->(product) { ... })
  has_embedding :embedding, from: -> { "#{name}\nCategory: #{category&.name}" }
end
```

| Option | Default | |
|---|---|---|
| `from:` | (required) | attribute, array of attributes, or lambda |
| `model:` | `config.default_model` | embedding model name |
| `dimensions:` | `provider_options[:dimensions]` | rejects vectors of a different size (`DimensionMismatchError`); not sent to the provider |
| `sync:` | `config.sync` (`:async`) | `:async` (Active Job after commit), `:inline`, or `false` |
| `if:` / `unless:` | none | only sync matching records, as with Rails callbacks |
| `digest_column:` | `<column>_digest` | where the text digest is stored |

A model can have several embeddings (`has_embedding :title_embedding, ...`). Pass `column:` to the methods below when it does.

### Methods

```ruby
product.embedding_stale?          # text, model or dimensions changed since the last embedding?
product.embedding_source_text     # the text that gets embedded
product.refresh_embedding!        # re-embed now, even if fresh

Product.embedding_missing         # scope: never embedded
Product.embed_query("red shoes")  # vector for a search string, using the column's model
Product.where(published: true).semantic_search("red shoes", limit: 10, distance: "cosine")
# results respond to #neighbor_distance

EmbedSync.without_sync { import_products! }        # no jobs during bulk imports (also inside a transaction)
EmbedSync.backfill(Product.includes(:category))    # => number of records embedded
EmbedSync.stale_report(Product)                    # => { total:, missing:, stale: }
```

### Rake tasks

```bash
bin/rails embed_sync:stale                          # all models with has_embedding
bin/rails "embed_sync:backfill[Product]"
bin/rails "embed_sync:backfill[Product,embedding]"
```

Backfill only embeds stale records, so you can stop it and run it again at any time.

## Configuration

```ruby
EmbedSync.configure do |config|
  config.provider = :ruby_llm                      # or :fake, or any object with #embed(texts, model:)
  config.provider_options = { dimensions: 1536 }   # passed to RubyLLM.embed
  config.default_model = "text-embedding-3-small"
  config.sync = :async                             # :async, :inline or false
  config.queue = :default
  config.priority = nil
  config.batch_size = 100                          # texts per API call when backfilling
  config.concurrency_limit = nil                   # Solid Queue: max EmbedJobs running at once
  config.query_cache = nil                         # e.g. Rails.cache, to cache search-query vectors
  config.query_cache_expires_in = 86_400
end
```

`:async` needs Active Job (apps created with `rails new --minimal` turn it off; use `sync: :inline` there).

### Custom providers

```ruby
class MyProvider
  # Return one vector (Array of Floats) per text, in order.
  def embed(texts, model:)
    MyClient.embeddings(input: texts, model: model).map { _1["embedding"] }
  end
end

EmbedSync.config.provider = MyProvider.new
```

Raise `EmbedSync::ProviderError` for errors worth retrying (rate limits, timeouts) and `EmbedSync::InvalidRequestError` for requests that will never succeed (text too long, bad API key).

## Production notes

- **Retries:** `EmbedSync::EmbedJob` retries `ProviderError` 5 times with polynomial backoff, and discards jobs for deleted records and for `InvalidRequestError` (retrying a rejected request doesn't help).
- **Failures don't break saves or backfills:** with `sync: :inline`, a provider error is logged and the record stays stale instead of raising from `save`. Backfill skips records the provider rejects and carries on; `embed_sync:stale` still lists them.
- **Long texts:** embedding models have an input limit (about 8k tokens for OpenAI and nomic-embed-text). Records over it are rejected and stay stale; trim them in the source, e.g. `from: -> { "#{name}\n#{description}".first(20_000) }`.
- **Concurrent edits:** if a record changes while its embedding is being generated, the older result is discarded rather than written over the newer text. Override in an initializer: `EmbedSync::EmbedJob.retry_on EmbedSync::ProviderError, wait: 1.minute, attempts: 10`.
- **Rate limits:** with Solid Queue, `config.concurrency_limit = 2` caps how many embedding jobs run at once.
- **Observability:** every provider call publishes `embed.embed_sync` (`record_class`, `column`, `model`, `count`) and is logged:
  ```
  EmbedSync (182.4ms) embedded 100 Product#embedding texts with text-embedding-3-small
  ```
- **Changing models:** the digest covers the model and dimensions (`has_embedding dimensions:` or `provider_options[:dimensions]`), so changing either marks every row stale and gives search queries a new cache key. For live search, add a second column (`--column=embedding_v2`), backfill it, switch `semantic_search(..., column: :embedding_v2)`, then drop the old one.

## Testing your app

Use the deterministic, offline `:fake` provider in tests. The install generator sets this up, with syncing off so tests don't embed unless they ask to:

```ruby
# config/initializers/embed_sync.rb
config.provider = Rails.env.test? ? :fake : :ruby_llm
config.sync = Rails.env.test? ? false : :async   # use :inline in tests that need real vectors
```

`EmbedSync.provider.calls` records every call made to the fake.

## Development

```bash
bin/setup
bundle exec rake                       # specs + RuboCop

# Another Rails version
BUNDLE_GEMFILE=gemfiles/rails_7.1.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7.1.gemfile bundle exec rspec

# Integration specs against PostgreSQL + pgvector
docker run -d -p 54329:5432 -e POSTGRES_PASSWORD=postgres pgvector/pgvector:pg17
DATABASE_URL=postgres://postgres:postgres@localhost:54329/postgres bundle exec rspec spec/integration
```

## License

MIT, see [LICENSE.txt](LICENSE.txt).
