"""Test infrastructure: real Postgres (full fidelity — Identity, RLS, advisory
locks). Locally a throwaway container is started per session; CI provides
TEST_DATABASE_URL via a service container. Schema comes from the actual
Alembic migrations, so they are exercised on every test run."""

import os
import subprocess
import sys
import time
import uuid
from collections.abc import AsyncIterator
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app

API_DIR = Path(__file__).resolve().parents[1]
CONTAINER = "kitabi-test-pg"
# Port 55443 — clear of rupee-diary's test container (55433) and both dev DBs.
LOCAL_URL = "postgresql+asyncpg://postgres:test@localhost:55443/test"
# Syncable tables to truncate between tests — extend as models land.
TABLES: list[str] = []


def _wait_for_pg() -> None:
    for _ in range(60):
        probe = subprocess.run(
            ["docker", "exec", CONTAINER, "pg_isready", "-U", "postgres"],
            capture_output=True,
        )
        if probe.returncode == 0:
            time.sleep(0.3)  # pg_isready can race the actual accept loop
            return
        time.sleep(0.5)
    raise RuntimeError("test postgres did not become ready")


@pytest.fixture(scope="session")
def database_url() -> str:
    url = os.environ.get("TEST_DATABASE_URL")
    started = False
    if url is None:
        subprocess.run(["docker", "rm", "-f", CONTAINER], capture_output=True)
        subprocess.run(
            [
                "docker",
                "run",
                "--rm",
                "-d",
                "--name",
                CONTAINER,
                "-p",
                "55443:5432",
                "-e",
                "POSTGRES_PASSWORD=test",
                "-e",
                "POSTGRES_DB=test",
                "postgres:17-alpine",
            ],
            check=True,
            capture_output=True,
        )
        _wait_for_pg()
        url, started = LOCAL_URL, True

    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        env={**os.environ, "DATABASE_URL": url},
        cwd=API_DIR,
        check=True,
        capture_output=True,
    )
    yield url
    if started:
        subprocess.run(["docker", "rm", "-f", CONTAINER], capture_output=True)


@pytest.fixture
async def db_sessionmaker(database_url):
    engine = create_async_engine(database_url, poolclass=NullPool)
    if TABLES:
        async with engine.begin() as conn:
            await conn.execute(text(f"TRUNCATE {', '.join(TABLES)} RESTART IDENTITY CASCADE"))
    yield async_sessionmaker(engine, expire_on_commit=False)
    await engine.dispose()


@pytest.fixture
def user() -> dict:
    return {"id": str(uuid.uuid4()), "email": "tester@example.com"}


@pytest.fixture
async def client(db_sessionmaker, user) -> AsyncIterator[AsyncClient]:
    app = create_app()

    async def override_db():
        async with db_sessionmaker() as session:
            yield session

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = lambda: user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
