// /languages — the directory of language hubs, linked from the header.
import { serveIndex } from './_lib/handler.js';

export function onRequestGet(context) {
  return serveIndex(context, {
    title: 'Languages',
    description:
      'Indian literature by language. Each hub collects the works, the writers and the translations in and out of that language.',
    kind: 'languages',
    field: 'languages',
    prefix: '/language/',
    canonical: '/languages',
  });
}
