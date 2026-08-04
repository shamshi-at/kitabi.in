// /genres — the directory of genre hubs, linked from the header.
import { serveIndex } from './_lib/handler.js';

export function onRequestGet(context) {
  return serveIndex(context, {
    title: 'Genres',
    description: 'Every genre carried by at least one book in the catalogue.',
    kind: 'books',
    field: 'genres',
    prefix: '/genre/',
    canonical: '/genres',
  });
}
