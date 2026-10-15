// /compare — Kitabi beside the apps readers ask about. The content is in
// _lib/guides.js; nothing here touches the API.
import { renderCompareIndex } from './_lib/pages/guides.js';

export function onRequestGet() {
  return renderCompareIndex();
}
