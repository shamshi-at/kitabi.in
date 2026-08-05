// Catch-all: a real 404 for anything no route and no asset matches.
//
// 404.html alone was not enough. Cloudflare Pages served its CONTENT for an
// unmatched path but with an HTTP 200 — the page said "not found" while the
// status line said "here you go". That is a soft 404, and it is the version of
// this bug that is hardest to notice, because the page looks right.
//
// ⚠️ A `[[path]]` catch-all runs BEFORE static assets, so this file can take the
// whole site down if it gets the pass-through wrong. Everything the site serves
// as a file is listed explicitly below and handed to env.ASSETS; anything else
// 404s. An allowlist rather than a heuristic, because the cost of a mistake is
// asymmetric: a missing font is cosmetic, but a missing
// /.well-known/apple-app-site-association silently breaks universal links for
// every installed app, and iOS only re-checks that at install.

import { servePage } from './_lib/handler.js';
import { notFound } from './_lib/layout.js';
import { renderHome } from './_lib/pages/home.js';

// Exact files the deploy copies into public/ (see .github/workflows/deploy.yml).
// NOTE the extensionless twins. Cloudflare Pages 308s /privacy.html to
// /privacy automatically, so listing only the .html form means the redirect
// lands on a path this catch-all does not recognise and 404s. That regression
// took the privacy policy offline — which is a store requirement, not a
// cosmetic page. Every .html asset needs both spellings here.
const ASSET_FILES = new Set([
  '/404.html',
  '/404',
  '/index.html',
  '/privacy.html',
  '/privacy',
  '/terms.html',
  '/terms',
  '/logo.svg',
  '/ico.png',
  '/kitabi-logo.png',
  '/apple-touch-icon.png',
  '/og-image.png',
  '/robots.txt',
  '/sitemap.xml',
  // IndexNow ownership proof. Must stay reachable and byte-match
  // api/app/services/indexnow.py's KEY — if this 404s, every submission comes
  // back 403 and the only symptom is that nothing ever gets announced.
  '/9b4aeafec5fe4eeaba383d6eb42bee5a.txt',
]);

// Directories served as files. `.well-known` is load-bearing for app links.
const ASSET_PREFIXES = ['/fonts/', '/.well-known/'];

export function isAsset(pathname) {
  if (ASSET_FILES.has(pathname)) return true;
  return ASSET_PREFIXES.some((prefix) => pathname.startsWith(prefix));
}

export async function onRequest(context) {
  const { pathname } = new URL(context.request.url);

  // HOME IS HANDLED HERE, not in index.js.
  //
  // A [[path]] catch-all shadows functions/index.js for "/" — named routes like
  // /browse keep winning, but "/" does not, and the home page 404'd in
  // production until this branch existed. Rather than rely on a precedence rule
  // that demonstrably does not hold, "/" is served explicitly from the one file
  // that is guaranteed to run.
  if (pathname === '/') {
    return servePage(context, '/public/home', renderHome, { what: 'page' });
  }

  if (isAsset(pathname)) {
    // Hand it back to the static asset handler untouched, so _headers still
    // applies (the immutable font caching, the app-association content types).
    return context.env.ASSETS.fetch(context.request);
  }

  // No route, no asset. A real 404 with noindex, so a wrong URL leaves the
  // index instead of sitting in it as a near-duplicate thin page.
  return notFound();
}
