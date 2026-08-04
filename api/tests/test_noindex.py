"""api.kitabi.in must never be indexed — and must never take kitabi.in with it.

The second half is the point. A blanket `noindex` on the API is only safe
because the edge builds fresh response headers instead of forwarding the
origin's; if that ever changes, the public site silently leaves Google's index
and nothing else fails. `test_edge_never_forwards_origin_headers` reads the
actual edge source so the assumption is checked rather than remembered.
"""

import re
from pathlib import Path

from app.core.noindex import ROBOTS_HEADER, ROBOTS_TXT

_EDGE = Path(__file__).resolve().parents[2] / "landing-page" / "functions"


async def test_robots_txt_is_served_and_disallows_everything(client):
    res = await client.get("/robots.txt")
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("text/plain")
    assert "Disallow: /" in res.text


def test_robots_txt_still_allows_well_known():
    # Apple fetches apple-app-site-association to validate universal links; a
    # Disallow that swallowed it would break the app's deep links.
    assert "Allow: /.well-known/" in ROBOTS_TXT
    assert ROBOTS_TXT.index("Allow: /.well-known/") < ROBOTS_TXT.index("Disallow: /")


async def test_every_api_response_carries_the_noindex_header(client):
    for path in ["/healthz", "/robots.txt", "/definitely-not-a-route"]:
        res = await client.get(path)
        assert res.headers.get("X-Robots-Tag") == ROBOTS_HEADER, path


async def test_error_responses_carry_it_too(client):
    # A 404/422 body leaks endpoint shapes; it must not be indexable either.
    res = await client.get("/catalog/works/not-a-uuid")
    assert res.status_code >= 400
    assert res.headers.get("X-Robots-Tag") == ROBOTS_HEADER


async def test_well_known_is_exempt(client):
    res = await client.get("/.well-known/apple-app-site-association")
    assert "X-Robots-Tag" not in res.headers


def _response_header_literal(source: str) -> str:
    """The `headers: { … }` block of the `new Response(upstream.body, …)` call.

    Reading `upstream.headers` elsewhere is fine and expected — the cover proxy
    inspects the upstream content-type to reject non-images. What must never
    happen is upstream headers ending up *on the response we return*.
    """
    call = source[source.index("new Response(upstream.body") :]
    match = re.search(r"headers:\s*\{", call)
    assert match, "no headers literal on the new Response call"
    start = match.end() - 1
    depth, i = 0, start
    while i < len(call):
        if call[i] == "{":
            depth += 1
        elif call[i] == "}":
            depth -= 1
            if depth == 0:
                return call[start : i + 1]
        i += 1
    raise AssertionError("unbalanced headers literal")


def test_edge_never_forwards_origin_headers():
    """The guard that makes the API's blanket noindex safe.

    Both edge handlers stream an API response body through to the reader. The
    headers they return must be built from scratch — if either ever passed the
    upstream's headers along, the API's `noindex` would land on a kitabi.in
    response and quietly deindex the public site.
    """
    for rel in [Path("sitemaps") / "[name].js", Path("img") / "c.js"]:
        source = (_EDGE / rel).read_text()
        assert "new Response(upstream.body" in source, f"test is pointed at the wrong file: {rel}"
        literal = _response_header_literal(source)
        assert "upstream" not in literal, f"{rel} forwards upstream headers: {literal}"
        assert "X-Robots-Tag" not in literal, f"{rel} sets X-Robots-Tag: {literal}"
        # A wholesale copy would bypass the literal check entirely.
        assert "new Headers(upstream" not in source, rel


def test_no_public_page_emits_an_api_host_url():
    """`Disallow: /` on api.kitabi.in is only free if nothing public points there.

    If a renderer ever emitted an api.kitabi.in URL — a cover, a link, an embed
    — crawlers would be told not to fetch it and that asset would drop out of
    search. Covers go through /img/c on our own host precisely so this holds.
    Server-to-server fetch bases are fine; URLs written into HTML are not.
    """
    offenders = []
    for path in sorted(_EDGE.rglob("*.js")):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if "api.kitabi.in" not in line:
                continue
            stripped = line.strip()
            if stripped.startswith(("//", "*", "/*")):
                continue  # a comment
            if re.match(r"const\s+\w*API\w*\s*=", stripped):
                continue  # the fetch base — server-to-server, never rendered
            offenders.append(f"{path.relative_to(_EDGE)}:{number}: {stripped}")
    assert not offenders, "public pages must not emit api.kitabi.in URLs:\n" + "\n".join(offenders)
