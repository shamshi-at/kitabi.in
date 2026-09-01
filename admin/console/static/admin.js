// Global search dropdown — vanilla, no framework. Debounced fetch of the
// /search fragment into the top-bar dropdown, with keyboard control:
//   /        focus the search (unless already typing in a field)
//   Esc      close / blur
//   ↑ ↓      move the highlight
//   Enter    open the highlighted result (or the first one)
(function () {
  const input = document.getElementById("gsearch");
  const box = document.getElementById("gsearch-results");
  if (!input || !box) return;

  let timer = null;
  let items = [];
  let active = -1;

  function close() {
    box.hidden = true;
    box.innerHTML = "";
    items = [];
    active = -1;
  }

  function paintActive() {
    items.forEach((el, i) => el.classList.toggle("on", i === active));
    if (active >= 0) items[active].scrollIntoView({ block: "nearest" });
  }

  async function run(q) {
    try {
      const res = await fetch("/search?q=" + encodeURIComponent(q), {
        headers: { "X-Requested-With": "fetch" },
      });
      if (!res.ok) return close();
      box.innerHTML = await res.text();
      box.hidden = false;
      items = Array.from(box.querySelectorAll(".gs-item"));
      active = items.length ? 0 : -1;
      paintActive();
    } catch (_) {
      close();
    }
  }

  input.addEventListener("input", () => {
    const q = input.value.trim();
    clearTimeout(timer);
    if (!q) return close();
    timer = setTimeout(() => run(q), 180);
  });

  input.addEventListener("keydown", (e) => {
    if (e.key === "Escape") return input.blur(), close();
    if (box.hidden || !items.length) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      active = (active + 1) % items.length;
      paintActive();
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      active = (active - 1 + items.length) % items.length;
      paintActive();
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (active >= 0) items[active].click();
    }
  });

  // "/" focuses search from anywhere that isn't already an input.
  document.addEventListener("keydown", (e) => {
    if (e.key !== "/" ) return;
    const t = e.target;
    if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) return;
    e.preventDefault();
    input.focus();
    input.select();
  });

  // Click-away closes.
  document.addEventListener("click", (e) => {
    if (!box.contains(e.target) && e.target !== input) close();
  });
  input.addEventListener("focus", () => {
    if (input.value.trim() && box.innerHTML) box.hidden = false;
  });
})();

// Mobile nav — the sidebar rail is off-canvas below the tablet breakpoint; the
// hamburger in the top bar slides it in over a scrim. Closes on scrim tap, on a
// nav link tap, and on Escape, so it never traps the user on a small screen.
(function () {
  const shell = document.getElementById("shell");
  const toggle = document.getElementById("railToggle");
  const scrim = document.getElementById("railScrim");
  const rail = document.getElementById("rail");
  if (!shell || !toggle || !scrim || !rail) return;

  function open() {
    shell.classList.add("rail-open");
    scrim.hidden = false;
    toggle.setAttribute("aria-expanded", "true");
  }
  function close() {
    shell.classList.remove("rail-open");
    scrim.hidden = true;
    toggle.setAttribute("aria-expanded", "false");
  }
  function isOpen() {
    return shell.classList.contains("rail-open");
  }

  toggle.addEventListener("click", () => (isOpen() ? close() : open()));
  scrim.addEventListener("click", close);
  rail.addEventListener("click", (e) => {
    if (e.target.closest("a")) close();
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && isOpen()) close();
  });
})();

// Peek popup — "who is this, really?" Any element carrying data-peek="<url>"
// opens that fragment in the shared dialog, so a merge decision can be checked
// against the record's actual catalog without leaving the queue (and losing
// the comparison you were in the middle of).
(function () {
  const dlg = document.getElementById("peek");
  const body = document.getElementById("peekBody");
  if (!dlg || !body) return;

  document.addEventListener("click", async (e) => {
    const trigger = e.target.closest("[data-peek]");
    if (trigger) {
      e.preventDefault();
      body.innerHTML = '<div class="pk-bd"><p class="m">Loading…</p></div>';
      dlg.showModal();
      try {
        const res = await fetch(trigger.dataset.peek, {
          headers: { "X-Requested-With": "fetch" },
        });
        body.innerHTML = await res.text();
      } catch (_) {
        body.innerHTML =
          '<div class="pk-bd"><p class="m">Could not load that record.</p></div>';
      }
      return;
    }
    // Close on the button, or on a click in the backdrop outside the panel.
    if (e.target.closest("[data-peek-close]") || e.target === dlg) dlg.close();
  });
})();

// Duplicate review — the "name to keep" field follows whichever row is
// selected, so picking a survivor also proposes its name. Once the reviewer
// types their own, it stops following: their correction outranks any row.
(function () {
  document.addEventListener("change", (e) => {
    const radio = e.target.closest('input[name="survivor_id"]');
    if (!radio || !radio.form) return;
    const field = radio.form.querySelector("[data-cluster-name]");
    if (field && !field.dataset.dirty) field.value = radio.dataset.name || field.value;
  });
  document.addEventListener("input", (e) => {
    if (e.target.matches("[data-cluster-name]")) e.target.dataset.dirty = "1";
  });
})();

// Merge picker — Keep/Absorb buttons on catalog rows fill the merge form, so
// nobody copies UUIDs by hand (impossible on a phone). Marks the chosen row's
// button so the current selection is visible, and flashes the form when both
// halves are set.
(function () {
  const form = document.getElementById("mergeform");
  if (!form) return;
  const inputs = {
    keep: form.querySelector('[name="keep"]'),
    absorb: form.querySelector('[name="absorb"]'),
  };
  document.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-mergepick]");
    if (!btn) return;
    const role = btn.dataset.mergepick;
    inputs[role].value = btn.dataset.id;
    document
      .querySelectorAll(`[data-mergepick="${role}"].on`)
      .forEach((b) => b.classList.remove("on"));
    btn.classList.add("on");
    if (inputs.keep.value && inputs.absorb.value) {
      form.scrollIntoView({ block: "nearest", behavior: "smooth" });
      form.classList.add("ready");
    }
  });
})();

// Inline save — a form marked data-inline posts via fetch and marks itself
// saved in place, so the buy-links worklist doesn't reload the whole page
// (and lose scroll position) for every row saved.
(function () {
  document.addEventListener("submit", async (e) => {
    const form = e.target.closest("form[data-inline]");
    if (!form) return;
    e.preventDefault();
    const btn = form.querySelector("button");
    const err = form.querySelector(".inline-err");
    btn.disabled = true;
    if (err) err.textContent = "";
    try {
      const res = await fetch(form.action, {
        method: "POST",
        body: new FormData(form),
        headers: { "X-Requested-With": "fetch" },
      });
      if (res.ok) {
        const row = form.closest("[data-row]") || form;
        row.classList.add("done");
        btn.textContent = "Saved ✓";
      } else {
        if (err) err.textContent = await res.text();
        btn.disabled = false;
      }
    } catch (_) {
      if (err) err.textContent = "Network error — try again.";
      btn.disabled = false;
    }
  });
  // Retyping after a save re-arms the button.
  document.addEventListener("input", (e) => {
    const form = e.target.closest("form[data-inline]");
    if (!form) return;
    const btn = form.querySelector("button");
    if (btn.textContent.startsWith("Saved")) {
      btn.textContent = "Save";
      btn.disabled = false;
      (form.closest("[data-row]") || form).classList.remove("done");
    }
  });
})();

// Six-box one-time-code input: auto-advance, backspace-to-previous, paste-fills,
// and it keeps a hidden `code` field in sync (that's what the form submits).
// Auto-submits the moment all six digits are present.
(function () {
  document.querySelectorAll("[data-otp]").forEach(function (wrap) {
    const boxes = Array.from(wrap.querySelectorAll(".otp-box"));
    const hidden = wrap.querySelector('input[type="hidden"]');
    const form = wrap.closest("form");
    if (!boxes.length || !hidden) return;

    function sync() {
      hidden.value = boxes.map((b) => b.value).join("");
      boxes.forEach((b) => b.classList.toggle("filled", !!b.value));
      if (hidden.value.length === boxes.length && form) {
        (form.requestSubmit ? form.requestSubmit() : form.submit());
      }
    }

    boxes.forEach((box, i) => {
      box.addEventListener("input", () => {
        box.value = box.value.replace(/\D/g, "").slice(0, 1);
        if (box.value && i < boxes.length - 1) boxes[i + 1].focus();
        sync();
      });
      box.addEventListener("keydown", (e) => {
        if (e.key === "Backspace" && !box.value && i > 0) {
          boxes[i - 1].focus();
        }
      });
      box.addEventListener("paste", (e) => {
        e.preventDefault();
        const digits = (e.clipboardData.getData("text") || "")
          .replace(/\D/g, "")
          .slice(0, boxes.length)
          .split("");
        digits.forEach((d, j) => {
          if (boxes[j]) boxes[j].value = d;
        });
        boxes[Math.min(digits.length, boxes.length - 1)].focus();
        sync();
      });
    });
  });
})();

// Register the service worker (see /sw.js, main.py). Its only job is to make
// the console installable; it caches static assets and nothing dynamic. Failure
// is silent — the console works identically without it, so a browser that
// blocks workers (or a hard-refresh with the worker disabled) loses nothing.
//
// updateViaCache:'none' — Cloudflare edge-caches /sw.js for 4h (a zone rule by
// file type, overriding the origin's no-cache), so the browser must be told to
// bypass its OWN http cache when checking the worker for updates. Without this
// a fixed worker could be shadowed by a stale cached copy; with it, every
// update check hits the network and a new sw.js ships on the next visit.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js", { updateViaCache: "none" }).catch(() => {});
  });
}

// Navigation loader (see .navload in admin.css, the markup in base.html).
//
// The console is server-rendered: a link is a full page load and a form is a
// POST-and-redirect. Installed as a PWA there is no browser tab spinner, so a
// click looks like nothing happened until the next page paints. This shows the
// Kitabi mark over the page the moment a navigation starts, and lets the new
// document (a fresh DOM, no overlay) simply replace it.
(function () {
  const el = document.getElementById("navload");
  if (!el) return;
  let safety = null;

  function show() {
    el.classList.add("on");
    el.setAttribute("aria-hidden", "false");
    // If a navigation somehow never happens (a download, a handler that bailed
    // after we showed), don't strand the reader under the overlay forever.
    clearTimeout(safety);
    safety = setTimeout(hide, 12000);
  }
  function hide() {
    el.classList.remove("on");
    el.setAttribute("aria-hidden", "true");
    clearTimeout(safety);
  }

  // A left-click on a link that will actually navigate this tab away.
  document.addEventListener("click", (e) => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    const a = e.target.closest("a[href]");
    if (!a) return;
    if (a.target && a.target !== "_self") return; // opens elsewhere
    if (
      a.hasAttribute("download") ||
      a.dataset.noLoader !== undefined ||
      a.hasAttribute("data-peek") ||
      a.hasAttribute("data-back") // handled by the smart-back handler, no loader
    )
      return;
    const href = a.getAttribute("href");
    if (!href || href.startsWith("#") || /^(javascript|mailto|tel):/i.test(href)) return;
    // Same-origin only — an external link leaves for the system browser and this
    // page stays put, so a loader here would hang.
    let url;
    try {
      url = new URL(a.href, location.href);
    } catch (_) {
      return;
    }
    if (url.origin !== location.origin) return;
    if (url.pathname === location.pathname && url.search === location.search && url.hash) return; // in-page anchor
    show();
  });

  // A form that will submit and navigate. Runs in the bubble phase after every
  // other submit handler, so `defaultPrevented` already reflects a cancelling
  // confirm() ("return confirm(...)") or a data-inline fetch save — either way
  // there is no navigation, so skip.
  document.addEventListener("submit", (e) => {
    if (e.defaultPrevented) return;
    const form = e.target;
    if (form.dataset.noLoader !== undefined || form.hasAttribute("data-inline")) return;
    show();
  });

  // Hide on every page display — a normal load, and crucially a bfcache restore
  // (Back button), where the old page can come back with the overlay still up.
  window.addEventListener("pageshow", hide);
})();

// Bulk selection on the catalog worklist — tick rows, delete the junk in one
// confirmed submit. The form (#bulkform) posts checked ids to
// /catalog/works/delete; the server skips anything a reader depends on.
(function () {
  const form = document.getElementById("bulkform");
  if (!form) return;
  const selall = form.querySelector("[data-selall]");
  const bar = form.querySelector("[data-bulkbar]");
  const count = form.querySelector("[data-bulkcount]");
  const boxes = () => Array.from(form.querySelectorAll(".rowchk"));

  function sync() {
    const all = boxes();
    const on = all.filter((b) => b.checked);
    if (count) count.textContent = on.length;
    if (bar) bar.hidden = on.length === 0;
    if (selall) {
      selall.checked = all.length > 0 && on.length === all.length;
      selall.indeterminate = on.length > 0 && on.length < all.length;
    }
  }

  form.addEventListener("change", (e) => {
    if (e.target === selall) boxes().forEach((b) => (b.checked = selall.checked));
    sync();
  });

  // The confirm is on the form element, so it runs before the document-level
  // navigation loader — a cancelled delete never flashes the loader.
  form.addEventListener("submit", (e) => {
    const n = boxes().filter((b) => b.checked).length;
    if (n === 0) {
      e.preventDefault();
      return;
    }
    const msg =
      "Delete " +
      n +
      " selected work" +
      (n === 1 ? "" : "s") +
      "? Any that readers have shelved, rated or reviewed are skipped. Soft delete — recoverable.";
    if (!confirm(msg)) e.preventDefault();
  });

  sync();
})();

// Smart back — the "← Section" link on a detail page. If you arrived here from
// somewhere on this site (a filtered list, a search), go back to it EXACTLY as
// you left it — filters, sort, scroll, all of it — via the browser's own
// history, which the server-rendered filter state in the URL restores for free.
// With no in-app history (a fresh tab, a pasted link) it falls through to the
// link's href, which points at the section's list. Progressive enhancement:
// with JS off, the href just works.
(function () {
  document.addEventListener("click", (e) => {
    const a = e.target.closest("a[data-back]");
    if (!a || e.defaultPrevented) return;
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    // history.length > 1 means there's a previous entry to return to. This
    // mirrors the browser's own Back button, which already lands on the filtered
    // list (verified) because the filter lives in the query string.
    if (history.length > 1) {
      e.preventDefault();
      history.back();
    }
  });
})();

// Live dashboard strip — polls the /live fragment and swaps it in place, so the
// "right now" numbers tick without a reload. Server-rendered HTML, not JSON:
// the same template paints the first load and every refresh, so the two can
// never drift apart.
//
// Three rules it follows, each learned the boring way:
//  * a hidden tab polls nothing (a console left open on a second screen must
//    not be a load generator), and refreshes immediately on becoming visible;
//  * a failed fetch leaves the last good strip on screen — a network blip is
//    not news, and blanking the panel would be worse than being 20s stale;
//  * the navigation loader is never shown for a background poll.
(function () {
  const host = document.getElementById("live");
  if (!host) return;
  const url = host.dataset.live;
  if (!url) return;
  const EVERY = 20000;
  let timer = null;

  async function refresh() {
    if (document.hidden) return;
    try {
      const res = await fetch(url, { headers: { "X-Requested-With": "fetch" } });
      if (!res.ok) return;
      host.innerHTML = await res.text();
    } catch (_) {
      /* keep the last good strip */
    }
  }

  function start() {
    stop();
    timer = setInterval(refresh, EVERY);
  }
  function stop() {
    if (timer) clearInterval(timer);
    timer = null;
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stop();
    else {
      refresh();
      start();
    }
  });
  start();
})();
