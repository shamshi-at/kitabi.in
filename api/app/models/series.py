"""Series model — a named ordering of Works (Layer-1 catalog).

**A position in a series belongs to the story, not to a printing or to a
language.** Book 3 of Ponniyin Selvan is book 3 in Tamil, in Malayalam and in
English, and it is book 3 whichever publisher printed the copy in your hand. So
membership lives on `Work` (`works.series_id` / `works.series_number`), and
every Work in a translation group carries the same position — the series page
then groups by position and shows the book in the reader's language rather than
listing the same story once per translation (migration 000043).

That replaces the original design, where the number sat on `Edition`: a work
with two editions had two answers to "which book is this?", and the public
series page had to `min()` them to pick one.

The columns here mirror Author/Publisher deliberately — `name_translit` /
`name_fold` so a Malayalam-named series is findable by a Latin query (and the
reverse), `merged_into_id` so duplicate rows fold into a canonical one and keep
their URL alive. Free-text entry created series rows for months; the same merge
machinery that cleans up duplicate authors now covers these.
"""

import uuid

from sqlalchemy import ForeignKey, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CatalogMixin


class Series(CatalogMixin, Base):
    """A named ordering of works (e.g. "Ponniyin Selvan", "Malgudi")."""

    __tablename__ = "series"

    name: Mapped[str] = mapped_column(String, nullable=False, index=True)
    # Public URL segment — /series/malgudi. Assigned once, never recomputed.
    slug: Mapped[str | None] = mapped_column(String, default=None, unique=True, index=True)
    # Set when this row was merged into another as a duplicate — see Publisher.
    merged_into_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("series.id"), default=None, index=True
    )
    # Cross-script search forms of `name` — see Work.title_translit / title_fold.
    name_translit: Mapped[str | None] = mapped_column(String, default=None)
    name_fold: Mapped[str | None] = mapped_column(String, default=None)
    # The language the series was written in. Not "the language of these books":
    # a translated series keeps its original's language here, because that is
    # the fact that doesn't change when someone adds a Malayalam translation.
    primary_language: Mapped[str | None] = mapped_column(String, default=None)
    description: Mapped[str | None] = mapped_column(String, default=None)
    external_source: Mapped[str | None] = mapped_column(String, default=None)
    external_id: Mapped[str | None] = mapped_column(String, default=None, index=True)
