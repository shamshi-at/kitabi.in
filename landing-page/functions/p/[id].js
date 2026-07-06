import { injectOg, fetchEntity } from '../_og.js';

// /p/:id — Open Graph tags for a shared publisher: logo, name, titles count.
export async function onRequest(context) {
  const { params, env, request } = context;
  const id = params.id;
  const url = new URL(request.url);
  const canonical = `https://kitabi.in/p/${encodeURIComponent(id)}`;

  const shell = await env.ASSETS.fetch(new URL('/publisher', url));

  const data = await fetchEntity(`/catalog/publishers/${encodeURIComponent(id)}`);
  const publisher = data && data.publisher;
  if (!publisher) return shell;

  const name = publisher.name || 'Unknown publisher';
  const works = Array.isArray(data.works) ? data.works : [];

  // PublisherOut carries no blurb, so describe by the number of titles.
  const description = works.length
    ? `${works.length} ${works.length === 1 ? 'title' : 'titles'} on Kitabi.`
    : 'A publisher on Kitabi.';

  return injectOg(shell, {
    pageTitle: `${name} — Kitabi`,
    title: name,
    description,
    url: canonical,
    image: publisher.logo_url || null,
  });
}
