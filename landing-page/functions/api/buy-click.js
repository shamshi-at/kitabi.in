// POST /api/buy-click — the website's click report, forwarded to the API.
//
// Same origin as the page on purpose (see _lib/buyclick.js): the browser
// never talks to the API host, and this function is the one place that
// decides what a report may contain before the origin sees it.
//
// Always 204, and never waits for the API: the reader who clicked is already
// on their way to the shop, and nothing here may slow or fail that.
import { reportToApi } from '../_lib/api.js';
import { buyClickReport, fromOurOwnPage } from '../_lib/buyclick.js';

const DONE = () => new Response(null, { status: 204, headers: { 'Cache-Control': 'no-store' } });

export async function onRequestPost(context) {
  const { request } = context;
  try {
    if (!fromOurOwnPage(request.url, request.headers.get('origin'))) return DONE();
    const report = buyClickReport(await request.text());
    if (!report) return DONE();
    const sent = reportToApi('/public/buy-click', report, request.headers.get('user-agent'));
    if (context.waitUntil) context.waitUntil(sent);
    else await sent;
  } catch (_) {
    // Counting a click is never worth an error page.
  }
  return DONE();
}
