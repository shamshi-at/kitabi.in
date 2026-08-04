// /reader/:username — a public reader profile.
//
// 404s for anyone who hasn't opted in, and does so indistinguishably from "no
// such handle": "this reader exists but is private" is itself a disclosure.
import { servePage } from '../_lib/handler.js';
import { renderReader } from '../_lib/pages/more.js';

export function onRequestGet(context) {
  return servePage(
    context,
    `/public/reader/${encodeURIComponent(context.params.username)}`,
    renderReader,
    { what: 'reader' },
  );
}
