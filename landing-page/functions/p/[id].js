import { injectOg, fetchEntity, notFound } from '../_og.js';

// /p/:id — Open Graph tags for a shared publisher: logo, name, titles count.
export async function onRequest(context) {
  const { params, env, request } = context;
  const id = params.id;
  const url = new URL(request.url);
  const canonical = `https://kitabi.in/p/${encodeURIComponent(id)}`;

  const shell = await env.ASSETS.fetch(new URL('/publisher', url));

  const { data, missing } = await fetchEntity(`/catalog/publishers/${encodeURIComponent(id)}`);
  const publisher = data && data.publisher;
  if (!publisher) return missing ? notFound(shell) : shell;

  const name = publisher.name || 'Unknown publisher';
  const works = Array.isArray(data.works) ? data.works : [];

  // PublisherOut carries no blurb, so describe by the number of titles.
  const description = works.length
    ? `${works.length} ${works.length === 1 ? 'title' : 'titles'} on Kitabi.`
    : 'A publisher on Kitabi.';

  // schema.org Organization for search engines — logo only when present.
  const jsonLd = { '@context': 'https://schema.org', '@type': 'Organization', name };
  if (publisher.logo_url) jsonLd.logo = publisher.logo_url;

  return injectOg(shell, {
    pageTitle: `${name} — Kitabi`,
    title: name,
    description,
    url: canonical,
    image: publisher.logo_url || null,
    canonical,
    jsonLd,
  });
}
