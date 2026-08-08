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
    # The circuit breaker: total paid calls across ALL readers in one UTC day.
    # This is the number that actually bounds the bill — the per-reader caps
    # only stop one account from being the whole problem.
    llm_daily_global_cap: int = 1000

    # Affiliate ids for the generated buy links (services/buy_links.py —
    # docs/revenue-plan.md §3.1). Plain URL parameters, not API credentials
    # (rule 8): unset means the links render untagged and earn nothing, so the
    # feature ships dormant and the owner flips revenue on by setting the tag
    # in Railway after the Associates account is approved.
    amazon_associate_tag: str = ""
    # Flipkart closed its direct affiliate programme to new publishers, so
    # `flipkart_affiliate_id` (the legacy `affid=`) is here for the case this
    # account ever gets direct access; the reachable route is Cuelinks, whose
    # Link Kit is a redirect wrapper rather than a parameter — hence a separate
    # setting. Direct wins over the aggregator when both are set.
    flipkart_affiliate_id: str = ""
    cuelinks_cid: str = ""

    # Supabase Storage writes (the `covers` bucket the app and admin console
    # already use). Needed only by the cover backfill job, which copies
    # hotlinked catalogue covers into a bucket we own — a cache is not
    # ownership. Optional and dormant when unset, like recs and push (rule 8):
    # no key means the job no-ops and makes no external call. The anon key is
    # not enough; Storage writes need the service role.
    supabase_service_role_key: str = ""

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
