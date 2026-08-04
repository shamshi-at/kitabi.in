// /list/:slug — an editorial list. The list itself is content in _lib/lists.js;
// only the book data comes from the API.
import { serveList } from '../_lib/handler.js';

export function onRequestGet(context) {
  return serveList(context, context.params.slug);
}
