// /lending-tracker — the lending ledger as its own page, for the readers who
// search for the job rather than for an app's name.
import { renderLendingTracker } from './_lib/pages/guides.js';

export function onRequestGet() {
  return renderLendingTracker();
}
