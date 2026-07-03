# Kitabi App

Flutter mobile app for Kitabi — the primary platform (mobile-first; web comes
later). See root [CLAUDE.md](../CLAUDE.md): Riverpod codegen, go_router, Drift
as offline-first source of truth, Dio, supabase_flutter auth, workmanager sync
drain. Mirrors the architecture of the sibling project `rupee-diary/app`.

Quick start (Flutter SDK at `~/development/flutter`):

```bash
flutter pub get
flutter run -d <device>
flutter test && flutter analyze
```

Layout: `lib/core/` (router, theme, later sync engine) · `lib/data/` (Drift,
repositories, API client — see its README) · `lib/features/<name>/` (feature-first
UI) · `lib/l10n/` (all user-facing strings, English template).

Scope (see [feature-map.md](../feature-map.md) for the full v1 slice):

- Sign in (Google / Apple), CSV import as the front door
- Add books via ISBN scan or manual entry; personal library with statuses, dates,
  notes, shelves, favorites — fully usable offline
- Ratings + reviews, lending records with due reminders
- Dashboard, stats and charts, search + filters
- Opt-in, transparent LLM recommendations; social share cards
