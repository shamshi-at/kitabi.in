// /language/:slug — the most valuable page type on the site. Nobody owns
// "Malayalam novels"; the results today are Wikipedia lists and blogspot posts.

import { serveHub } from './../_lib/handler.js';
import { renderHub } from './../_lib/pages/discover.js';

export function onRequestGet(context) {
  return serveHub(context, 'language', context.params.slug, renderHub);
}
