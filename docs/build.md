# Kitabi — Build & Run Guide

> **Purpose.** The single place for "how do I build, run, test, and ship each part
> of Kitabi." Prerequisites, exact commands, the gotchas that have bitten us, and
> the release paths for API, app (iOS + Android), and the landing page.
>
> Companion docs: [architecture.md](architecture.md) (how the system fits together
> and a file-by-file map), [../STATUS.md](../STATUS.md) (what's live/deployed),
> [../CLAUDE.md](../CLAUDE.md) (conventions and non-negotiable rules).

The repo is a monorepo with three independent parts — `api/` (FastAPI),
`app/` (Flutter), `landing-page/` (static). Each builds and ships on its own.

---

## 0. Prerequisites (one-time machine setup)

| Tool | Version | Notes |
|---|---|---|
| Python | 3.12+ | Homebrew `python@3.12`. The API is 3.12-only (async SQLAlchemy 2.0). |
| Docker | any recent | Local Postgres for dev + the throwaway test DB; and `docker build` (rule 9). |
| Flutter SDK | matches `app/pubspec.yaml` `sdk: ^3.12.2` | Installed at `~/development/flutter` — **not on the default PATH**. |
| Xcode | current | iOS builds; ships the JBR-independent toolchain. |
| Android Studio / JDK | JBR bundled with Android Studio | `keytool`/Gradle need a JDK — use Android Studio's JBR at `/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin`. |
| CocoaPods | current | iOS pods. |

**Local ports** are offset from the sibling project `rupee-diary` so both run side
by side: dev Postgres **55442**, throwaway test Postgres **55443**.

---

## 1. API (`api/`)

FastAPI, fully async, Python 3.12. Local venv at `api/.venv`.

### First-time setup

```bash
cd api
python3.12 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt   # runtime + dev (ruff/black/pytest)
cp .env.example .env                            # then fill in (see below)
docker compose up -d db                          # local Postgres on port 55442
.venv/bin/alembic upgrade head                   # apply all migrations
```

### `.env` (gitignored — never commit)

```
ENV=dev
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:55442/postgres
# Production uses the Supavisor transaction pooler URL (port 6543), NOT the direct
# db.<ref>.supabase.co:5432 connection — that hostname is IPv6-only and times out
# on networks without IPv6 (see CLAUDE.md "Lessons learned in Kitabi").
SUPABASE_URL=https://<project-ref>.supabase.co
```

Optional/feature-gated env (dormant when unset — CLAUDE.md rule 8):
- `ANTHROPIC_API_KEY` — enables LLM recommendations (`GET /recommendations`) **and**
  cover-photo extraction (`POST /catalog/cover-extract` — prefill the add-book form
  from photographed covers when a scan finds nothing).
- `FIREBASE_CREDENTIALS` — the Firebase Admin service-account JSON; enables FCM push.
- `SCHEDULER_ENABLED=true` — turns on APScheduler jobs (Supabase keep-warm).

### Run / test / lint

```bash
cd api
.venv/bin/uvicorn app.main:app --reload            # dev server → http://localhost:8000/healthz
.venv/bin/pytest                                    # spins up kitabi-test-pg container (port 55443)
.venv/bin/ruff check . && .venv/bin/black --check . # lint (line length 100)
docker build -t kitabi-api .                        # MUST always build (rule 9)
```

### Migrations

```bash
.venv/bin/alembic revision --autogenerate -m "describe change"
.venv/bin/alembic upgrade head          # apply
.venv/bin/alembic downgrade -1          # roll back one (test reversibility before shipping)
```

- **Every model change ships its migration in the same commit.** Never edit an
  applied migration.
- Verify `upgrade` **and** `downgrade` on a scratch DB before deploy.
- Production migrations run automatically on deploy — the Docker `CMD` runs
  `alembic upgrade head` before uvicorn boots. Because the active `.env`
  `DATABASE_URL` can point at prod, run migrations against prod **deliberately**,
  not casually.

### Deploy

Push to `main` — Railway watches the repo (Root Directory `api`) and auto-deploys.
No `railway up` needed. The container runs `alembic upgrade head` then uvicorn.
See [../STATUS.md](../STATUS.md) for the live URL and Railway/region config.

---

## 2. App (`app/`)

Flutter, offline-first. Drift + Riverpod are **code-generated** — regenerate after
touching any Drift table or `@riverpod`-annotated file.

### First-time setup

```bash
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift + Riverpod codegen
cp dart_defines.env.example dart_defines.env               # then fill in real values (gitignored)
```

### `dart_defines.env` (gitignored — never commit)

```
API_BASE_URL=https://api.kitabi.in
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_PUBLISHABLE_KEY=<anon/publishable key>
```

> **Critical gotcha.** Every `--dart-define` the app reads must be passed on
> **every** `flutter build`/`flutter run` — none carry over, and a missing one
> **fails silently** (the app falls back to an in-code default and runs
> unconfigured: wrong API host, or a stub auth service that always fails sign-in
> with no build-time error). This bit us repeatedly. **Never call
> `flutter run`/`flutter build ipa` directly with hand-typed defines** — always
> use the scripts below, which read every required key from `dart_defines.env`
> and **fail loudly** if one is missing.

### Run / test / analyze

```bash
cd app
./scripts/run_dev.sh -d <device>        # NOT `flutter run` directly
flutter test                             # widget + unit tests (no defines needed)
flutter analyze                          # static analysis
```

After changing a Drift table or Riverpod codegen file, **run build_runner** before
trusting any analyzer error — stale generated code produces confusing phantom errors.

### Build a release iOS IPA

```bash
cd app
./scripts/build_ipa.sh                   # → build/ios/ipa/kitabi.ipa
```

Upload via Apple Transporter or `xcrun altool --upload-app`. Notes:
- **Bump `version:` in `pubspec.yaml`** (the `+NN` build number) for every store
  upload — App Store Connect rejects a duplicate build number. If a build number
  looks "stuck," wipe Xcode DerivedData and `flutter clean` (stale DerivedData once
  pinned CFBundleVersion to an old value and every IPA was rejected as a duplicate).
- iOS deployment target is **15.5** (raised for `mobile_scanner`'s MLKit).
- **`mobile_scanner` cannot build on an Apple Silicon iOS Simulator** (MLKit ships
  no arm64 simulator slice). Verify the ISBN-scan screen on a **real iPhone** or an
  **Android emulator**, not the iOS Simulator.
- TestFlight/production APNs push needs a **Production** APNs key uploaded to
  Firebase and the `aps-environment` entitlement set to `production`.

### Build a release Android AAB

```bash
cd app
./scripts/build_aab.sh                   # → build/app/outputs/bundle/release/app-release.aab
```

Upload to Play Console → Internal testing → Create release. Prerequisites:
- **Upload keystore** kept OUTSIDE the repo:
  ```bash
  keytool -genkey -v -keystore ~/keys/kitabi-upload.jks \
    -keyalg RSA -keysize 2048 -validity 10000 -alias upload
  ```
  (Use Android Studio's bundled JBR `keytool` if `java` isn't on PATH.)
- `android/key.properties` (gitignored) — copy `key.properties.example`, point
  `storeFile` at `~/keys/kitabi-upload.jks`, fill passwords/alias. The script
  refuses to build without it (a debug-signed AAB is rejected by Play).
- Play uses **Google-managed app signing** — your upload key signs the AAB, Google
  re-signs with the distribution key.
- `compileSdk = 36`, `targetSdk = 35`. Some plugins (e.g. `image_cropper`) pin an
  older compileSdk; `android/build.gradle.kts` force-overrides plugin compileSdk to
  36 in an `afterEvaluate` block.
- R8 minification is **off** (`isMinifyEnabled = false`, `isShrinkResources =
  false`) — R8 was stripping WorkManager/Room and Firebase/MLKit registrars and
  crashing the app on launch.

### Codegen, icons, splash

```bash
dart run build_runner build --delete-conflicting-outputs   # Drift/Riverpod
dart run flutter_launcher_icons                             # app icons
dart run flutter_native_splash:create                       # native splash
flutter gen-l10n                                            # regenerate l10n from .arb (also runs on build)
```

App icon source is a **flat full-bleed square** (`assets/icon/app_icon.svg`) — the
OS applies its own rounding; the splash reuses the already-rounded brand tile.

---

## 3. Landing page (`landing-page/`)

Dependency-free static HTML/CSS — **no build step, no frameworks**. Edit and open
`index.html` directly, or serve the folder with any static server. Deploys to
Cloudflare Pages on push to `main` touching `landing-page/**` via
`.github/workflows/deploy.yml` (needs `CLOUDFLARE_API_TOKEN` +
`CLOUDFLARE_ACCOUNT_ID` repo secrets). The `/b/:id` `/a/:id` `/p/:id` share routes
are served by Cloudflare **Pages Functions** (`landing-page/functions/`) that inject
Open Graph tags server-side so shared links preview richly.

Regenerate logo rasters from `logo.svg`:
```bash
qlmanage -t -s 512 -o . logo.svg && sips ...   # kitabi-logo.png (512), ico.png (64)
```

---

## 4. CI (GitHub Actions)

Lint/test/build checks only — **not** deployment (except the landing page):

- **`api-ci.yml`** (paths `api/**`) — ruff, black, pytest against `postgres:17-alpine`,
  pip-audit (advisory), `docker build`.
- **`app-ci.yml`** (paths `app/**`) — `flutter pub get`, `build_runner`,
  `flutter analyze`, `flutter test`.
- **`deploy.yml`** (paths `landing-page/**`) — deploys to Cloudflare Pages.
- **API deploy is via Railway's own git integration**, not Actions.

---

## 5. Definition of done (before ticking a task / committing)

Per [../CLAUDE.md](../CLAUDE.md):
1. Code + tests pass (`pytest` / `flutter test`).
2. Lint clean (`ruff` + `black` / `flutter analyze`).
3. Migration included in the same commit if the schema changed.
4. `docker build` still works.
5. App features work **offline** (airplane-mode check for Layer-2 data).
6. Matches the mockup ([kitabi_screens.html](kitabi_screens.html)).
7. [../STATUS.md](../STATUS.md) updated if architecture/integration/deploy/feature
   state changed.
