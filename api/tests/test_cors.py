"""CORS is scoped to exactly what kitabi.in's public share pages do: read-only,
unauthenticated GETs. These are the guards that keep it that way — the previous
policy advertised every method to every browser and allowed credentials.

CORS is a browser policy, not access control (curl ignores it). What it bounds
is what a *hostile web page* can make a reader's browser do on their behalf.
"""

from app.core.config import get_settings

ORIGIN = "https://kitabi.in"
_PUBLIC = "/catalog/browse/languages"


async def test_a_public_get_from_kitabi_in_is_allowed(client):
    """The share pages fetch the catalog from the browser, so this must work
    until they're edge-rendered."""
    resp = await client.get(_PUBLIC, headers={"Origin": ORIGIN})
    assert resp.status_code == 200
    assert resp.headers["access-control-allow-origin"] == ORIGIN


async def test_credentials_are_never_allowed(client):
    """`Access-Control-Allow-Credentials` is what lets a cross-origin page read
    a response with the reader's cookies attached. Nothing on the public web
    signs in, so it must never be advertised."""
    resp = await client.get(_PUBLIC, headers={"Origin": ORIGIN})
    assert "access-control-allow-credentials" not in resp.headers


async def test_an_unknown_origin_gets_no_cors_grant(client):
    resp = await client.get(_PUBLIC, headers={"Origin": "https://evil.test"})
    assert "access-control-allow-origin" not in resp.headers


async def test_write_methods_are_not_offered_to_browsers(client):
    """The public web is strictly read-only (plan rule 2). A preflight asking
    to POST cross-origin must be refused, not answered with a grant."""
    resp = await client.options(
        "/catalog/works",
        headers={
            "Origin": ORIGIN,
            "Access-Control-Request-Method": "POST",
        },
    )
    assert "POST" not in resp.headers.get("access-control-allow-methods", "")


async def test_a_get_preflight_is_still_answered(client):
    resp = await client.options(
        _PUBLIC,
        headers={"Origin": ORIGIN, "Access-Control-Request-Method": "GET"},
    )
    assert resp.status_code == 200
    assert "GET" in resp.headers["access-control-allow-methods"]


async def test_authorization_is_not_an_allowed_cross_origin_header(client):
    """Dropping it enforces "the public web never carries a token" at the
    transport layer rather than trusting that nobody adds one later."""
    resp = await client.options(
        _PUBLIC,
        headers={
            "Origin": ORIGIN,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )
    assert "authorization" not in resp.headers.get("access-control-allow-headers", "").lower()


def test_the_allowed_origins_are_kitabi_in_only():
    """A stray origin here would undo every test above, and it's a one-line
    env change in production — so assert the shape, not just the behaviour."""
    for origin in get_settings().cors_origins:
        assert origin.startswith("https://")
        assert origin.endswith("kitabi.in")
