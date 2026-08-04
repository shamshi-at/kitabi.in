// /book/:key — the flagship page, server-rendered at the edge.
//
// `key` is a slug ("chemmeen"), or a UUID for rows that never got one — and for
// every /b/<uuid> link already in Google's index, in a share card, or bound to
// the app's universal links. The API resolves both, permanently.

import { servePage } from '../_lib/handler.js';
import { renderBook } from '../_lib/pages/book.js';

export function onRequestGet(context) {
  const key = context.params.key;
  return servePage(context, `/public/book/${encodeURIComponent(key)}`, renderBook, {
    what: 'book',
  });
}
