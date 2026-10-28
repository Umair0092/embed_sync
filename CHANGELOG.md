## [Unreleased]

## [0.1.0] - Unreleased

First release.

- `has_embedding` macro: attribute list or lambda as the source, `model:`, `dimensions:`, `sync:`, `if:`/`unless:`
- Change detection with a digest of the text, model and dimensions (`<column>_stale?`, `<column>_missing` scope)
- Background sync after commit with `EmbedSync::EmbedJob`; `:inline` and disabled modes; `EmbedSync.without_sync`
- Generators: `embed_sync:install` and `embed_sync MODEL attrs...` (pgvector migration with HNSW/IVFFlat index)
- `EmbedSync.backfill` / `EmbedSync.stale_report` and the `embed_sync:backfill` / `embed_sync:stale` rake tasks
- Providers: `:ruby_llm` (default) and `:fake`; custom providers are any object with `#embed(texts, model:)`
- `Model.embed_query` and `Model.semantic_search` (neighbor), with an optional query cache
- `embed.embed_sync` instrumentation and log subscriber; retries with backoff; Solid Queue concurrency limit
