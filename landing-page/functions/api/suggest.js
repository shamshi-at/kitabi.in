// /api/suggest?q= — the typeahead's data source.
//
// Proxied through our own origin rather than called on api.kitabi.in directly:
// it keeps the browser to a single origin (the CORS policy is GET-only and
// credential-less precisely so the public web never needs a second one), and it
// lets the edge cache a popular prefix.
import { fetchPage } from '../_lib/api.js';

const EMPTY = (q) =>
  new Response(JSON.stringify({ q, suggestions: [] }), {
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });

export async function onRequestGet(context) {
  const q = (new URL(context.request.url).searchParams.get('q') || '').trim().slice(0, 80);
  if (q.length < 2) return EMPTY(q);

  const { data } = await fetchPage(`/public/suggest?q=${encodeURIComponent(q)}`);
  // A failed lookup is an empty list, never an error: the form still works, and
  // a broken dropdown must not make a working site look broken.
  if (!data) return EMPTY(q);
  return new Response(JSON.stringify(data), {
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, max-age=60, s-maxage=300',
    },
  });
}
