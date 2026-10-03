"""Prove the R2 covers bucket works, before a night's intake depends on it.

Runs one real cover through the exact code the nightly job uses
(`cover_ingest.ingest`: fetch → shrink → signed upload), then fetches the
result back from the bucket's public URL the way a phone would. Each of the
four things that have to be right is checked separately and named when it is
not: the five `R2_*` settings, the credentials, the bucket, and the public
domain.

It touches no database and creates no catalogue row. It does leave one object
in the bucket — a real, normalised book cover under its content-addressed key,
which the first promotion of that book would have written anyway.

    # with the variables Railway already holds (nothing copied to disk)
    railway run .venv/bin/python scripts/check_cover_storage.py

    # or with the five R2_* values in api/.env
    .venv/bin/python scripts/check_cover_storage.py

    # a different cover
    .venv/bin/python scripts/check_cover_storage.py --cover https://…/front.jpg

Values are never printed — only whether each is present and the right shape.
"""

from __future__ import annotations

import argparse
import asyncio
import io
import logging
import os
import re
import sys

import httpx
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.core.config import get_settings  # noqa: E402
from app.jobs.catalog_intake import USER_AGENT  # noqa: E402
from app.services import cover_ingest, r2_client  # noqa: E402

#: The God of Small Things — the same book the intake tests are written around.
DEFAULT_COVER = "https://covers.openlibrary.org/b/isbn/9780060977498-L.jpg"

_HEX = re.compile(r"^[0-9a-f]+$")

#: name → (what it should look like, a check). Shapes, never values.
_SHAPES = {
    "r2_account_id": ("32 hex characters", lambda v: len(v) == 32 and bool(_HEX.match(v))),
    "r2_access_key_id": ("32 hex characters", lambda v: len(v) == 32 and bool(_HEX.match(v))),
    "r2_secret_access_key": (
        "64 hex characters — the Secret Access Key, not the API token value",
        lambda v: len(v) == 64 and bool(_HEX.match(v)),
    ),
    "r2_covers_bucket": ("a bucket name", lambda v: bool(re.match(r"^[a-z0-9][a-z0-9-]+$", v))),
    "r2_covers_public_url": (
        "https://<the bucket's custom domain>, no path",
        lambda v: bool(re.match(r"^https://[a-z0-9.-]+/?$", v)),
    ),
}


def _check_settings(settings) -> bool:
    ok = True
    for name, (shape, valid) in _SHAPES.items():
        value = (getattr(settings, name) or "").strip()
        if not value:
            print(f"  MISSING  {name.upper()}")
            ok = False
        elif not valid(value):
            print(f"  ODD      {name.upper()} — expected {shape}")
        else:
            print(f"  ok       {name.upper()}")
    return ok


async def _run(cover: str) -> int:
    settings = get_settings()
    print("1. settings")
    if not _check_settings(settings):
        print("\nNot configured: set every R2_* variable and run this again.")
        return 1

    print(f"\n2. ingest  {cover}")
    async with httpx.AsyncClient(timeout=30, headers={"User-Agent": USER_AGENT}) as client:
        result = await cover_ingest.ingest(client, settings, cover, pause=0)
        if result.url is None:
            kind = "the source cover is unusable" if result.gone else "could not complete"
            print(f"  FAILED   {kind}: {result.reason}")
            print("           (an `r2:` line above, if there is one, says why the bucket refused)")
            return 1
        print(f"  ok       stored as {result.url}")

        print("\n3. public URL")
        try:
            public = await client.get(result.url)
        except httpx.HTTPError as exc:
            print(f"  FAILED   {type(exc).__name__} — is the custom domain connected and active?")
            return 1
        if public.status_code != 200:
            print(f"  FAILED   HTTP {public.status_code} from {r2_client.public_base(settings)}")
            print("           The upload worked; the bucket's public domain is not serving it.")
            return 1
        if not result.url.endswith(cover_ingest.object_key(public.content)):
            print("  FAILED   the public URL returned different bytes than were stored")
            return 1
        image = Image.open(io.BytesIO(public.content))
        print(
            f"  ok       {image.format} {image.size[0]}×{image.size[1]}, "
            f"{len(public.content) / 1024:.0f} KB, "
            f"cache-control: {public.headers.get('cache-control', '—')}"
        )

    print("\nCover storage works end to end.")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--cover", default=DEFAULT_COVER, help="source cover URL to ingest")
    args = parser.parse_args()
    # So `r2_client`'s own explanation of a refused upload is visible.
    logging.basicConfig(level=logging.WARNING, format="  %(message)s")
    sys.exit(asyncio.run(_run(args.cover)))


if __name__ == "__main__":
    main()
