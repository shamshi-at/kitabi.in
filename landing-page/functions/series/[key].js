// /series/:key — the books in reading order.
import { servePage } from '../_lib/handler.js';
import { renderSeries } from '../_lib/pages/more.js';

export function onRequestGet(context) {
  return servePage(context, `/public/series/${encodeURIComponent(context.params.key)}`, renderSeries, {
    what: 'series',
  });
}
