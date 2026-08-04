// /p/:uuid — legacy publisher share URL. 301 to the canonical slug URL, kept
// forever; see functions/b/[id].js for why.

import { legacyRedirect } from '../_lib/handler.js';

export function onRequestGet(context) {
  return legacyRedirect(context, 'publisher', context.params.id);
}
