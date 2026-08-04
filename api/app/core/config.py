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
