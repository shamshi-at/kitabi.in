// /lists — the directory of editorial lists.
import { serveListIndex } from './_lib/handler.js';

export function onRequestGet(context) {
  return serveListIndex(context);
}
