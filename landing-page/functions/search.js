// /search — server-rendered results. Works with JavaScript disabled: the header
// form is a plain GET, and nothing here needs a script to appear.

import { serveSearch } from './_lib/handler.js';
import { renderSearch } from './_lib/pages/discover.js';

export function onRequestGet(context) {
  return serveSearch(context, renderSearch);
}
