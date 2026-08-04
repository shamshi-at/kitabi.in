// /language/:slug/:form — e.g. /language/malayalam/novels.
//
// Sub-hubs multiply the indexable surface honestly: ~6 real pages per language,
// each targeting a query someone actually types, all built from data that
// already exists.

import { serveHub } from '../../_lib/handler.js';
import { renderHub } from '../../_lib/pages/discover.js';

export function onRequestGet(context) {
  const { slug, form } = context.params;
  return serveHub(context, 'language', slug, renderHub, { form });
}
