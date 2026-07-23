// /sitemaps/:name — proxy the catalog sitemaps (index + paged urlsets) from
// the API so search engines fetch them from kitabi.in, the host the share
// URLs live on (robots.txt points crawlers at /sitemaps/index.xml).
//
// SCALE: one edge invocation + one API GET per crawl hit, and crawlers respect
// the hour-long Cache-Control; fine on the free tier.

const API = 'https://api.kitabi.in';

// index.xml, works-1.xml, authors-12.xml, publishers-3.xml, … — anything else
// (path traversal, junk) is a plain 404, never forwarded to the API.
const NAME_RE = /^(index|(works|authors|publishers)-\d{1,5})\.xml$/;

export async function onRequest(context) {
  const name = context.params.name;
  if (!NAME_RE.test(name)) {
    return new Response('Not found', { status: 404 });
  }

  let upstream;
  try {
    upstream = await fetch(`${API}/catalog/sitemap/${name}`, {
      headers: { Accept: 'application/xml' },
    });
  } catch (_) {
    return new Response('Sitemap temporarily unavailable', { status: 503 });
  }

  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': 'application/xml',
      'Cache-Control': 'public, max-age=3600',
    },
  });
}
