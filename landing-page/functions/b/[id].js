import { injectOg, fetchEntity, clamp } from '../_og.js';

// /b/:id — inject real Open Graph tags for a shared book so link previews show
// the cover, title (+ author) and a short blurb. Humans still get book.html and
// its client-side render; bots read the head we rewrite here.
export async function onRequest(context) {
  const { params, env, request } = context;
  const id = params.id;
  const url = new URL(request.url);
  const canonical = `https://kitabi.in/b/${encodeURIComponent(id)}`;

  // Start from the static shell — it's what humans get and what we rewrite.
  const shell = await env.ASSETS.fetch(new URL('/book', url));

  const data = await fetchEntity(`/catalog/works/${encodeURIComponent(id)}`);
  if (!data || !data.id) return shell; // unknown/unavailable → generic preview

  const editions = Array.isArray(data.editions) ? data.editions : [];
  const ed = editions.find((e) => e && e.cover_url) || editions[0] || {};
  const authors = Array.isArray(data.authors) ? data.authors : [];
  const authorLine = authors
    .map((a) => a.pen_name || a.name)
    .filter(Boolean)
    .join(', ');

  const title = data.title || 'Untitled';

  // Prefer the real blurb; otherwise assemble author · publisher · year context.
  let description = data.description ? clamp(data.description, 200) : '';
  if (!description) {
    const bits = [];
    if (authorLine) bits.push(`by ${authorLine}`);
    if (ed.publisher && ed.publisher.name) bits.push(ed.publisher.name);
    if (data.first_publish_year) bits.push(String(data.first_publish_year));
    description = bits.length ? bits.join(' · ') : 'Track, lend, and share your library on Kitabi.';
  }

  return injectOg(shell, {
    pageTitle: `${title} — Kitabi`,
    title: authorLine ? `${title} — ${authorLine}` : title,
    description,
    url: canonical,
    image: ed.cover_url || null,
  });
}
