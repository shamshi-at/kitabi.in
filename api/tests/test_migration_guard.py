"""The guard that stops a local `alembic upgrade head` from migrating production.

`api/.env` points DATABASE_URL at the Supabase pooler, so a bare alembic run in
this directory migrates the live database. That happened on 5 Aug 2026 (migration
000041), *despite* the hazard being documented — which is the whole argument for
a process that exits over a note in a file.

These tests pull the guard out of `alembic/env.py` by source rather than
importing it: importing env.py executes the migration run itself. The file is
tiny and the extracted names are asserted to exist, so a rename fails loudly here
instead of silently testing nothing.
"""

import re
from pathlib import Path

import pytest

API_DIR = Path(__file__).resolve().parents[1]
ENV_PY = API_DIR / "alembic" / "env.py"
DOCKERFILE = API_DIR / "Dockerfile"


def _load_guard():
    """Exec just the guard's own definitions, with no alembic context."""
    source = ENV_PY.read_text()
    start = source.index("ALLOW_ENV_VAR =")
    end = source.index("def _sync_url()")
    namespace: dict = {}
    exec(  # noqa: S102 — our own source, extracted deliberately
        "import os\nfrom urllib.parse import urlparse\n" + source[start:end], namespace
    )
    for name in ("ALLOW_ENV_VAR", "_is_local", "_guard_against_accidental_production_migration"):
        assert name in namespace, f"{name} vanished from env.py — this test is now vacuous"
    return namespace


GUARD = _load_guard()


@pytest.mark.parametrize(
    "url",
    [
        "postgresql+asyncpg://postgres:postgres@localhost:55442/kitabi",
        "postgresql+asyncpg://postgres:postgres@localhost:55443/test",
        "postgresql+asyncpg://postgres:postgres@127.0.0.1:5432/test",
        "postgresql+asyncpg://postgres:postgres@db:5432/kitabi",  # compose service
        "postgresql+asyncpg://postgres:postgres@postgres:5432/test",  # CI service
    ],
)
def test_local_databases_migrate_freely(url, monkeypatch):
    """The everyday path must stay frictionless, or the guard gets removed."""
    monkeypatch.delenv(GUARD["ALLOW_ENV_VAR"], raising=False)
    GUARD["_guard_against_accidental_production_migration"](url)  # must not raise


def test_the_real_production_url_shape_is_refused(monkeypatch):
    """The exact URL shape that was actually migrated by accident."""
    monkeypatch.delenv(GUARD["ALLOW_ENV_VAR"], raising=False)
    url = (
        "postgresql+asyncpg://postgres.lwyifccwirfmgdvemgkz:hunter2"
        "@aws-1-ap-southeast-1.pooler.supabase.com:6543/postgres"
    )
    with pytest.raises(SystemExit) as excinfo:
        GUARD["_guard_against_accidental_production_migration"](url)

    message = str(excinfo.value)
    assert "aws-1-ap-southeast-1.pooler.supabase.com" in message, "say which host was refused"
    assert "hunter2" not in message, "an error message must never echo the password"
    assert "ALLOW_PROD_MIGRATION=1" in message, "an unactionable refusal just gets worked around"


def test_the_opt_in_lets_a_deliberate_production_migration_through(monkeypatch):
    monkeypatch.setenv(GUARD["ALLOW_ENV_VAR"], "1")
    GUARD["_guard_against_accidental_production_migration"](
        "postgresql+asyncpg://u:p@aws-1-ap-southeast-1.pooler.supabase.com:6543/postgres"
    )


@pytest.mark.parametrize("value", ["", "0", "true", "yes", "TRUE"])
def test_only_an_exact_1_opts_in(value, monkeypatch):
    """Anything looser and a stray `ALLOW_PROD_MIGRATION=false` in a shell
    profile reads as permission."""
    monkeypatch.setenv(GUARD["ALLOW_ENV_VAR"], value)
    with pytest.raises(SystemExit):
        GUARD["_guard_against_accidental_production_migration"](
            "postgresql+asyncpg://u:p@some.remote.host:5432/postgres"
        )


def test_a_password_containing_an_at_sign_does_not_defeat_the_host_check(monkeypatch):
    """urlparse splits netloc on the LAST '@'. If it split on the first, the
    parsed host would be garbage and the guard could pass a remote URL."""
    monkeypatch.delenv(GUARD["ALLOW_ENV_VAR"], raising=False)
    with pytest.raises(SystemExit):
        GUARD["_guard_against_accidental_production_migration"](
            "postgresql+asyncpg://user:p@ss@w0rd@real.production.host:5432/db"
        )
    # …and the same trick must not make a local URL look remote either.
    GUARD["_guard_against_accidental_production_migration"](
        "postgresql+asyncpg://user:p@ss@localhost:55442/kitabi"
    )


def test_an_unparseable_url_is_refused_not_waved_through(monkeypatch):
    """Fail closed: if the host can't be determined, it is not known to be local."""
    monkeypatch.delenv(GUARD["ALLOW_ENV_VAR"], raising=False)
    for url in ("", "not a url", "postgresql+asyncpg:///var/run/postgres"):
        with pytest.raises(SystemExit):
            GUARD["_guard_against_accidental_production_migration"](url)


def test_the_container_still_opts_in():
    """THE load-bearing assertion. The API container migrates on boot, so if the
    Dockerfile loses this line the guard refuses at startup, the CMD fails, the
    health check fails, and Railway restart-loops production. Failing here is
    how that gets caught in CI instead of in production."""
    dockerfile = DOCKERFILE.read_text()
    assert re.search(r"^ENV ALLOW_PROD_MIGRATION=1$", dockerfile, re.MULTILINE), (
        "api/Dockerfile must set ALLOW_PROD_MIGRATION=1 — the container's CMD runs "
        "`alembic upgrade head` against the production database at boot."
    )
    # And the premise that makes it load-bearing.
    assert "alembic upgrade head" in dockerfile
