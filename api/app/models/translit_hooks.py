"""Keeps the cross-script search columns in sync with their source text.

SQLAlchemy `before_insert`/`before_update` events — rather than explicit calls
sprinkled through the services — so *every* write path (manual add/edit forms,
OpenLibrary cache-on-first-use, CSV import, future seeds) maintains
`title_translit`/`name_translit` without having to remember to.

Imported for its side effects from `app.models` (which everything that touches
the ORM already imports).
"""

from sqlalchemy import event

from app.models.author import Author
from app.models.publisher import Publisher
from app.models.work import Work
from app.services.translit import transliterate


@event.listens_for(Work, "before_insert")
@event.listens_for(Work, "before_update")
def _work_translit(mapper, connection, target: Work) -> None:  # noqa: ANN001
    target.title_translit = transliterate(target.title)


@event.listens_for(Author, "before_insert")
@event.listens_for(Author, "before_update")
def _author_translit(mapper, connection, target: Author) -> None:  # noqa: ANN001
    target.name_translit = transliterate(target.name)


@event.listens_for(Publisher, "before_insert")
@event.listens_for(Publisher, "before_update")
def _publisher_translit(mapper, connection, target: Publisher) -> None:  # noqa: ANN001
    target.name_translit = transliterate(target.name)
