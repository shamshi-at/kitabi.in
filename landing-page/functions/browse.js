// /browse — faceted catalogue browse. noindex, follow.

import { serveBrowse } from './_lib/handler.js';
import { renderBrowse } from './_lib/pages/discover.js';

export function onRequestGet(context) {
  return serveBrowse(context, renderBrowse);
}
