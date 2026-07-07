"""Async SQLAlchemy engine and session factory, tuned for the Supavisor
transaction pooler (no statement cache, unique prepared-statement names, warm
recycled pool). `get_db` yields the request-scoped session."""

import uuid
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import get_settings


def _normalize(url: str) -> str:
    """Force the asyncpg driver explicitly. A plain `postgresql://` URL would
    pick asyncpg but skip our pooler-safety connect_args; a `postgres://` URL
    (what Railway/Supabase often hand out) would skip the driver AND the pool
    config in `_engine_kwargs`, silently leaving connections un-pooled and slow
    (every request pays a full cross-region reconnect). Normalize every Postgres
    scheme to postgresql+asyncpg so the pool + connect args always apply."""
    for scheme in ("postgresql+asyncpg://", "postgresql://", "postgres://"):
        if url.startswith(scheme):
            return "postgresql+asyncpg://" + url[len(scheme) :]
    return url


def _engine_kwargs(url: str) -> dict:
    if url.startswith("postgresql+asyncpg"):
        # Supavisor TRANSACTION-mode pooler: no client-side statement caching,
        # and prepared-statement names must be unique per connection attempt or
        # pooled connections collide with DuplicatePreparedStatementError
        # (bit rupee-diary in production, Jun 2026). Keep a warm pool and recycle
        # before Supavisor's idle timeout so requests reuse connections instead
        # of reconnecting across regions on every call.
        return {
            "pool_size": 10,
            "max_overflow": 10,
            "pool_pre_ping": True,
            "pool_recycle": 280,
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
