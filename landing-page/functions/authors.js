// /authors — linked from the header. Until this existed the path fell through
// to the old launching-soon index.html at HTTP 200, which is the worst kind of
// broken link: it looks like a page.
import { servePeople } from './_lib/handler.js';

export function onRequestGet(context) {
  return servePeople(context, 'authors');
}
