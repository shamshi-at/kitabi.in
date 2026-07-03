import uuid
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import get_settings


def _normalize(url: str) -> str:
    """Force the asyncpg driver explicitly — a plain postgresql:// URL would
    silently pick asyncpg while skipping our pooler-safety connect_args."""
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+asyncpg://", 1)
    return url


def _engine_kwargs(url: str) -> dict:
    if url.startswith("postgresql+asyncpg"):
        # Supavisor TRANSACTION-mode pooler: no client-side statement caching,
        # and prepared-statement names must be unique per connection attempt or
        # pooled connections collide with DuplicatePreparedStatementError
        # (bit rupee-diary in production, Jun 2026).
        return {
            "pool_size": 5,
            "max_overflow": 5,
            "pool_pre_ping": True,
            "connect_args": {
                "statement_cache_size": 0,
                "prepared_statement_cache_size": 0,
                "prepared_statement_name_func": lambda: f"__asyncpg_{uuid.uuid4()}__",
            },
        }
    return {}


settings = get_settings()
_url = _normalize(settings.database_url)
engine = create_async_engine(_url, **_engine_kwargs(_url))
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_db() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session
