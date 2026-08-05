// /isbn/:isbn — 301 to the book this ISBN belongs to.
//
// An ISBN is how a book is searched for by someone holding it, and it is how
// every other catalogue links to a book page. Until this route existed the
// number appeared only in a book page's body text: no URL, title or canonical
// carried it, so an ISBN query had nothing of ours to rank. This gives every
// edition an addressable URL that funnels its authority into the canonical
// /book/<slug> page rather than competing with it.
//
// Both ISBN forms work. The reconciliation happens server-side — see
// api/app/services/isbn.py — so /isbn/8126403454 and /isbn/9788126403455 land on
// the same book whichever one the catalogue actually stores.

import { permanentRedirect } from '../_lib/handler.js';
import { cleanIsbn } from '../_lib/isbn.js';
import { fetchPage } from '../_lib/api.js';
import { notFound, unavailable } from '../_lib/layout.js';

export async function onRequestGet(context) {
  const isbn = cleanIsbn(context.params.isbn);
  // Not ISBN-shaped: a real 404 without troubling the origin. This URL is
  // walkable by anyone, so the cheap rejection happens here.
  if (!isbn) return notFound({ what: 'ISBN' });

  const { data, missing } = await fetchPage(`/public/isbn/${encodeURIComponent(isbn)}`);
  if (data?.slug) return permanentRedirect(`/book/${encodeURIComponent(data.slug)}`);

  // The three-way split the whole site holds to: a definite 404 from the API
  // means no such book and should leave the index; anything else is a blip, and
  // a blip must never be reported as "this book is gone" — 503, so the crawler
  // comes back rather than dropping the URL.
  return missing ? notFound({ what: 'ISBN' }) : unavailable();
}
