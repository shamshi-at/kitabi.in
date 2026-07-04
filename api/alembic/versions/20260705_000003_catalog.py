"""Add shared catalog tables (Layer 1).

Authors, publishers, genres, series, works, editions — server-authoritative,
fetched/cached by the app, not user-synced (CLAUDE.md rule 2). RLS enabled
with zero policies on every table (rule 11): only the API touches these.

Revision ID: 000003
Revises: 000002
Create Date: 2026-07-05

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000003"
down_revision: str | None = "000002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _catalog_columns() -> list[sa.Column]:
    return [
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    ]


def _enable_rls(*tables: str) -> None:
    for table in tables:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")


def upgrade() -> None:
    op.create_table(
        "authors",
        *_catalog_columns(),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("bio", sa.String(), nullable=True),
        sa.Column("external_source", sa.String(), nullable=True),
        sa.Column("external_id", sa.String(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_authors_name", "authors", ["name"])
    op.create_index("ix_authors_external_id", "authors", ["external_id"])

    op.create_table(
        "publishers",
        *_catalog_columns(),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("external_source", sa.String(), nullable=True),
        sa.Column("external_id", sa.String(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_publishers_name", "publishers", ["name"])
    op.create_index("ix_publishers_external_id", "publishers", ["external_id"])

    op.create_table(
        "genres",
        *_catalog_columns(),
        sa.Column("name", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index("ix_genres_name", "genres", ["name"])

    op.create_table(
        "series",
        *_catalog_columns(),
        sa.Column("name", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_series_name", "series", ["name"])

    op.create_table(
        "works",
        *_catalog_columns(),
        sa.Column("title", sa.String(), nullable=False),
        sa.Column("subtitle", sa.String(), nullable=True),
        sa.Column("description", sa.String(), nullable=True),
        sa.Column("language", sa.String(), nullable=True),
        sa.Column("first_publish_year", sa.Integer(), nullable=True),
        sa.Column("aggregate_rating", sa.Float(), nullable=True),
        sa.Column("translation_group_id", sa.Uuid(), nullable=True),
        sa.Column("external_source", sa.String(), nullable=True),
        sa.Column("external_id", sa.String(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_works_title", "works", ["title"])
    op.create_index("ix_works_translation_group", "works", ["translation_group_id"])
    op.create_index("ix_works_external_id", "works", ["external_id"])

    op.create_table(
        "editions",
        *_catalog_columns(),
        sa.Column("work_id", sa.Uuid(), sa.ForeignKey("works.id"), nullable=False),
        sa.Column("publisher_id", sa.Uuid(), sa.ForeignKey("publishers.id"), nullable=True),
        sa.Column("series_id", sa.Uuid(), sa.ForeignKey("series.id"), nullable=True),
        sa.Column("series_number", sa.Integer(), nullable=True),
        sa.Column("isbn", sa.String(), nullable=True),
        sa.Column("language", sa.String(), nullable=True),
        sa.Column("page_count", sa.Integer(), nullable=True),
        sa.Column("pub_date", sa.Date(), nullable=True),
        sa.Column("format", sa.String(), nullable=True),
        sa.Column("cover_url", sa.String(), nullable=True),
        sa.Column("external_source", sa.String(), nullable=True),
        sa.Column("external_id", sa.String(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("isbn"),
    )
    op.create_index("ix_editions_work_id", "editions", ["work_id"])
    op.create_index("ix_editions_isbn", "editions", ["isbn"])
    op.create_index("ix_editions_external_id", "editions", ["external_id"])

    op.create_table(
        "work_authors",
        sa.Column("work_id", sa.Uuid(), sa.ForeignKey("works.id"), primary_key=True),
        sa.Column("author_id", sa.Uuid(), sa.ForeignKey("authors.id"), primary_key=True),
    )
    op.create_table(
        "work_genres",
        sa.Column("work_id", sa.Uuid(), sa.ForeignKey("works.id"), primary_key=True),
        sa.Column("genre_id", sa.Uuid(), sa.ForeignKey("genres.id"), primary_key=True),
    )

    _enable_rls(
        "authors",
        "publishers",
        "genres",
        "series",
        "works",
        "editions",
        "work_authors",
        "work_genres",
    )


def downgrade() -> None:
    op.drop_table("work_genres")
    op.drop_table("work_authors")
    op.drop_table("editions")
    op.drop_table("works")
    op.drop_table("series")
    op.drop_table("genres")
    op.drop_table("publishers")
    op.drop_table("authors")
