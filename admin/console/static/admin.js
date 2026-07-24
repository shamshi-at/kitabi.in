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
