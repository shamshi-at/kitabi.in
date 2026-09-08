// /reader/:username/recap/:key — the page a shared reading card links to.
//
// 404s for a reader who hasn't published recaps, and does so indistinguishably
// from "no such handle" and from "that key means nothing": a derived link is a
// guessable one, so the gate is the whole of the protection.
import { servePage } from '../../../_lib/handler.js';
import { renderRecap } from '../../../_lib/pages/recap.js';

export function onRequestGet(context) {
  const { username, key } = context.params;
  return servePage(
    context,
    `/public/reader/${encodeURIComponent(username)}/recap/${encodeURIComponent(key)}`,
    renderRecap,
    { what: 'recap' },
  );
}
