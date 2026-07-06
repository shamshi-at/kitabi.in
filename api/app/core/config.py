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

    @property
    def recommendations_enabled(self) -> bool:
        return bool(self.anthropic_api_key)

    @property
    def jwks_url(self) -> str:
        return f"{self.supabase_url}/auth/v1/.well-known/jwks.json"

    @property
    def jwt_issuer(self) -> str:
        return f"{self.supabase_url}/auth/v1"


@lru_cache
def get_settings() -> Settings:
    return Settings()
