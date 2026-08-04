// /translations — the translation index. Books that exist in more than one
// language, which is the site's signature and a page nobody else publishes.
import { serveTranslationIndex } from './_lib/handler.js';

export function onRequestGet(context) {
  return serveTranslationIndex(context);
}
