# data/

Centralized data layer — the sync engine owns all persistence (CLAUDE.md).
Providers talk to repositories only; repositories wrap DAOs and enqueue sync ops.

Planned shape (mirrors rupee-diary):

- `db/` — Drift database, one `database.dart` schema, DAOs per table group
- `api/` — Dio client + interceptors (JWT attach, 426 update-gate, retry/backoff)
- `repositories/` — repository per aggregate; the only surface providers touch
- `sync/` — sync engine: local `sync_queue`, push/pull drain, conflict handling
