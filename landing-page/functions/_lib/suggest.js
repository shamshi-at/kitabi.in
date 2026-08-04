// Search typeahead — the site's ONLY JavaScript, and entirely optional.
//
// Progressive enhancement in the strict sense: the search form is a plain GET
// that already works with JS disabled, blocked or failed. This attaches to it
// afterwards and adds a suggestion list. If any of it breaks, the form still
// submits and the server still renders results — nothing here is load-bearing.
//
// Inlined as a deferred <script> rather than a file: it is under 2 KB, so a
// separate request would cost more than the bytes save.

export const SUGGEST_JS = `
(function(){
  var forms = document.querySelectorAll('form[role="search"]');
  if (!forms.length || !window.fetch) return;

  forms.forEach(function(form){
    var input = form.querySelector('input[name="q"]');
    if (!input) return;

    var box = document.createElement('div');
    box.className = 'sugg';
    box.setAttribute('role', 'listbox');
    box.hidden = true;
    form.style.position = 'relative';
    form.appendChild(box);

    var timer, controller, items = [], active = -1;

    function close(){ box.hidden = true; active = -1; }

    function go(href){ if (href) window.location.href = href; }

    function draw(list){
      items = list || [];
      if (!items.length) { close(); return; }
      box.innerHTML = items.map(function(s, i){
        return '<a class="sugg-i" role="option" id="sg' + i + '" href="' + s.href + '">' +
               '<span class="sugg-l">' + esc(s.label) + '</span>' +
               (s.sub ? '<span class="sugg-s">' + esc(s.sub) + '</span>' : '') + '</a>';
      }).join('');
      box.hidden = false;
      active = -1;
    }

    // The suggestions come from our own API, but they are still strings from a
    // database being written into innerHTML — escape them.
    function esc(t){
      return String(t == null ? '' : t).replace(/[&<>"']/g, function(c){
        return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
      });
    }

    function highlight(){
      var nodes = box.querySelectorAll('.sugg-i');
      for (var i = 0; i < nodes.length; i++) {
        nodes[i].setAttribute('aria-selected', i === active ? 'true' : 'false');
      }
      input.setAttribute('aria-activedescendant', active >= 0 ? 'sg' + active : '');
    }

    input.setAttribute('autocomplete', 'off');
    input.setAttribute('role', 'combobox');
    input.setAttribute('aria-autocomplete', 'list');
    input.setAttribute('aria-expanded', 'false');

    input.addEventListener('input', function(){
      var q = input.value.trim();
      clearTimeout(timer);
      if (controller) controller.abort();
      if (q.length < 2) { close(); return; }
      // Debounced: a keystroke is not a request. 180ms is under the threshold
      // where typing feels laggy and well above one call per character.
      timer = setTimeout(function(){
        controller = new AbortController();
        fetch('/api/suggest?q=' + encodeURIComponent(q), { signal: controller.signal })
          .then(function(r){ return r.ok ? r.json() : null; })
          .then(function(d){ draw(d && d.suggestions); input.setAttribute('aria-expanded', box.hidden ? 'false' : 'true'); })
          .catch(function(){ /* the form still works */ });
      }, 180);
    });

    input.addEventListener('keydown', function(e){
      if (box.hidden) return;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        active += (e.key === 'ArrowDown' ? 1 : -1);
        if (active < -1) active = items.length - 1;
        if (active >= items.length) active = -1;
        highlight();
      } else if (e.key === 'Enter' && active >= 0) {
        // Only intercept Enter when a suggestion is actually selected —
        // otherwise the form submits normally, which is the behaviour someone
        // who ignored the dropdown expects.
        e.preventDefault();
        go(items[active].href);
      } else if (e.key === 'Escape') {
        close();
      }
    });

    document.addEventListener('click', function(e){
      if (!form.contains(e.target)) close();
    });
    input.addEventListener('blur', function(){ setTimeout(close, 150); });
  });
})();
`;

export const SUGGEST_CSS = `
.sugg{position:absolute;top:calc(100% + 6px);left:0;right:0;z-index:60;background:var(--card);
  border:1px solid var(--line);border-radius:12px;overflow:hidden;
  box-shadow:0 12px 32px rgba(43,33,24,.22)}
.sugg-i{display:block;padding:9px 14px;border-bottom:1px solid var(--line)}
.sugg-i:last-child{border-bottom:0}
.sugg-i:hover,.sugg-i[aria-selected="true"]{background:var(--paper-deep)}
.sugg-l{display:block;font-family:var(--serif);font-size:14px;font-weight:600;line-height:1.3}
.sugg-s{display:block;font-size:11.5px;color:var(--ink-soft);margin-top:2px}
`;
