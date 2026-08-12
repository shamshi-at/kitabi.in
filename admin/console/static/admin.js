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
