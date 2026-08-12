"""The pre-launch wipe (`scripts/reset_user_data.py`) classifies every table as
either reader data (deleted) or catalog/admin (kept). A table added later and
classified as neither is the failure this guards: it would silently survive a
wipe that is supposed to leave no reader data behind.

Pure — no database. It compares the script's lists against SQLAlchemy metadata.
"""

import importlib.util
from pathlib import Path

from app.models.base import Base, SyncableMixin

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "reset_user_data.py"


def _load():
    spec = importlib.util.spec_from_file_location("reset_user_data", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_every_table_is_classified() -> None:
    mod = _load()
    classified = set(mod.USER_TABLES) | set(mod.KEPT_TABLES)
    for extra in mod.OPTIONAL.values():
        classified |= set(extra)

    unclassified = sorted(set(Base.metadata.tables) - classified)
    assert not unclassified, (
        "tables the wipe neither deletes nor knowingly keeps: "
        f"{unclassified} — add them to USER_TABLES or KEPT_TABLES in {SCRIPT.name}"
    )


def test_every_syncable_table_is_deleted() -> None:
    """Anything carrying `SyncableMixin` is by definition one reader's data
    (CLAUDE.md rule 10), so it must be in the delete list, not merely known."""
    mod = _load()
    syncable = {
        m.class_.__tablename__ for m in Base.registry.mappers if issubclass(m.class_, SyncableMixin)
    }
    missing = sorted(syncable - set(mod.USER_TABLES))
    assert not missing, f"syncable (per-reader) tables missing from the wipe: {missing}"


def test_catalog_tables_are_never_deleted() -> None:
    mod = _load()
    catalog = {
        "works",
        "editions",
        "authors",
        "publishers",
        "series",
        "genres",
        "work_authors",
        "work_genres",
        "work_translators",
    }
    optional = {t for extra in mod.OPTIONAL.values() for t in extra}
    assert not catalog & set(mod.USER_TABLES)
    assert not catalog & optional
    assert catalog <= set(mod.KEPT_TABLES)


def test_children_are_deleted_before_their_parents() -> None:
    """The delete list is ordered by hand; a wrong order is an FK violation
    partway through the transaction, i.e. a wipe that rolls back at 3am."""
    mod = _load()
    order = {t: i for i, t in enumerate(mod.USER_TABLES)}
    for name, table in Base.metadata.tables.items():
        if name not in order:
            continue
        for fk in table.foreign_keys:
            parent = fk.column.table.name
            if parent in order and parent != name:
                assert (
                    order[name] < order[parent]
                ), f"{name} references {parent} but is deleted after it"
