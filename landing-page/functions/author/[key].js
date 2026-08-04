// /author/:key — server-rendered. Slug or UUID, same as /book.

import { servePage } from '../_lib/handler.js';
import { renderAuthor } from '../_lib/pages/people.js';

export function onRequestGet(context) {
  const key = context.params.key;
  return servePage(context, `/public/author/${encodeURIComponent(key)}`, renderAuthor, {
    what: 'author',
  });
}
