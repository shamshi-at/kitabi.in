// / — the front door. Replaces the old launching-soon marketing page: this is
// now the crawl root, and the app pitch is one honest band near the bottom.

import { servePage } from './_lib/handler.js';
import { renderHome } from './_lib/pages/home.js';

export function onRequestGet(context) {
  return servePage(context, '/public/home', renderHome, { what: 'page' });
}
