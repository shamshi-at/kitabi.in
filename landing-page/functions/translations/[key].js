// /translations/:key — one book across every language it exists in. Canonical
// to the group, so this page and the individual book pages never compete for
// the same query.
import { servePage } from '../_lib/handler.js';
import { renderTranslations } from '../_lib/pages/more.js';

export function onRequestGet(context) {
  return servePage(
    context,
    `/public/translations/${encodeURIComponent(context.params.key)}`,
    renderTranslations,
    { what: 'translation group' },
  );
}
