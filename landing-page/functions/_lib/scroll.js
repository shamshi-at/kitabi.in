// The continuous list and the jump button — the second (and last) piece of
// JavaScript on the site, and as optional as the first (_lib/suggest.js).
//
// **The list.** Every paged list — browse, the language and genre hubs, the
// author and publisher directories, a book's reviews — is still rendered by the
// server one page at a time, with a real pager of real links underneath
// (components.js `pager`). That is what a crawler walks and what a reader gets
// with JavaScript off. This script reads `rel="next"` out of that pager, hides
// the numbered buttons, and when the reader nears the end of the list fetches
// the next page — the same URL a click would have opened, so it is the same
// edge-cache entry and costs the origin nothing new — and moves that page's
// items into this one.
//
// Three things an endless list gets wrong, and what is done about each:
//
//  * **The address stops meaning anything.** As a batch scrolls into view the
//    address bar is rewritten (replaceState) to the page that batch came from,
//    so a reload, a bookmark or a shared link lands on what was on screen.
//  * **The footer can never be reached.** The jump button's "down" pauses the
//    loading and goes to the real end of the page; "Show more" resumes it.
//  * **A failed fetch strands the reader.** On any error the "Show more" link
//    goes back to being a plain link to the next page.
//
// Nothing is fetched until the reader has actually scrolled (or pressed "Show
// more"). A list that happens to end inside the window is not a request for
// the next page — and a crawler that renders the page in a very tall window
// without scrolling must see page 1 as page 1, with a link to page 2, not the
// first five pages poured into one address.
//
// A reader who arrives on page 3 is shown page 3 onwards, with a plain link
// back to the page before it.
//
// **The jump button.** One floating button that follows the reader's last
// scroll: scrolling up offers the top, scrolling down offers the end. It shows
// only on pages long enough to need it, away from the edge it points at, and
// fades after a few idle seconds so it does not sit on the covers.
//
// Inlined like the typeahead, for the same reason: ~3 KB, so a separate
// request would cost more than the bytes save. No backticks and no dollar-brace
// inside the script — it lives in a template literal.

export const SCROLL_CSS = `
.scm{display:flex;flex-direction:column;align-items:center;gap:8px;margin-top:26px}
.scm-more,.scm-prev a{border:1px solid var(--line);background:var(--card);border-radius:8px;
  padding:9px 18px;font-size:12.5px;font-weight:600;color:var(--ink)}
.scm-more:hover,.scm-prev a:hover{border-color:var(--oxblood);color:var(--oxblood)}
.scm-more[aria-busy]{opacity:.55;pointer-events:none}
.scm-st{font-size:12px;color:var(--ink-soft);min-height:16px}
.scm-prev{display:flex;justify-content:center;margin:0 0 18px}
.jmp{position:fixed;right:16px;bottom:calc(16px + env(safe-area-inset-bottom,0px));z-index:30;
  width:44px;height:44px;border-radius:50%;border:1px solid var(--oxblood);background:var(--oxblood);
  color:#F6F0E3;font-size:19px;line-height:1;cursor:pointer;padding:0;
  box-shadow:0 8px 22px rgba(43,33,24,.28);opacity:0;visibility:hidden;transform:translateY(8px)}
.jmp.on{opacity:1;visibility:visible;transform:none}
.jmp:focus-visible{outline:2px solid var(--gold);outline-offset:3px}
@media(prefers-reduced-motion:no-preference){
  .jmp{transition:opacity .18s,transform .18s,visibility .18s}
}
`;

export const SCROLL_JS = `
(function(){
  var d = document, w = window, root = d.documentElement;
  if (!w.requestAnimationFrame || !d.querySelector) return;
  var calm = w.matchMedia && w.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var DASH = '\\u2013';

  // ---- the continuous list ---------------------------------------------
  var feed = null;
  var pager = d.querySelector('nav[data-pager]');
  var list = d.querySelector('[data-list]');
  if (pager && list && list.firstElementChild && w.fetch && w.DOMParser &&
      w.IntersectionObserver && w.history && history.replaceState) {
    feed = startFeed();
  }

  function startFeed(){
    var nextA = pager.querySelector('a[rel="next"]');
    var prevA = pager.querySelector('a[rel="prev"]');
    var next = nextA ? nextA.getAttribute('href') : null;
    var cnt = d.querySelector('.cnt');
    var from = cnt ? cnt.textContent.split(DASH)[0] : '';
    var batches = [{ el: list.firstElementChild, url: location.pathname + location.search, title: d.title }];
    var busy = false, paused = false, broken = false, armed = false, current = 0;

    // The author stylesheet gives .pager display:flex, which beats [hidden].
    pager.style.display = 'none';

    if (prevA) {
      var up = d.createElement('p');
      up.className = 'scm-prev';
      var back = d.createElement('a');
      back.href = prevA.getAttribute('href');
      back.textContent = '\\u2039 Show earlier';
      up.appendChild(back);
      list.parentNode.insertBefore(up, list);
    }

    var box = d.createElement('div');
    box.className = 'scm';
    var more = d.createElement('a');
    more.className = 'scm-more';
    more.textContent = 'Show more';
    var st = d.createElement('span');
    st.className = 'scm-st';
    st.setAttribute('role', 'status');
    st.setAttribute('aria-live', 'polite');
    box.appendChild(more);
    box.appendChild(st);
    pager.parentNode.insertBefore(box, pager);

    function draw(){
      if (next) { more.href = next; more.style.display = ''; }
      else { more.style.display = 'none'; }
    }

    var io = new IntersectionObserver(function(entries){
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].isIntersecting && armed && !paused) load();
      }
    }, { rootMargin: '0px 0px 900px 0px' });

    function load(){
      if (busy || broken || !next) return;
      busy = true;
      var url = next;
      more.setAttribute('aria-busy', 'true');
      st.textContent = 'Loading more\\u2026';
      fetch(url, { headers: { Accept: 'text/html' } })
        .then(function(res){ if (!res.ok) throw new Error('status'); return res.text(); })
        .then(function(text){
          var doc = new DOMParser().parseFromString(text, 'text/html');
          var theirs = doc.querySelector('[data-list]');
          if (!theirs || !theirs.firstElementChild) throw new Error('shape');
          var first = null, added = 0;
          while (theirs.firstElementChild) {
            var node = d.adoptNode(theirs.firstElementChild);
            if (!first) first = node;
            list.appendChild(node);
            added++;
          }
          batches.push({ el: first, url: url, title: doc.title });
          var theirCnt = doc.querySelector('.cnt');
          if (cnt && theirCnt && theirCnt.textContent.indexOf(DASH) > 0) {
            cnt.textContent = from + DASH + theirCnt.textContent.split(DASH)[1];
          }
          var theirNext = doc.querySelector('nav[data-pager] a[rel="next"]');
          next = theirNext ? theirNext.getAttribute('href') : null;
          busy = false;
          more.removeAttribute('aria-busy');
          // What the reader now has, said where they are looking — and, being
          // a live region, announced to a screen reader on every batch.
          st.textContent = !next ? 'That is everything.'
            : cnt ? cnt.textContent : added + ' more shown';
          draw();
          // A tall screen may still have the block in view; an observer only
          // reports changes, so ask it again.
          io.unobserve(box);
          if (next) io.observe(box);
        })
        .catch(function(){
          // Leave the reader a way on: the link is a plain link again.
          busy = false;
          broken = true;
          more.removeAttribute('aria-busy');
          st.textContent = 'Could not load more here. The link opens the next page.';
          io.disconnect();
        });
    }

    more.addEventListener('click', function(e){
      if (broken || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button) return;
      e.preventDefault();
      paused = false;
      armed = true;
      load();
    });

    draw();
    if (next) io.observe(box);

    return {
      pause: function(){ paused = true; },
      // The reader's first scroll. An observer only reports changes, so it is
      // asked again in case the end of the list is already in range.
      arm: function(){
        if (armed) return;
        armed = true;
        if (next && !broken) { io.unobserve(box); io.observe(box); }
      },
      // Which batch is on screen: the last one whose first item has passed the
      // middle of the window. Its address is the page it came from.
      sync: function(){
        var mid = w.innerHeight / 2, now = 0;
        for (var i = 0; i < batches.length; i++) {
          if (batches[i].el.getBoundingClientRect().top <= mid) now = i;
        }
        if (now === current) return;
        current = now;
        try {
          history.replaceState(history.state, '', batches[now].url);
          d.title = batches[now].title;
        } catch (e) {}
      }
    };
  }

  // ---- the jump button --------------------------------------------------
  var jmp = d.createElement('button');
  jmp.type = 'button';
  jmp.className = 'jmp';
  d.body.appendChild(jmp);
  var lastY = w.pageYOffset || 0, dir = 0, timer = null, ticking = false;

  function hide(){ jmp.classList.remove('on'); }

  function idle(){
    if (jmp.matches && jmp.matches(':hover,:focus')) { timer = setTimeout(idle, 1500); return; }
    hide();
  }

  function point(){
    var y = w.pageYOffset || 0, vh = w.innerHeight, h = root.scrollHeight;
    if (Math.abs(y - lastY) > 6) { dir = y > lastY ? 1 : -1; lastY = y; }
    var show = false;
    if (h > vh * 2) {
      if (dir < 0) show = y > vh;
      else if (dir > 0) show = h - vh - y > vh;
    }
    if (!show) { hide(); return; }
    var up = dir < 0;
    jmp.setAttribute('data-dir', up ? 'up' : 'down');
    jmp.textContent = up ? '\\u2191' : '\\u2193';
    jmp.setAttribute('aria-label', up ? 'Back to the top' : 'Jump to the end of the page');
    jmp.title = up ? 'Back to the top' : 'Jump to the end';
    jmp.classList.add('on');
    clearTimeout(timer);
    timer = setTimeout(idle, 3500);
  }

  jmp.addEventListener('click', function(){
    var up = jmp.getAttribute('data-dir') === 'up';
    // Going to the end means the end: stop fetching more, or the footer
    // moves away as fast as the reader approaches it.
    if (!up && feed) feed.pause();
    w.scrollTo({ top: up ? 0 : root.scrollHeight, behavior: calm ? 'auto' : 'smooth' });
    hide();
  });

  w.addEventListener('scroll', function(){
    if (ticking) return;
    ticking = true;
    w.requestAnimationFrame(function(){
      ticking = false;
      point();
      if (feed) { feed.arm(); feed.sync(); }
    });
  }, { passive: true });
})();
`;
