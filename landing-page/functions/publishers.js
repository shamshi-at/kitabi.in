// /publishers — see authors.js.
import { servePeople } from './_lib/handler.js';

export function onRequestGet(context) {
  return servePeople(context, 'publishers');
}
