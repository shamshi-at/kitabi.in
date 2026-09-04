// /series/:key — the books in reading order.
import { servePage } from '../_lib/handler.js';
import { renderSeries } from '../_lib/pages/more.js';

export function onRequestGet(context) {
  const key = context.params.key;
  return servePage(context, `/public/series/${encodeURIComponent(key)}`, renderSeries, {
    what: 'series',
    mergedFrom: { kind: 'series', key },
  });
}
