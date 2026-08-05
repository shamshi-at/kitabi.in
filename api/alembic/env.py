import os
from logging.config import fileConfig
from urllib.parse import urlparse

from sqlalchemy import create_engine, pool

from alembic import context
from app.core.config import get_settings
from app.models.base import Base

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata

# --------------------------------------------------------------------------
# The production guard
# --------------------------------------------------------------------------
#
# `api/.env` points DATABASE_URL at the **Supabase pooler**, not at local
# Postgres — so a bare `alembic upgrade head` in this directory migrates
# PRODUCTION. That is not a hypothetical: it happened on 5 Aug 2026 while
# migration 000041 was being tested locally, and it happened *despite* the
# hazard being written down in STATUS.md. A note in a long file does not stop
# anyone; a process that exits does.
#
# So: migrating a non-local host requires saying so out loud.
#
# The deploy path is unaffected, and deliberately opts in where it is visible
# rather than through a dashboard setting nobody can read from the repo — the
# API's Dockerfile sets ALLOW_PROD_MIGRATION=1, because migrating on boot is
# exactly that container's job (its CMD is `alembic upgrade head && uvicorn …`).
# `tests/test_migration_guard.py` asserts the Dockerfile still carries it, so
# deleting the opt-in fails CI instead of restart-looping production.
ALLOW_ENV_VAR = "ALLOW_PROD_MIGRATION"

# Hosts that are unambiguously a throwaway database: the dev container
# (compose maps 55442), the test container (55443), CI's service container, and
# the Docker-internal aliases. Anything else is treated as real data.
_LOCAL_HOSTS = frozenset(
    {"localhost", "127.0.0.1", "::1", "db", "postgres", "host.docker.internal"}
)


def _is_local(host: str | None) -> bool:
    return (host or "").lower() in _LOCAL_HOSTS


def _guard_against_accidental_production_migration(url: str) -> None:
    if os.environ.get(ALLOW_ENV_VAR) == "1":
        return
    host = urlparse(url).hostname
    if _is_local(host):
        return
    # The host, never the URL — it carries the password.
    raise SystemExit(
        f"\nRefusing to migrate a non-local database: {host}\n\n"
        "DATABASE_URL points somewhere real (api/.env points at the Supabase\n"
        "pooler, which IS production). Pick one:\n\n"
        "  • Local dev DB:  DATABASE_URL=postgresql+asyncpg://postgres:postgres"
        "@localhost:55442/kitabi \\\n"
        "                     .venv/bin/alembic upgrade head\n\n"
        f"  • Really production, on purpose:  {ALLOW_ENV_VAR}=1 "
        ".venv/bin/alembic upgrade head\n\n"
        "Note that pushing to `main` already migrates production on deploy —\n"
        "the API container runs `alembic upgrade head` at boot — so doing it by\n"
        "hand is usually redundant as well as risky.\n"
    )


def _sync_url() -> str:
    """Convert asyncpg URL to psycopg2 for migrations.

    asyncpg (via Supavisor transaction pooling) uses named prepared statements
    that collide across pooled connections. psycopg2 uses the simple query
    protocol with no prepared statements, so it works through any pooler.
    """
    url = get_settings().database_url
    _guard_against_accidental_production_migration(url)
    return url.replace("postgresql+asyncpg://", "postgresql+psycopg2://", 1)


def run_migrations_offline() -> None:
    context.configure(
        url=_sync_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = create_engine(_sync_url(), poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()
    connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
