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

import { notFound } from './_lib/layout.js';

// Exact files the deploy copies into public/ (see .github/workflows/deploy.yml).
const ASSET_FILES = new Set([
  '/404.html',
  '/index.html',
  '/privacy.html',
  '/terms.html',
  '/logo.svg',
  '/ico.png',
  '/kitabi-logo.png',
  '/apple-touch-icon.png',
  '/og-image.png',
  '/robots.txt',
  '/sitemap.xml',
]);

// Directories served as files. `.well-known` is load-bearing for app links.
const ASSET_PREFIXES = ['/fonts/', '/.well-known/'];

export function isAsset(pathname) {
  if (ASSET_FILES.has(pathname)) return true;
  return ASSET_PREFIXES.some((prefix) => pathname.startsWith(prefix));
}

export async function onRequest(context) {
  const { pathname } = new URL(context.request.url);

  if (isAsset(pathname)) {
    // Hand it back to the static asset handler untouched, so _headers still
    // applies (the immutable font caching, the app-association content types).
    return context.env.ASSETS.fetch(context.request);
  }

  // No route, no asset. A real 404 with noindex, so a wrong URL leaves the
  // index instead of sitting in it as a near-duplicate thin page.
  return notFound();
}
