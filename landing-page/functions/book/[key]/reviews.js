// /book/:key/reviews — every public review on one book, paginated.
import { serveReviews } from '../../_lib/handler.js';
import { renderReviews } from '../../_lib/pages/more.js';

export function onRequestGet(context) {
  return serveReviews(context, context.params.key, renderReviews);
}
