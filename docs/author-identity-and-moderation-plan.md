# Author identity & content moderation — plan

**Simplified 14 Jul 2026** after owner clarified the actual near-term use
case: a handful of writer friends, personally invited, who sign up, manage
their own library like any reader, and also add their own books to the
catalog — with their public profile showing "works by them." No open
public sign-up, no strangers claiming authors, no crowd to moderate yet.
That changes the right answer a lot: the claim/evidence/approval design
further down this doc is now **shelved, not built** — kept as the plan for
if Kitabi ever opens beyond an invited circle. Build the simple version
below first.

---

## The simple version (build this)

### The insight

Nothing here needs a new table. Two things already exist that do 90% of the
work:

- `POST /catalog/authors` already takes `created_by_user_id` from whoever's
  signed in ([catalog.py:350-359](../api/app/api/catalog.py)) — when a friend
  adds their own book, they're already the one creating the Author row.
- `GET /users/{user_id}/library` already shows another reader's public
  library, gated on `profile.library_visible`
  ([users.py:45-52](../api/app/api/users.py)) — the exact shape needed for
  "works by them" on a profile, just pointed at a different query.

The only missing piece is a **link from an Author row to the Profile who is
that author**, plus a place to show it. No claim workflow, no evidence, no
approval queue, no verified badge — you personally know and invited these
friends, so the trust check already happened outside the app.

### Data model — one column

`authors.linked_user_id: uuid | None, index` (nullable FK to `profiles.id`).
That's it. No new table.

### Flow

1. **The common case — adding their own book for the first time:** the
   existing add-book form's author field already lets you type a new name
   and create it (`catalog.py` author picker "add new"). Add one checkbox,
   "This is me," visible only when creating a brand-new Author (not when
   picking an existing one from the typeahead). Checking it just passes
   `linked_user_id = current_user_id` in the same `POST /catalog/authors`
   call that already runs. Zero extra screens.
2. **The Author row already exists** (someone else added their book first,
   or it came in via an OpenLibrary ISBN lookup): a "This is me" button on
   that author's page, visible to any signed-in user, does a one-tap
   `PATCH /catalog/authors/{id}` guarded by `linked_user_id IS NULL` — first
   to claim it wins, atomically, no pending state. If it's already linked to
   someone else and that's wrong, you fix it directly (you're personally
   onboarding every author friend, so a bad link is a two-minute DB fix, not
   a workflow to build).
3. **Profile page — a "Works" tab:** new endpoint
   `GET /users/{user_id}/works`, same shape as the existing
   `public_library` — query `Work`s joined through `work_authors` to any
   `Author` with `linked_user_id = user_id`. Surfaced as a tab on the
   existing profile screen, next to a "Library" tab (reusing the
   Lent-out/Borrowed segmented-control pattern from the lending ledger), not
   a bolted-on card — see the mockups below. Gate it on
   `profile.profile_visible` (same flag the profile itself already uses),
   independent of `library_visible` — their published works are catalog
   data, not their personal reading list, so it's a separate toggle from "is
   my library public," and the tab stays open even when the Library tab is
   locked.
4. **Mapping a friend as the author when adding *their* book** (a different
   user is adding a book written by an author-friend, not the friend adding
   their own): the existing author typeahead
   (`GET /catalog/authors?q=`, already used by 7b's author field) just needs
   to return `linked_user_id` on each result so the picker can show a small
   "🔗 on Kitabi" pill next to a linked friend's name — picking that row
   credits the book to their real, already-linked Author row like any other
   existing-author pick. No new endpoint, one extra field on `AuthorOut`.
5. **Global search surfaces authors, not just books:** `search_authors`
   already exists (`GET /catalog/authors?q=`); global search just needs to
   run it alongside the existing work/library search and render an
   "Authors" section above/below the book results, same 🔗 pill as above.
6. **Author page → public profile:** on the author page (4c), when
   `linked_user_id` is set, show one extra row, "View their Kitabi profile,"
   linking to `GET /users/{user_id}/profile` (already built) — no new
   endpoint on this side either.

### Mockups

Added to [docs/kitabi_screens.html](kitabi_screens.html) (14 Jul 2026, revised
same day after owner feedback) — open it and jump to the "Home" and "Library"
sections:

- **4e** — global search's new "Authors" section, linked author carries the
  🔗 badge.
- **4f** — the author page with a "View her Kitabi profile" button (only
  shown when `linked_user_id` is set) — an outlined oxblood `.btn.ghost`, not
  a plain text row (the first pass looked like dead space, fixed after
  feedback). The avatar itself is also a tell — oxblood + gold ring for a
  linked reader (same treatment the profile screen uses for you) vs. the
  plain gold-soft initials circle on the unlinked 4c.
- **4g** — the *same* profile screen every "view Kitabi profile" door opens
  onto, not a bespoke author-only page — its header matches the existing
  profile screen (12) exactly. **Works is a tab, not a card section**: a
  segmented control next to **Library**, reusing the exact chiprow pattern
  the lending ledger already uses for Lent out/Borrowed (8b). Library can be
  locked (🔒) while Works stays open — a private reader can still be a public
  author, independent toggles on purpose. Step 3's `GET /users/{user_id}/works`
  is what backs this tab.
- **7c** — the add-book author field, showing the 🔗-badged friend match
  mid-typeahead (step 4 above), sitting right next to unrelated near-matches
  and the existing "add new" affordance — one dropdown, not a special mode.

### What this does *not* need

- No `author_claims` table, no evidence upload, no pending/approved/rejected
  state — there's no queue because there's no stranger to vet.
- No `verified` flag/badge — with an invited-only friend circle, every link
  is already "verified" by the fact that you personally set them up.
- No extension to the `work_revisions` moderation queue — a friend editing
  their own book's details is exactly the existing "contributor edits apply
  live" path (`catalog_service.propose_or_apply_update`), unchanged.
- No rate limiting, no abuse handling — not a real risk at friend-circle
  scale.

### Data model summary (net new)

- `authors.linked_user_id` column + migration + index.
- `GET /users/{user_id}/works` endpoint (mirrors `public_library`).
- `PATCH /catalog/authors/{id}` "This is me" self-link, guarded by
  `linked_user_id IS NULL`.
- "This is me" checkbox on the add-author flow, wired through the existing
  `create_author` call.
- "Works by [name]" section on the profile screen.

RLS: no change needed — `linked_user_id` lives on the already-RLS'd
`authors` table, written only through the API, same as every other column
on it (rule 11).

### Where this lands in `docs/tasks.md`

Phase 2 — Shared catalog, same place as the previous entry:

- [ ] `authors.linked_user_id` column + migration
- [ ] "This is me" checkbox on add-author (new-author case) + self-link
      button on the author page (existing-author case)
- [ ] `GET /users/{user_id}/works` + "Works by [name]" section on the
      profile screen (app)

### When to revisit the heavier design below

Only if Kitabi ever opens to sign-up beyond people you personally invite —
at that point a stranger claiming "I am this author" needs evidence and
review, and public catalog data needs a real trust signal. The claim table,
verified badge, and moderation queue extension below are the plan for that
day; nothing about the simple version above needs to be undone to get
there — `linked_user_id` becomes `claimed_by_user_id`'s first-approved
value, and the self-link button becomes the "submit a claim" button gated
behind an approval step instead of applying instantly.

---

## Appendix — the fuller design, shelved for when there's a public crowd

*(Original 14 Jul 2026 plan, kept for reference — not being built now.)*

### Part A — User is also an author (full version)

New table `author_claims` (mirrors `work_revisions`' shape deliberately):

| column | type | note |
|---|---|---|
| `id` | uuid pk | |
| `author_id` | uuid, FK `authors.id`, index | which catalog Author row |
| `user_id` | uuid, index | the claimant (`profiles.id`) |
| `evidence` | jsonb | free-form: links (publisher page, Amazon/Goodreads author page, personal site, social profile), a note. No file upload — rule 8, no storage bucket yet |
| `status` | string, index, default `pending` | `pending` \| `approved` \| `rejected` |
| `created_at` | timestamptz | |
| `decided_at` | timestamptz, nullable | |
| `decided_by_user_id` | uuid, nullable | who approved/rejected |

Partial unique index: `(author_id) WHERE status = 'approved'` — only one
approved claim per Author row at a time.

`authors` gains `claimed_by_user_id`, `verified`, `verified_at`. Approver =
owner, manually, for V1 (no paid identity-verification service — rule 8).
On approval, extend `catalog_service`'s ownership check so a verified
claimant can also edit-immediately on Works they're listed as an author of.

Unlocks later (Layer 4): author responds to reviews, sees engagement stats,
gets notified on new ratings/reviews of their work.

Edge cases: multiple Author rows for one person (pen names) — one Profile
can hold multiple approved claims. Revoke — owner flips `approved` back to
`rejected`, nulls the pointer, keeps the row as an audit trail. Abuse — rate
limit claim submissions per user.

### Part B — Content moderation & the "verified" flag (full version)

Two different "verified" claims, kept as separate fields:

| | Author identity verified | Content/data trust |
|---|---|---|
| Question | "Is this really that author?" | "Is this catalog data / review accurate, not abusive?" |
| Lives on | `authors.verified` only | Not built — `[LATER]` per feature-map.md, "nothing to moderate when solo" |
| Who decides | Owner, from evidence | Community flags + owner, at scale |

Extend the existing `work_revisions` wiki-style pattern (unowned/
self-contributed edits apply live, everyone else's queue for approval) to
`Author` edits too — currently Work-only.

Generic `content_reports` table (`[WIRED]`, dormant): `id`,
`reporter_user_id`, `entity_type`, `entity_id`, `reason`, `status`,
`created_at`, `resolved_at`, `resolved_by_user_id`. No auto-hide logic, no
admin portal — a queue the owner can query directly, same "build the shape,
skip the UI" move feature-map.md already uses elsewhere.

Abuse prevention stays cheap and in-Postgres (per-user rate limits via a
plain count query) — no Redis, no external service, per rule 8.

Deliberately still `[LATER]`: admin/moderation portal, auto-hide on report
threshold, community moderators, appeals flow, generic data-trust `verified`
flag on `Work`/`Edition`/`Publisher`.
