// /ml/app — the app page in Malayalam, paired with /app by hreflang.
import { renderMalayalamApp } from '../_lib/pages/guides.js';

export function onRequestGet() {
  return renderMalayalamApp();
}
