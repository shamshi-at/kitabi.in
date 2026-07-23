import { injectOg, fetchEntity, clamp, notFound } from '../_og.js';

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

  // Unknown book → a real 404 + noindex; API unreachable → the generic shell,
  // unchanged, because a blip must not read to a crawler as "this book is gone".
  const { data, missing } = await fetchEntity(`/catalog/works/${encodeURIComponent(id)}`);
  if (!data || !data.id) return missing ? notFound(shell) : shell;

  const editions = Array.isArray(data.editions) ? data.editions : [];
  const ed = editions.find((e) => e && e.cover_url) || editions[0] || {};
  const authors = Array.isArray(data.authors) ? data.authors : [];
  const authorLine = authors
    .map((a) => a.pen_name || a.name)
    .filter(Boolean)
    .join(', ');

  const title = data.title || 'Untitled';

  // schema.org Book for search engines — only fields the API actually
  // returned; null/empty fields are omitted entirely.
  const jsonLd = { '@context': 'https://schema.org', '@type': 'Book', name: title };
  const authorNames = authors.map((a) => a.pen_name || a.name).filter(Boolean);
  if (authorNames.length) {
    jsonLd.author = authorNames.map((n) => ({ '@type': 'Person', name: n }));
  }
  if (data.language) jsonLd.inLanguage = data.language;
  if (data.first_publish_year) jsonLd.datePublished = String(data.first_publish_year);
  if (data.description) jsonLd.description = clamp(data.description, 500);
  if (ed.cover_url) jsonLd.image = ed.cover_url;
  const FORMATS = {
    paperback: 'https://schema.org/Paperback',
    hardcover: 'https://schema.org/Hardcover',
    ebook: 'https://schema.org/EBook',
  };
  const workExample = editions
    .map((e) => {
      if (!e) return null;
      const ex = { '@type': 'Book' };
      if (e.isbn) ex.isbn = e.isbn;
      if (e.page_count) ex.numberOfPages = e.page_count;
      const key = String(e.format || '').toLowerCase();
      const format = Object.hasOwn(FORMATS, key) ? FORMATS[key] : null;
      if (format) ex.bookFormat = format;
      if (e.publisher && e.publisher.name) {
        ex.publisher = { '@type': 'Organization', name: e.publisher.name };
      }
      return Object.keys(ex).length > 1 ? ex : null; // nothing beyond @type → skip
    })
    .filter(Boolean);
  if (workExample.length) jsonLd.workExample = workExample;

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
    canonical,
    jsonLd,
  });
}
