// /publisher/:key — server-rendered. Slug or UUID, same as /book.

import { servePage } from '../_lib/handler.js';
import { renderPublisher } from '../_lib/pages/people.js';

export function onRequestGet(context) {
  const key = context.params.key;
  return servePage(context, `/public/publisher/${encodeURIComponent(key)}`, renderPublisher, {
    what: 'publisher',
    mergedFrom: { kind: 'publisher', key },
  });
}
