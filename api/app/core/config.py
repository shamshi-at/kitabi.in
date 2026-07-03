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

    # CORS: the mobile app needs none; only a web origin would go here.
    cors_origins: list[str] = []

    scheduler_enabled: bool = False

    @property
    def jwks_url(self) -> str:
        return f"{self.supabase_url}/auth/v1/.well-known/jwks.json"

    @property
    def jwt_issuer(self) -> str:
        return f"{self.supabase_url}/auth/v1"


@lru_cache
def get_settings() -> Settings:
    return Settings()
