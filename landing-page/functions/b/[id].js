// /b/:uuid — the original share URL. Now a 301 to the canonical slug URL.
//
// This route is NEVER removed. It is in Google's index, in every share card ever
// generated, and — the one that would actually break people — bound to the app's
// universal links via .well-known/apple-app-site-association, which iOS only
// re-evaluates at install. Deleting it would orphan every installed app.
//
// /book/* was added to the association files in the same change as this
// redirect, and deliberately ahead of it.

import { legacyRedirect } from '../_lib/handler.js';

export function onRequestGet(context) {
  return legacyRedirect(context, 'book', context.params.id);
}
