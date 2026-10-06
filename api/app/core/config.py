"""Settings loaded from env via pydantic-settings: DB URL, Supabase JWKS/JWT
verification config, CORS, version gate, and opt-in recs/push credentials."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    env: str = "dev"
    app_version: str = "0.1.0"

    # Local dev: `docker compose up -d db` (see compose.yaml). Railway sets the
    # Supavisor transaction-pooler URL (port 6543), never the direct connection.
    # One engine everywhere: Postgres (Identity, advisory locks, RLS).
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:55442/kitabi"

    # Supabase JWT verification (asymmetric signing keys, ES256)
    supabase_url: str = ""  # e.g. https://<project-ref>.supabase.co
    jwt_audience: str = "authenticated"

    # CORS: the mobile app needs none. The landing page's public share pages
    # (kitabi.in/b/:id, /a/:id, /p/:id) fetch the unauthenticated catalog
    # endpoints from the browser, so that origin must be allowed.
    cors_origins: list[str] = ["https://kitabi.in", "https://www.kitabi.in"]

    scheduler_enabled: bool = False

    # IndexNow: ping Bing/Yandex/Seznam/Naver when a book page worth indexing
    # appears, instead of waiting to be re-crawled. Free and keyless (the key is
    # public by design — see services/indexnow.py), so rule 8 holds.
    #
    # OFF by default so a developer adding a book on a laptop never announces a
    # page to the internet. Production opts in via `ENV INDEXNOW_ENABLED=1` in
    # api/Dockerfile — in the repo, not a dashboard, so it is readable from a
    # checkout. Note Google does NOT consume IndexNow; that still needs Search
    # Console.
    indexnow_enabled: bool = False

    # Daily catalogue intake (docs/catalog-intake-plan.md). The job discovers
    # candidate books, screens them against the completeness gate, and promotes
    # the complete ones — unattended, every night.
    #
    # OFF by default, and this is the important half. Merging the pipeline to
    # main must not start creating catalogue rows: a developer running the API
    # on a laptop, a test database, a preview deploy — none of them should
    # publish books. Production opts in via `ENV CATALOG_INTAKE_ENABLED=1` in
    # api/Dockerfile, declared in the repo rather than a dashboard so the one
    # place that publishes is readable from a checkout (the same shape as
    # INDEXNOW_ENABLED and ALLOW_PROD_MIGRATION).
    catalog_intake_enabled: bool = False
    # When the nightly run starts, in UTC (the scheduler's zone). 21:00 UTC is
    # **02:30 IST** — owner decision, 6 Oct 2026, moved from 02:30 UTC (08:00
    # IST). A fixed UTC time rather than a zone name: India has no DST, and a
    # slim image may not ship tzdata. The admin console's "nightly intake"
    # screen reads these two to know which night it is judging, so the screen
    # and the schedule cannot drift apart.
    catalog_intake_run_hour_utc: int = 21
    catalog_intake_run_minute_utc: int = 0
    # Books promoted per run. The ceiling on how fast the catalogue can grow,
    # and therefore the ceiling on how much a mistake in a source adapter can
    # cost before anyone looks. 150 since 4 Oct 2026 (owner): at 50 the three
    # storefronts' ~10,000 titles would have taken most of a year.
    catalog_intake_daily_limit: int = 150
    # Candidates each seed contributes per discovery pass. Discovery writes
    # only to `catalog_intake`, so this bounds crawling, never publishing.
    catalog_intake_per_seed: int = 50
    # Publishers' storefronts (services/intake_storefront.py). Each night reads
    # every shop's newest page, then this many further pages of its backlist —
    # a hundred books a page, one request each. Staging only: it bounds
    # crawling, never publishing.
    catalog_intake_backlist_pages: int = 3
    # Product pages read per night to fill what a feed leaves out (ISBN,
    # author, the title in its own script). One request a second, so this is
    # also roughly how many seconds the pass takes. Kept at twice the daily
    # limit: two of the three shops are complete only once their page is read,
    # so reading has to stay ahead of publishing or the limit is never reached.
    catalog_intake_enrich_limit: int = 300
    # Held books whose credits the LLM is asked about per night
    # (services/author_roles.py). A paid call each, so this is a spend limit as
    # much as a pace; `llm_daily_quota_author_roles` is the hard ceiling.
    catalog_intake_roles_limit: int = 60
    # Kerala Book Store pages read per night (services/intake_keralabookstore.py).
    # **0 — off — by default**, and that is the point: it is a multi-publisher
    # retailer, not a publisher's own shop, so whether its covers may be copied
    # to our bucket is the owner's decision, not a default. Ten seconds a page
    # (the shop's stated crawl delay), so 150 is about twenty-five minutes.
    catalog_intake_keralabookstore_pages: int = 0

    # Version gate: the app sends `X-App-Version`; anything older than this gets
    # a 426 with an update payload (CLAUDE.md — the update-gate). Bump when a
    # release must be forced.
    min_app_version: str = "0.1.0"

    # LLM-reasoned recommendations (the opt-in "quiet delight" — feature-map.md).
    # Optional: unset means the feature is dormant and no external call is made
    # (CLAUDE.md rule 8 — the owner opts in by providing a key, so there's no
    # mandatory bill/credential). Recs are cheap, so default to a small model.
    anthropic_api_key: str = ""
    recs_model: str = "claude-haiku-4-5-20251001"
    # Cover-photo extraction (prefill the add-book form from photographs of a
    # book the catalog doesn't know). Same key/gate as recs. Uses a STRONGER
    # model than recs: extraction is rare (only for books no catalog knows,
    # disproportionately regional-language) and reads stylised regional scripts
    # off a photo — Haiku hallucinated Malayalam titles (verified on device
    # 8 Jul 2026), Sonnet reads them. Still pennies per call given how rarely
    # this path runs.
    extraction_model: str = "claude-sonnet-5"
    # Deciding who wrote and who translated a book from the publisher's own
    # blurb and biographies (services/author_roles.py). The most capable model
    # because the failure this guards against is a *wrong* credit on a public
    # page, and the volume is small: roughly a fifth of two shops' books, once.
    # The request is shaped for this model generation (effort, structured
    # output, refusal fallbacks) — check all three before pointing it elsewhere.
    author_roles_model: str = "claude-opus-5-5"

    # Daily spend limits for the two endpoints that cost real money. Auth on
    # them means "any signed-in reader", so without a ceiling the cap on the
    # Anthropic bill is the caller's patience. Enforced in
    # services/llm_quota.py against the `llm_usage` table — Postgres, not
    # Redis (rule 8). Set any of these to 0 to disable that limit entirely.
    #
    # Per reader, per UTC day. Sized against real use: recs are one deliberate
    # screen visit each, extraction is the rescue path for books no catalog
    # knows (a reader bulk-adding a shelf might genuinely photograph dozens).
    llm_daily_quota_recommendations: int = 20
    llm_daily_quota_cover_extract: int = 40
    # Not per reader: the whole intake job's ceiling for one UTC day, whatever
    # `catalog_intake_roles_limit` or a restarted run would otherwise spend.
    llm_daily_quota_author_roles: int = 100
    # The circuit breaker: total paid calls across ALL readers in one UTC day.
    # This is the number that actually bounds the bill — the per-reader caps
    # only stop one account from being the whole problem.
    llm_daily_global_cap: int = 1000
    # How long a cached recommendation result stays servable when its inputs
    # haven't changed. The fingerprint invalidates on any rating/library
    # change; this bound exists so a dormant shelf still sees catalogue growth.
    recs_cache_ttl_days: int = 7

    # Affiliate tag for the generated Amazon buy link (services/buy_links.py —
    # docs/revenue-plan.md §3.1, Amazon-only since 9 Aug 2026). A plain URL
    # parameter, not an API credential (rule 8): unset means the link renders
    # untagged and earns nothing, so the feature ships dormant and the owner
    # flips revenue on by setting the tag in Railway after the Associates
    # account is approved. (flipkart_affiliate_id / cuelinks_cid lived here
    # until the one-button decision; extra="ignore" keeps any lingering env
    # values harmless.)
    amazon_associate_tag: str = ""

    # Supabase Storage writes (the `covers` bucket the app and admin console
    # already use). Needed only by the cover backfill job, which copies
    # hotlinked catalogue covers into a bucket we own — a cache is not
    # ownership. Optional and dormant when unset, like recs and push (rule 8):
    # no key means the job no-ops and makes no external call. The anon key is
    # not enough; Storage writes need the service role.
    supabase_service_role_key: str = ""

    # Cloudflare R2 — where the catalogue *intake* keeps the covers it ingests
    # (services/cover_ingest.py; owner decision 3 Oct 2026, plan §4 option C).
    # Reader uploads, portraits and logos stay in the Supabase bucket above;
    # this is a second store on purpose, because ~12,000 intake covers do not
    # fit Supabase's 1 GB / metered-egress free tier and R2 charges no egress.
    #
    # A bucket of its own, NOT the backup bucket: this one is public by design
    # and that one must never be. The token should be scoped to this bucket
    # alone (Object Read & Write), so the API cannot read a database dump.
    #
    # Optional and dormant when unset, like recs and push (rule 8): without all
    # five the intake promotes only covers the edge proxy already serves and
    # makes no R2 call. `r2_covers_public_url` is the bucket's public origin —
    # its custom domain, e.g. https://covers.kitabi.in — and is what ends up in
    # `editions.cover_url`.
    r2_account_id: str = ""
    r2_access_key_id: str = ""
    r2_secret_access_key: str = ""
    r2_covers_bucket: str = ""
    r2_covers_public_url: str = ""

    # Push notifications (FCM HTTP v1). Optional, opt-in like recs (rule 8): the
    # owner pastes a Firebase Admin service-account JSON here (one string). Unset
    # → push is dormant and every notify call is a no-op, no external request.
    # project_id is read from the JSON, so no separate setting.
    firebase_credentials: str = ""

    @property
    def recommendations_enabled(self) -> bool:
        return bool(self.anthropic_api_key)

    @property
    def extraction_enabled(self) -> bool:
        return bool(self.anthropic_api_key)

    @property
    def push_enabled(self) -> bool:
        return bool(self.firebase_credentials)

    @property
    def jwks_url(self) -> str:
        return f"{self.supabase_url}/auth/v1/.well-known/jwks.json"

    @property
    def jwt_issuer(self) -> str:
        return f"{self.supabase_url}/auth/v1"


@lru_cache
def get_settings() -> Settings:
    return Settings()
