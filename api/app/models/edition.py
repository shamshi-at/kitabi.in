import uuid
from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import Date, ForeignKey, String, Uuid
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, CatalogMixin

if TYPE_CHECKING:
    from app.models.publisher import Publisher
    from app.models.series import Series
    from app.models.work import Work


class Edition(CatalogMixin, Base):
    """A specific printing/ISBN of a Work (feature-map.md rule 17). Ownership,
    cover, page count, and format attach here, not to the Work — two people
    can own different editions of the same book with different covers.

    `cover_url` is nullable: when null, the app renders a generated "typeset"
    cover from title + author (docs/screen-design.md's cover-treatments
    pattern) rather than a broken-image placeholder.
    """

    __tablename__ = "editions"

    work_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("works.id"), nullable=False)
    publisher_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("publishers.id"), default=None
    )
    series_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("series.id"), default=None)
    series_number: Mapped[int | None] = mapped_column(default=None)

    isbn: Mapped[str | None] = mapped_column(String, unique=True, default=None, index=True)
    language: Mapped[str | None] = mapped_column(String, default=None)
    page_count: Mapped[int | None] = mapped_column(default=None)
    pub_date: Mapped[date | None] = mapped_column(Date, default=None)
    format: Mapped[str | None] = mapped_column(String, default=None)  # paperback/hardcover/ebook
    cover_url: Mapped[str | None] = mapped_column(String, default=None)
    # The back cover — a user can photograph both sides of a book they own. Front
    # (`cover_url`) is what every list/grid renders; `back_cover_url` shows only on
    # the book page. Both nullable; null front falls back to the typeset cover.
    back_cover_url: Mapped[str | None] = mapped_column(String, default=None)
    # [WIRED] Where this edition is available to buy — a list of external
    # retailer links ([{"retailer": "Amazon", "url": ...}, {"retailer":
    # "Flipkart", ...}]). Display-only, per-edition (ISBN-specific), populated
    # later; the book page lists each retailer, dormant while the list is empty.
    buy_links: Mapped[list | None] = mapped_column(JSONB, default=None)

    external_source: Mapped[str | None] = mapped_column(String, default=None)
    external_id: Mapped[str | None] = mapped_column(String, default=None, index=True)

    work: Mapped["Work"] = relationship(back_populates="editions", lazy="joined")
    publisher: Mapped["Publisher | None"] = relationship(lazy="joined")
    series: Mapped["Series | None"] = relationship(lazy="joined")
