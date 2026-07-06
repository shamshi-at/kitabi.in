import { injectOg, fetchEntity, clamp } from '../_og.js';

// /a/:id — Open Graph tags for a shared author: portrait, name, works count.
export async function onRequest(context) {
  const { params, env, request } = context;
  const id = params.id;
  const url = new URL(request.url);
  const canonical = `https://kitabi.in/a/${encodeURIComponent(id)}`;

  const shell = await env.ASSETS.fetch(new URL('/author', url));

  const data = await fetchEntity(`/catalog/authors/${encodeURIComponent(id)}`);
  const author = data && data.author;
  if (!author) return shell;

  const name = author.name || 'Unknown author';
  const works = Array.isArray(data.works) ? data.works : [];

  let description = author.bio ? clamp(author.bio, 200) : '';
  if (!description) {
    description = works.length
      ? `${works.length} ${works.length === 1 ? 'work' : 'works'} on Kitabi.`
      : 'An author on Kitabi.';
  }

  return injectOg(shell, {
    pageTitle: `${name} — Kitabi`,
    title: name,
    description,
    url: canonical,
    image: author.image_url || null,
  });
}
