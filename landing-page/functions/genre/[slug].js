// /genre/:slug — same template as the language hub, different filter.

import { serveHub } from './../_lib/handler.js';
import { renderHub } from './../_lib/pages/discover.js';

export function onRequestGet(context) {
  return serveHub(context, 'genre', context.params.slug, renderHub);
}
