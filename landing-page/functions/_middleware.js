// Runs before every route on this project. Keep it to things that must apply
// site-wide — a route file cannot do this job, because named routes
// (/author/[key].js and friends) never reach the [[path]] catch-all.
//
// The logic lives in _lib/host.js so it is testable; this file is the wiring.

import { canonicalHostUrl } from './_lib/host.js';

export async function onRequest(context) {
  // 301 rather than 302: this is permanent, and only a permanent redirect
  // transfers link equity and gets cached by the browser.
  const canonical = canonicalHostUrl(context.request.url);
  if (canonical) return Response.redirect(canonical, 301);
  return context.next();
}
