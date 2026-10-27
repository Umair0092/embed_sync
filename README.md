# EmbedSync

> Keep vector embeddings in sync with your ActiveRecord models.

> **Status:** early development. The API below is the target design, not the shipped behavior yet. Follow the [roadmap issues](https://github.com/Umair0092/embed_sync/issues).

[neighbor](https://github.com/ankane/neighbor) lets you *search* vectors, and [ruby_llm](https://github.com/crmne/ruby_llm) lets you *generate* them. EmbedSync fills the gap between them by regenerating a record's embedding whenever the text it's built from changes, in a background job, without calling the API again for unchanged saves.

```ruby
class Product < ApplicationRecord
  has_neighbors :embedding
  has_embedding :embedding, from: -> { "#{name}\n#{description}" }
end
```

```bash
bin/rails g embed_sync:install
bin/rails g embed_sync Product
bin/rails embed_sync:backfill[Product]
bin/rails embed_sync:stale[Product]
```

## Roadmap

1. Core config and provider interface (with a fake provider for tests)
2. `has_embedding` macro, change detection and digest column
3. Background sync with ActiveJob
4. Rails generators (install and per-model migration)
5. Backfill and stale rake tasks
6. ruby_llm provider adapter
7. Query helper (`embed_query`) and neighbor integration
8. Instrumentation, retries and rate limiting
9. Re-embedding after a model change
10. Docs, demo app and the 0.1.0 release

## Installation

```bash
bundle add embed_sync
```

## Development

```bash
bin/setup
bundle exec rake   # specs + rubocop
```

## License

MIT, see [LICENSE.txt](LICENSE.txt).
