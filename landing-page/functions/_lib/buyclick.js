// Counting clicks on the bookseller button — the website's half.
//
// The button on a book page is an ordinary link straight to the shop, and it
// stays one: nothing here stands between a reader and where they are going.
// This only *reports* that the click happened, so the console can show which
// books people go on to look at buying (owner request, 5 Oct 2026).
//
// It is the one thing the public site writes, so it is kept small enough to
// read in a minute:
//
//  * the browser sends a beacon to OUR origin (`/api/buy-click`) — never to
//    the API host, which no public page may name;
//  * the edge function forwards only a report it has rebuilt from validated
//    fields (`buyClickReport` below), so nothing a caller adds rides along;
//  * the API stores the book and the shop — no account, no IP, no browser.
//
// A crawler never fires it (it is a click handler, not a link), a reader with
// JavaScript off is simply not counted, and a blocked beacon costs nothing:
// the link has already opened.

/** Inlined on a book page that has a buy link. No backticks, no dollar-brace. */
export const BUY_CLICK_JS = `
(function(){
  if (!navigator.sendBeacon || !document.addEventListener) return;
  function report(e){
    var a = e.target && e.target.closest ? e.target.closest('a[data-buy]') : null;
    if (!a) return;
    // A middle click opens the shop in a new tab — still a click on the button.
    if (e.type === 'auxclick' && e.button !== 1) return;
    try {
      navigator.sendBeacon('/api/buy-click', JSON.stringify({
        edition_id: a.getAttribute('data-edition'),
        retailer: a.getAttribute('data-buy'),
        affiliate: a.hasAttribute('data-aff')
      }));
    } catch (err) {}
  }
  document.addEventListener('click', report, true);
  document.addEventListener('auxclick', report, true);
})();
`;

const MAX_REPORT_BYTES = 512;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// A shop's name as the page printed it: letters, spaces and a little
// punctuation. Not a URL, not markup, not forty kilobytes.
const SHOP = /^[A-Za-z][A-Za-z0-9 .&-]{0,39}$/;

/**
 * The report to forward to the API, or null when the body is not one.
 *
 * Rebuilt from the three fields it may contain rather than passed through:
 * whatever else a caller put in the body stops here. Pure, so it is tested.
 */
export function buyClickReport(text) {
  if (typeof text !== 'string' || !text || text.length > MAX_REPORT_BYTES) return null;
  let data;
  try {
    data = JSON.parse(text);
  } catch (_) {
    return null;
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
  const edition = typeof data.edition_id === 'string' ? data.edition_id : '';
  const retailer = typeof data.retailer === 'string' ? data.retailer : '';
  if (!UUID.test(edition) || !SHOP.test(retailer)) return null;
  return JSON.stringify({
    edition_id: edition.toLowerCase(),
    retailer,
    affiliate: data.affiliate === true,
  });
}

/**
 * Whether a report came from one of our own pages. A browser states where a
 * request was made from; another site scripting its visitors' browsers at this
 * endpoint is told no. (Someone with curl can say anything — the API's own
 * checks and ceiling are what bound that.)
 */
export function fromOurOwnPage(requestUrl, originHeader) {
  if (!originHeader) return false;
  try {
    return new URL(originHeader).hostname === new URL(requestUrl).hostname;
  } catch (_) {
    return false;
  }
}
