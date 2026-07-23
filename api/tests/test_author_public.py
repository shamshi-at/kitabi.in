"""The author detail endpoint is public, but withholds the reader's identity.

kitabi.in/a/:id builds its share preview and schema.org JSON-LD from an
anonymous fetch of this endpoint, so requiring a bearer token here silently
broke every author link (found 23 Jul 2026). It is public now — with one
carve-out: `linked_user_id` is a Supabase user id, so anonymous callers never
see it, and a pending claim stays visible only to the reader who filed it.
"""

import uuid

from app.models import Author


async def _author(db_sessionmaker, name: str = "Thakazhi Sivasankara Pillai") -> Author:
    async with db_sessionmaker() as session:
        author = Author(name=name)
        session.add(author)
        await session.commit()
        await session.refresh(author)
        return author


async def test_anonymous_can_read_an_author(unauthenticated_client, db_sessionmaker):
    author = await _author(db_sessionmaker)

    resp = await unauthenticated_client.get(f"/catalog/authors/{author.id}")

    assert resp.status_code == 200
    assert resp.json()["author"]["name"] == "Thakazhi Sivasankara Pillai"


async def test_anonymous_never_sees_linked_user_id(unauthenticated_client, db_sessionmaker):
    linked = uuid.uuid4()
    async with db_sessionmaker() as session:
        author = Author(name="Kamala Das", linked_user_id=linked)
        session.add(author)
        await session.commit()
        await session.refresh(author)

    body = (await unauthenticated_client.get(f"/catalog/authors/{author.id}")).json()

    # The link exists in the row; it just isn't published to crawlers.
    assert body["author"]["linked_user_id"] is None
    assert body["author"]["claim_pending"] is False


async def test_signed_in_reader_still_sees_linked_user_id(client, db_sessionmaker):
    linked = uuid.uuid4()
    async with db_sessionmaker() as session:
        author = Author(name="M.T. Vasudevan Nair", linked_user_id=linked)
        session.add(author)
        await session.commit()
        await session.refresh(author)

    body = (await client.get(f"/catalog/authors/{author.id}")).json()

    assert body["author"]["linked_user_id"] == str(linked)


async def test_unknown_author_is_404_for_anonymous(unauthenticated_client):
    resp = await unauthenticated_client.get(f"/catalog/authors/{uuid.uuid4()}")

    assert resp.status_code == 404
    assert resp.json()["code"] == "not_found"


async def test_a_broken_token_still_401s(unauthenticated_client, db_sessionmaker):
    """Present-but-invalid is a broken client, not an anonymous visitor —
    downgrading it to anonymous would hide the app's own auth failures."""
    author = await _author(db_sessionmaker, "Vaikom Muhammad Basheer")

    resp = await unauthenticated_client.get(
        f"/catalog/authors/{author.id}", headers={"Authorization": "Bearer not-a-real-jwt"}
    )

    assert resp.status_code == 401
    assert resp.json()["code"] == "unauthorized"
