// The public site's stylesheet, as a string, inlined into every page.
//
// WHY INLINED rather than a linked file: the performance budget allows ZERO
// render-blocking requests (docs/web-platform-plan.md §6). A linked stylesheet
// is one, and most visitors here arrive from a search result, read one page and
// leave — so there is no second page to amortise a cached file across. Gzipped
// this is a couple of KB inside a document that already has to be sent.
//
// FONTS ARE SELF-HOSTED, from /fonts (see landing-page/fonts/README.md). Never
// fonts.googleapis.com: that costs a DNS lookup, a TLS handshake, a CSS round
// trip and *then* a fetch from a second origin before a glyph paints, and the
// budget allows zero third-party origins.
//
// Three properties make this safe to put in front of every page:
//   * `font-display: swap` — text paints immediately in the fallback and swaps
//     when the face arrives, so a slow font never delays the LCP.
//   * `unicode-range` — the latin-ext subsets download ONLY on pages that
//     actually render those characters. That matters here: the catalogue is
//     full of transliterated names (Bibhūtibhūshaṇa, Ḥāfiẓ, Kāśīnātha) and
//     without the extended subset a name renders in two typefaces at once.
//   * `size-adjust`/fallback stack chosen so the swap moves as little as
//     possible — the whole point of explicit image dimensions elsewhere is CLS,
//     and a font swap is the other half of that.
//
// Indic scripts are deliberately NOT bundled — 14 languages would be ~500 KB to
// solve a problem the system fonts already handle. See fonts/README.md.

export const CSS = `
@font-face{
  font-family:'Fraunces';font-style:normal;font-weight:400 700;font-display:swap;
  src:url('/fonts/fraunces-latin.woff2') format('woff2');
  unicode-range:U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,
    U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD;
}
@font-face{
  font-family:'Fraunces';font-style:normal;font-weight:400 700;font-display:swap;
  src:url('/fonts/fraunces-latin-ext.woff2') format('woff2');
  unicode-range:U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,
    U+0308,U+0329,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C0,
    U+2113,U+2C60-2C7F,U+A720-A7FF;
}
@font-face{
  font-family:'InterVar';font-style:normal;font-weight:400 700;font-display:swap;
  src:url('/fonts/inter-latin.woff2') format('woff2');
  unicode-range:U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,
    U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD;
}
@font-face{
  font-family:'InterVar';font-style:normal;font-weight:400 700;font-display:swap;
  src:url('/fonts/inter-latin-ext.woff2') format('woff2');
  unicode-range:U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,
    U+0308,U+0329,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C0,
    U+2113,U+2C60-2C7F,U+A720-A7FF;
}
:root{
  --paper:#F6F0E3;--paper-deep:#EFE6D2;--card:#FFFCF4;
  --ink:#2B2118;--ink-soft:#7A6A55;--line:#E2D6BD;
  --oxblood:#7E2A33;--oxblood-deep:#5E1F26;
  --gold:#B8862B;--gold-soft:#F0E2C2;
  --moss:#48663F;--slate:#43617E;--stamp-grey:#9A8F7C;
  --night:#241811;--night-2:#33241A;
  /* The brand faces first, then a fallback chosen to be metrically close so the
     swap moves as little as possible. Indic text falls through to the system
     stack on purpose — see fonts/README.md. */
  --serif:'Fraunces','Iowan Old Style','Palatino Linotype',Palatino,Georgia,'Times New Roman',serif;
  --sans:'InterVar',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;
}
*{margin:0;padding:0;box-sizing:border-box}
/* The renderer builds cards out of <a><span>…</span></a> rather than nested
   divs, because an <a> may not contain block-level flow content in valid HTML.
   Spans are inline by default, so every span that is meant to be a LINE in a
   stacked card has to be told so — otherwise the lines run together and text
   wraps mid-phrase ("Marathi 100 / books"). One rule instead of a dozen. */
.bk .bt,.bk .ba,.cvw,.feat .eyebrow,.feat .fa,
.tcard .ti .lg,.tcard .ti .t,.tcard .ti .m,
.pair .side .t,.pair .side .m,
.srow .st,.srow .sa{display:block}
html{-webkit-text-size-adjust:100%}
body{font-family:var(--sans);color:var(--ink);background:var(--paper);line-height:1.5;
  -webkit-font-smoothing:antialiased}
a{color:inherit;text-decoration:none}
img{max-width:100%;display:block}
.serif{font-family:var(--serif)}
.wrap{max-width:1180px;margin:0 auto;padding:0 22px}
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}

/* skip link — keyboard users shouldn't tab the whole header on every page */
.skip{position:absolute;left:-9999px;top:0;background:var(--oxblood);color:var(--paper);
  padding:10px 16px;z-index:100;border-radius:0 0 8px 0}
.skip:focus{left:0}

/* ---------- header ---------- */
.shead{background:var(--card);border-bottom:1px solid var(--line);position:sticky;top:0;z-index:40}
.shead-in{max-width:1180px;margin:0 auto;padding:11px 22px;display:flex;align-items:center;gap:18px;flex-wrap:wrap}
.brand{display:flex;align-items:center;gap:10px;flex-shrink:0}
.brand img{width:32px;height:32px}
.brand .bn{font-family:var(--serif);font-weight:600;font-size:19px;line-height:1.05}
.brand .bn small{display:block;font-family:var(--sans);font-size:7.5px;font-weight:700;
  letter-spacing:.22em;text-transform:uppercase;color:var(--gold);margin-top:3px}
.snav{display:flex;gap:17px;font-size:13.5px;font-weight:500;color:var(--ink-soft)}
.snav a:hover{color:var(--oxblood)}
.snav a[aria-current]{color:var(--oxblood);font-weight:600;border-bottom:2px solid var(--gold);padding-bottom:2px}
.hsearch{flex:1;min-width:180px;max-width:420px;margin-left:auto;display:flex}
.hsearch input{flex:1;background:var(--paper-deep);border:1px solid var(--line);border-right:0;
  border-radius:999px 0 0 999px;padding:8px 15px;font:inherit;font-size:13px;color:var(--ink);min-width:0}
.hsearch input::placeholder{color:#a3937c}
.hsearch button{background:var(--paper-deep);border:1px solid var(--line);border-left:0;
  border-radius:0 999px 999px 0;padding:0 15px;font:inherit;font-size:13px;color:var(--ink-soft);cursor:pointer}
.hsearch button:hover{color:var(--oxblood)}
.btn-app{background:var(--oxblood);color:#F6F0E3;font-size:12.5px;font-weight:600;
  padding:9px 17px;border-radius:999px;white-space:nowrap}
.btn-ghost{border:1px solid var(--line);background:var(--card);color:var(--ink);font-size:12.5px;
  font-weight:600;padding:8px 16px;border-radius:999px;display:inline-block}
.btn-ghost:hover{border-color:var(--oxblood);color:var(--oxblood)}

/* ---------- breadcrumb ---------- */
.crumb{padding:13px 0 0;font-size:12px;color:var(--ink-soft);display:flex;gap:7px;flex-wrap:wrap;align-items:center}
.crumb a{color:var(--oxblood);border-bottom:1px solid rgba(126,42,51,.25)}
.crumb .sep{color:#bcae94}

/* ---------- section heads ---------- */
.sec{margin-top:34px}
.sec-h{display:flex;align-items:baseline;justify-content:space-between;gap:14px;
  border-bottom:1px solid var(--line);padding-bottom:9px;margin-bottom:18px}
.sec-h h2,.sec-h h3{font-family:var(--serif);font-size:20px;font-weight:600}
.sec-h .more{font-size:12px;font-weight:600;color:var(--oxblood);white-space:nowrap}
.eyebrow{font-size:9.5px;font-weight:700;letter-spacing:.2em;text-transform:uppercase;color:var(--ink-soft)}

/* ---------- covers ---------- */
.cv{display:block;aspect-ratio:2/3;border-radius:3px 7px 7px 3px;position:relative;overflow:hidden;
  box-shadow:0 7px 18px rgba(43,33,24,.26);background:var(--paper-deep);width:100%}
.cv::before{content:"";position:absolute;left:0;top:0;bottom:0;width:4px;background:rgba(0,0,0,.22);z-index:3}
/* The image sits ON TOP of the typeset cover, so a cover URL that 404s (plenty
   of the hotlinked OpenLibrary ones do) reveals the typeset one underneath
   instead of a blank box. No JS, no onerror. */
.cv img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;z-index:2}
.cv .ct{position:absolute;inset:0;display:flex;flex-direction:column;justify-content:center;
  padding:11% 9%;text-align:center;gap:7%;background:linear-gradient(155deg,#7E2A33,#4E181F);color:#F0E2C2}
.cv .ct .t{font-family:var(--serif);font-size:13px;font-weight:600;line-height:1.22}
.cv .ct .a{font-size:8px;letter-spacing:.11em;text-transform:uppercase;opacity:.78;font-weight:600}
.cv.g1 .ct{background:linear-gradient(155deg,#7E2A33,#4E181F)}
.cv.g2 .ct{background:linear-gradient(155deg,#43617E,#25384A);color:#DCE7F0}
.cv.g3 .ct{background:linear-gradient(155deg,#48663F,#2A3E24);color:#E3EAD9}
.cv.g4 .ct{background:linear-gradient(155deg,#B8862B,#7A5713);color:#FFF6E0}
.cv.g5 .ct{background:linear-gradient(155deg,#33241A,#1A1009);color:#E9DCC2}
.cv.g6 .ct{background:linear-gradient(155deg,#8C5A3C,#553220);color:#F5E4D4}
.cv.g7 .ct{background:linear-gradient(155deg,#5C4A73,#33264A);color:#E7DEF2}
.cv.g8 .ct{background:linear-gradient(155deg,#2F6360,#153A38);color:#D8ECEA}

/* ---------- the cover viewer ---------- */
/* Tapping the hero cover opens both sides of the book full-screen. The track is
   a scroll-snap row, so swiping is the browser's own behaviour and costs no
   script; the arrows and chips are fragment links, and the overlay is open
   while one of its slides is the :target. */
.cvh{position:relative}
.cvz{display:block}
/* The back cover, tucked at the corner of the front — the app's own shelf
   gesture (book_detail_screen.dart), and the shape a reader already knows.
   It is the same URL the viewer's second slide uses, so the one download
   serves both and opening the viewer is instant; fetchpriority=low keeps
   those bytes behind the hero cover, which is the page's LCP. */
/* z-index 4 is not decoration: .cv is positioned but makes no stacking
   context, so the front cover's own layers escape into this one — its image
   sits at 2 and the spine rule at 3, and a thumbnail with no z-index at all
   was painted UNDER the cover it is supposed to be tucked against. */
.cvb{position:absolute;right:-8px;bottom:-8px;z-index:4;width:clamp(58px,34%,86px);display:block;
  border-radius:2px 5px 5px 2px;overflow:hidden;box-shadow:0 4px 14px rgba(43,33,24,.34);
  outline:2px solid var(--paper)}
.cvb img{display:block;width:100%;aspect-ratio:2/3;object-fit:cover}
.cvv{display:none}
.cvv:has(:target){display:block;position:fixed;inset:0;z-index:90;background:rgba(20,13,8,.94)}
.cvt{display:flex;height:100%;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none}
.cvt::-webkit-scrollbar{display:none}
.cvs{flex:0 0 100%;scroll-snap-align:center;display:flex;flex-direction:column;
  align-items:center;justify-content:center;gap:14px;padding:60px 18px 26px}
/* Lazy inside a hidden container: the photograph is fetched when the viewer is
   opened, never on the page view. min-height reserves the frame so opening it
   on a slow connection shows a box filling, not an empty screen. */
.cvs img{max-width:min(720px,100%);max-height:76vh;min-height:38vh;object-fit:contain;
  border-radius:5px;background:rgba(246,240,227,.07);box-shadow:0 18px 50px rgba(0,0,0,.5)}
.cvs figcaption{display:flex;gap:18px;color:#9d8f79;font-size:12px;letter-spacing:.03em}
.cvs figcaption b{color:#F0E2C2;font-weight:600}
.cvs figcaption a{color:#C9A45C;border-bottom:1px solid rgba(201,164,92,.4)}
.cvx,.cvn{position:fixed;display:flex;align-items:center;justify-content:center;border-radius:999px;
  background:rgba(246,240,227,.14);color:#F6F0E3}
.cvx{top:14px;right:16px;width:38px;height:38px;font-size:21px}
.cvn{top:50%;transform:translateY(-50%);width:44px;height:44px;font-size:26px;line-height:1}
.cvn.p{left:12px}
.cvn.n{right:12px}
/* On a phone the sides are the image's own margins and swiping is the
   natural gesture — the Front/Back links under the photograph are the
   affordance there, and arrows would only sit on top of the cover. */
@media(max-width:700px){.cvn{display:none}}
/* Older browsers (pre-:has) get one side at a time — same links, no swipe. */
@supports not selector(:has(*)){
  .cvs:target{display:flex;position:fixed;inset:0;z-index:90;background:rgba(20,13,8,.94)}
  .cvs{display:none}
}

/* ---------- grids ---------- */
.strip{display:grid;grid-template-columns:repeat(auto-fill,minmax(122px,1fr));gap:18px}
.bk .bt{font-family:var(--serif);font-size:13.5px;font-weight:600;margin-top:9px;line-height:1.3}
.bk:hover .bt{color:var(--oxblood)}
.bk .ba{font-size:11.5px;color:var(--ink-soft);margin-top:2px}
/* The rating chip worn on the cover itself — dark scrim + gold so it reads
   over photo covers and every typeset tone alike, in both site themes. */
.cv .rt{position:absolute;left:6px;bottom:6px;z-index:3;padding:2px 7px;border-radius:999px;
  background:rgba(22,13,7,.78);color:#D1A04A;font-size:10px;font-weight:700;letter-spacing:.02em;line-height:1.6}

/* ---------- people directory ---------- */
/* A grid of names whose lengths vary wildly ("Ruskin Bond" beside "Rasipuram
   Krishnaswamy Narayan"). Without a floor on the name box, a two-line name
   pushes its book count down and the counts stop lining up across the row —
   which is what made the first version look untidy. Each cell is a flex column
   with the name clamped to two lines, so every count sits on the same baseline
   whatever the name does. */
.people{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:22px 16px}
.person{display:flex;flex-direction:column;align-items:center;text-align:center}
.person .ppl{width:64px;height:64px;font-size:24px;margin-bottom:10px}
.person .pn{font-family:var(--serif);font-size:14px;font-weight:600;line-height:1.3;
  display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;
  min-height:2.6em}
.person:hover .pn{color:var(--oxblood)}
.person .pc{font-size:11.5px;color:var(--ink-soft);margin-top:4px}
.person .pl{font-size:10.5px;color:var(--gold);font-weight:700;margin-top:2px}

/* ---------- pills, chips, stars ---------- */
.pill{font-size:10.5px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;
  padding:4px 10px;border-radius:999px;display:inline-block}
.p-ox{background:#F2DEDA;color:var(--oxblood)}
.p-gold{background:#F2E6C4;color:#8F681E}
.p-moss{background:#E3EAD9;color:var(--moss)}
.p-slate{background:#DEE7EF;color:var(--slate)}
.p-grey{background:#EAE4D6;color:var(--stamp-grey)}
.chip{font-size:11.5px;font-weight:600;padding:5px 12px;border-radius:999px;
  border:1px solid var(--line);background:var(--card);color:var(--ink-soft);display:inline-block}
.chip:hover{border-color:var(--oxblood);color:var(--oxblood)}
.chip[aria-current]{background:var(--oxblood);border-color:var(--oxblood);color:#F6F0E3}
.chips{display:flex;gap:7px;flex-wrap:wrap}
.stars{display:flex;align-items:center;gap:8px}
.stars .s{font-size:16px;letter-spacing:1.5px;color:var(--gold)}
.stars .s .off{color:#DCD0B6}
.stars .n{font-size:12.5px;color:var(--ink-soft);font-weight:600}

/* ---------- book page ---------- */
.bhero{display:grid;grid-template-columns:1fr;gap:26px;margin-top:20px;align-items:start}
@media(min-width:760px){.bhero{grid-template-columns:212px 1fr;gap:32px}}
@media(min-width:1040px){.bhero{grid-template-columns:212px 1fr 232px}}
.bhero h1{font-family:var(--serif);font-size:clamp(27px,6vw,36px);font-weight:600;line-height:1.14}
.bhero .native{font-family:var(--serif);font-size:clamp(17px,4vw,22px);color:var(--ink-soft);margin-top:7px}
.bhero .by{font-size:15px;margin-top:14px}
.bhero .by a{color:var(--oxblood);font-weight:600;border-bottom:1px solid rgba(126,42,51,.3)}
.bhero .by .tr{color:var(--ink-soft);font-size:13.5px;display:block;margin-top:4px}
.rating-row{display:flex;align-items:center;gap:16px;margin-top:16px;flex-wrap:wrap}
.rating-row .big{font-family:var(--serif);font-size:31px;font-weight:700;line-height:1}
.rating-row .big span{font-size:14px;color:var(--ink-soft);font-weight:400}
.facts{margin-top:17px;display:flex;flex-wrap:wrap;gap:7px 22px;font-size:13px;color:var(--ink-soft)}
.facts b{color:var(--ink);font-weight:600}
.blurb{margin-top:17px;font-size:14.5px;line-height:1.78;color:#4a3d2e;max-width:640px}
.act{display:flex;gap:10px;margin-top:20px;flex-wrap:wrap}
.act .prim{background:var(--oxblood);color:#F6F0E3;font-size:13.5px;font-weight:600;
  padding:11px 22px;border-radius:999px;box-shadow:0 5px 14px rgba(126,42,51,.28)}
.rail{background:var(--card);border:1px solid var(--line);border-radius:13px;overflow:hidden;margin-bottom:14px}
.rail .rh{background:var(--paper-deep);padding:10px 15px;font-size:9.5px;font-weight:700;
  letter-spacing:.18em;text-transform:uppercase;color:var(--ink-soft);border-bottom:1px solid var(--line)}
.rail .rb{padding:12px 15px}
.rail .kv{display:flex;justify-content:space-between;gap:12px;padding:6px 0;font-size:12.5px}
.rail .kv .k{color:var(--ink-soft);flex-shrink:0}
.rail .kv .v{font-weight:600;text-align:right;word-break:break-word}
/* The Amazon button — squid-ink card, white lowercase wordmark over the
   orange smile, and an orange pill CTA. Deliberately the one loud, branded
   element on the page: recognisable at a glance, which is what earns the
   click (owner decision, 9 Aug 2026 — Amazon only). */
.rail .amzn{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;
  gap:10px 12px;margin:2px 0 8px;padding:13px 16px;border-radius:12px;background:#131921;
  color:#fff;text-decoration:none;transition:box-shadow .15s ease}
.rail .amzn:hover{box-shadow:0 6px 18px rgba(19,25,33,.38);background:#1c2733}
.rail .amzn .wm{display:inline-flex;flex-direction:column;align-items:flex-start;
  font-weight:800;font-size:19px;letter-spacing:-.5px;line-height:1}
.rail .amzn .wm .sm{width:44px;height:11px;color:#FF9900;margin:2px 0 0 2px;display:block}
.rail .amzn .go{background:#FFA41C;color:#131921;font-weight:800;font-size:12.5px;
  padding:8px 13px;border-radius:999px;white-space:nowrap}
.rail .buydisc{padding:5px 0 7px;font-size:10.5px;font-style:italic;color:var(--ink-soft)}
.rail.dark{background:linear-gradient(150deg,var(--night-2),var(--night));border-color:var(--night)}
.rail.dark .rh{background:transparent;color:var(--gold);border-bottom-color:rgba(240,226,194,.16)}
.rail.dark .rb{color:#CBB897;font-size:12.5px;line-height:1.7}

/* ---------- translation module (the signature block) ---------- */
.trans{background:linear-gradient(160deg,#FFFCF4,#F6EFDD);border:1px solid var(--gold);
  border-radius:14px;overflow:hidden;display:flex}
.trans .rule{width:4px;background:var(--gold);flex-shrink:0}
.trans .tin{padding:18px 20px;flex:1;min-width:0}
.trans .th{display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}
.trans .grp{margin-left:auto;font-size:11.5px;color:var(--ink-soft)}
.trans .grp b{color:var(--gold);font-weight:700}
.tg{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:13px;margin-top:14px}
.tcard{background:var(--card);border:1px solid var(--line);border-radius:11px;padding:12px;
  display:flex;gap:12px;align-items:center}
.tcard:hover{border-color:var(--gold)}
.tcard .cvw{width:48px;flex-shrink:0}
.tcard .ti{flex:1;min-width:0}
.tcard .ti .lg{font-size:9.5px;font-weight:700;letter-spacing:.16em;text-transform:uppercase;color:var(--gold)}
.tcard .ti .t{font-family:var(--serif);font-size:15px;font-weight:600;margin-top:3px;line-height:1.25}
.tcard .ti .m{font-size:11.5px;color:var(--ink-soft);margin-top:3px}
.tcard.orig{border-color:var(--gold);background:linear-gradient(160deg,#FFFCF4,#FBF4E4)}

/* ---------- editions ---------- */
.eds{border:1px solid var(--line);border-radius:12px;overflow:hidden;background:var(--card)}
.ed{display:grid;grid-template-columns:44px 1fr;gap:12px 14px;align-items:center;
  padding:12px 14px;border-bottom:1px solid var(--line);font-size:13px}
/* On a phone the facts are their own row under the publisher — three grid
   children of their own would flow into the 44px cover column. */
.edf{grid-column:1/-1;display:flex;flex-wrap:wrap;gap:10px 26px;align-items:center}
@media(min-width:700px){
  .ed{grid-template-columns:44px 1fr auto}
  .edf{grid-column:auto;display:grid;grid-template-columns:128px 92px 88px;gap:0}
}
.ed:last-child{border-bottom:0}
.ed:nth-child(even){background:#FDFAF1}
.ed .et{font-family:var(--serif);font-size:14px;font-weight:600;line-height:1.28}
.ed .em{font-size:11.5px;color:var(--ink-soft);margin-top:2px}
.ed .col{font-size:12.5px;color:var(--ink-soft)}
.ed .col b{display:block;color:var(--ink);font-weight:600;font-size:13px}

/* ---------- ratings + reviews ---------- */
.ratings{display:grid;grid-template-columns:1fr;gap:22px;align-items:center;margin-bottom:22px}
@media(min-width:620px){.ratings{grid-template-columns:180px 1fr;gap:30px}}
.score{text-align:center}
/* DIRECT child only. stars() renders its own .n ("4.4 · 312 ratings")
   inside this block, and a descendant selector set that to 48px serif too —
   so the average was drawn twice, the second copy landing on top of the star
   row (owner report, 1 Sep 2026). */
.score>.n{font-family:var(--serif);font-size:48px;font-weight:700;line-height:1}
/* …and the star row's number is redundant under a 48px copy of itself. The
   screen-reader text lives in its own .sr span, so this hides nothing but ink. */
.score .stars .n{display:none}
.score .stars{justify-content:center}
.score .of{font-size:12.5px;color:var(--ink-soft);margin-top:4px}
.hist{display:flex;flex-direction:column;gap:6px}
.hbar{display:flex;align-items:center;gap:10px;font-size:12px}
.hbar .lb{width:32px;color:var(--ink-soft);font-weight:600;text-align:right}
.hbar .tr{flex:1;height:9px;background:var(--paper-deep);border-radius:999px;overflow:hidden}
.hbar .fl{height:100%;background:var(--gold);border-radius:999px}
.hbar>.ct{width:40px;font-size:11.5px;color:var(--ink-soft);text-align:right}
.rev{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;margin-bottom:13px}
.rev .rhd{display:flex;align-items:center;gap:11px}
.rev .av{width:34px;height:34px;border-radius:50%;background:var(--paper-deep);
  display:flex;align-items:center;justify-content:center;font-family:var(--serif);
  font-size:14px;color:var(--ink-soft);flex-shrink:0;border:1px solid var(--line)}
.rev .who{font-weight:600;font-size:13.5px}
.rev .when{font-size:11.5px;color:var(--ink-soft);margin-top:1px}
.rev .rs{margin-left:auto;font-size:14px;color:var(--gold);letter-spacing:1px}
.rev>.rt{font-family:var(--serif);font-size:14.5px;line-height:1.75;color:#4a3d2e;margin-top:11px;font-style:italic}

/* ---------- facts table ---------- */
.ftab{border:1px solid var(--line);border-radius:12px;overflow:hidden;background:var(--card);
  display:grid;grid-template-columns:1fr}
@media(min-width:700px){.ftab{grid-template-columns:1fr 1fr}}
.ftab .r{display:flex;gap:14px;padding:11px 16px;border-bottom:1px solid var(--line);font-size:13px}
.ftab .k{width:128px;color:var(--ink-soft);flex-shrink:0}
.ftab .v{font-weight:500}
.ftab .v a{color:var(--oxblood);border-bottom:1px solid rgba(126,42,51,.25)}

/* ---------- home ---------- */
.hhero{background:linear-gradient(180deg,var(--paper-deep),var(--paper));
  border-bottom:1px solid var(--line);padding:34px 0 32px}
.hhero-in{display:grid;grid-template-columns:1fr;gap:30px;align-items:center}
@media(min-width:900px){.hhero-in{grid-template-columns:1.25fr .95fr;gap:44px}}
.hh-l h1{font-family:var(--serif);font-size:clamp(28px,5.5vw,38px);font-weight:600;line-height:1.16}
.hh-l h1 em{font-style:italic;color:var(--oxblood)}
.hh-l p{color:var(--ink-soft);font-size:15px;line-height:1.7;margin-top:13px;max-width:520px}
.bigsearch{margin-top:20px;display:flex;max-width:540px;box-shadow:0 6px 18px rgba(43,33,24,.09);border-radius:999px}
.bigsearch input{flex:1;background:var(--card);border:1.5px solid var(--line);border-right:0;
  border-radius:999px 0 0 999px;padding:13px 20px;font:inherit;font-size:14.5px;min-width:0}
.bigsearch button{background:var(--oxblood);color:#F6F0E3;border:1.5px solid var(--oxblood);
  border-radius:0 999px 999px 0;padding:0 24px;font:inherit;font-size:13px;font-weight:600;cursor:pointer}
.hint{margin-top:11px;font-size:12.5px;color:var(--ink-soft)}
.hint b{color:var(--oxblood);font-weight:600}
.feat{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px;
  display:flex;gap:16px;box-shadow:0 10px 28px rgba(43,33,24,.13);position:relative;overflow:hidden}
.feat::after{content:"";position:absolute;left:0;top:0;bottom:0;width:3px;background:var(--gold)}
.feat .cvw{width:96px;flex-shrink:0}
.feat h2{font-family:var(--serif);font-size:19px;font-weight:600;margin-top:5px;line-height:1.24}
.feat .fa{font-size:12.5px;color:var(--ink-soft);margin-top:3px}
.feat .fq{font-family:var(--serif);font-style:italic;font-size:13px;color:#6d5f4b;
  line-height:1.6;margin-top:9px;border-left:2px solid var(--gold-soft);padding-left:11px}
.langs{display:grid;grid-template-columns:repeat(auto-fill,minmax(104px,1fr));gap:11px}
.lang{background:var(--card);border:1px solid var(--line);border-radius:11px;padding:13px 10px;text-align:center}
.lang:hover{border-color:var(--gold)}
/* These are spans in the markup, so they must be told to stack — left inline
   they flow together and the count wraps as "Marathi 100 / books". */
.lang .n{display:block;font-family:var(--serif);font-size:16px;line-height:1.2}
.lang .c{display:block;font-size:10px;color:var(--gold);font-weight:700;margin-top:4px;letter-spacing:.04em}
.pairs{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px}
.pair{background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden;display:flex}
.pair:hover{border-color:var(--gold)}
.pair .rule{width:3px;background:var(--gold);flex-shrink:0}
.pair .in{padding:13px 15px;display:flex;align-items:center;gap:12px;flex:1;min-width:0}
.pair .cvw{width:44px;flex-shrink:0}
.pair .side{flex:1;min-width:0}
.pair .side .t{font-family:var(--serif);font-size:14px;font-weight:600;line-height:1.26}
.pair .side .m{font-size:11px;color:var(--ink-soft);margin-top:3px}
.pair .arrow{color:var(--gold);font-size:17px;flex-shrink:0}
.appband{background:linear-gradient(135deg,var(--night-2),var(--night));color:#E9DCC2;
  border-radius:14px;padding:24px 26px;display:flex;align-items:center;justify-content:space-between;gap:24px;flex-wrap:wrap}
.appband h2{font-family:var(--serif);font-size:21px;font-weight:600;color:#F6F0E3}
.appband p{font-size:13px;color:#CBB897;margin-top:7px;line-height:1.65;max-width:520px}
/* The store buttons. Deliberately the same object as the pair on /app
   (landing-page/app.html) — same two-line label, same inline marks, same
   paper-on-night treatment — because a reader who meets one and then the other
   should be meeting the same button, not a family resemblance. Keep the two in
   step when either changes. */
.appband .stores{display:flex;gap:12px;flex-wrap:wrap}
.appband .store{display:flex;align-items:center;gap:11px;text-align:left;
  background:var(--paper);color:var(--ink);border:1px solid var(--paper);border-radius:14px;
  padding:11px 18px;min-width:186px;text-decoration:none}
.appband .store .ic{flex-shrink:0}
.appband .store small{display:block;font-size:9.5px;font-weight:700;letter-spacing:.12em;
  text-transform:uppercase;color:var(--oxblood)}
.appband .store span span{font-size:15.5px;font-weight:700}
.appband a.store:hover{background:#FFFCF4;border-color:#FFFCF4}
/* The half that has no store yet. An outline instead of a fill, and not an <a>:
   a badge that goes nowhere teaches a reader to distrust the one beside it. */
.appband .store.ghost{background:transparent;color:var(--paper);
  border:1.5px solid rgba(246,240,227,.45)}
.appband .store.ghost small{color:var(--gold)}
.appband .store.off{cursor:default}

/* ---------- hubs ---------- */
.hubhead{background:linear-gradient(170deg,var(--paper-deep),var(--paper));
  border-bottom:1px solid var(--line);padding:28px 0}
.hubhead-in{display:grid;grid-template-columns:1fr;gap:26px;align-items:start}
@media(min-width:900px){.hubhead-in{grid-template-columns:1fr 290px;gap:40px}}
.hubhead h1{font-family:var(--serif);font-size:clamp(26px,5vw,35px);font-weight:600;line-height:1.14}
.hubhead h1 .nat{display:block;font-size:.82em;color:var(--oxblood);margin-bottom:5px}
.intro{font-size:14.5px;line-height:1.78;color:#4a3d2e;margin-top:14px;max-width:660px}
.intro a{color:var(--oxblood);border-bottom:1px solid rgba(126,42,51,.28)}
.hubstats{background:var(--card);border:1px solid var(--line);border-radius:13px;padding:16px 18px}
.hubstats .st{display:flex;justify-content:space-between;padding:7px 0;font-size:13px;border-bottom:1px solid var(--line)}
.hubstats .st:last-child{border-bottom:0}
.hubstats .st b{font-family:var(--serif);font-size:17px;font-weight:700}
.hubstats .k{color:var(--ink-soft)}
.toolbar{display:flex;align-items:center;gap:9px;flex-wrap:wrap;padding:16px 0;
  border-bottom:1px solid var(--line);margin-bottom:20px}
.toolbar .cnt{font-size:12.5px;color:var(--ink-soft);margin-left:auto}
/* Browse's filter bar (docs/browse-filters-mockups.html, direction C + A's
   sort): a segmented sort control, then one <details> door per facet whose
   popover holds ONLY that facet — small panels, never a wall. Zero JS: the
   popover links are in the DOM regardless, and name="facet" gives native
   one-open-at-a-time. The bar is the positioning context, so every popover
   spans the bar's own width and can't overflow a small screen. */
.fbar{position:relative;display:flex;align-items:center;gap:8px;flex-wrap:wrap;
  padding:12px 0;border-top:1px solid var(--line);border-bottom:1px solid var(--line);
  margin:16px 0 20px}
.fbar .cnt{font-size:12.5px;color:var(--ink-soft);margin-left:auto}
.seg{display:inline-flex;border:1px solid var(--line);border-radius:10px;overflow:hidden;
  background:var(--card);max-width:100%;overflow-x:auto;scrollbar-width:none;
  /* min-width:0 lets the flex item shrink below its ~430px of nowrap sort
     labels on narrow screens — without it the bar can't wrap and the whole
     page scrolls sideways; with it the control scrolls inside itself. */
  min-width:0}
.seg::-webkit-scrollbar{display:none}
.seg a{padding:7px 12px;font-size:11.5px;font-weight:600;color:var(--ink-soft);
  border-right:1px solid var(--line);white-space:nowrap}
.seg a:last-child{border-right:0}
.seg a[aria-current]{background:var(--oxblood);color:#F6F0E3}
.fdoor summary{list-style:none;cursor:pointer;display:inline-flex;gap:6px;align-items:center;
  border:1px solid var(--line);background:var(--card);border-radius:10px;padding:6px 12px;
  font-size:12px;font-weight:600;color:var(--ink);white-space:nowrap}
.fdoor summary::-webkit-details-marker{display:none}
.fdoor summary i{font-style:normal;font-size:9px;color:var(--ink-soft)}
.fdoor.live summary{background:var(--oxblood);border-color:var(--oxblood);color:#F6F0E3}
.fdoor.live summary i{color:#E9C9CC}
.fdoor[open] summary{border-color:var(--oxblood);color:var(--oxblood);
  box-shadow:0 0 0 1px var(--oxblood)}
.fdoor.live[open] summary{color:#F6F0E3}
.fdoor .pop{position:absolute;left:0;right:0;top:calc(100% + 8px);z-index:5;
  background:var(--card);border:1px solid var(--line);border-radius:12px;
  box-shadow:0 16px 40px rgba(43,33,24,.22);padding:8px 10px}
.pop .cols{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:0 16px}
.pop .row{display:flex;justify-content:space-between;align-items:center;gap:12px;
  font-size:12.5px;font-weight:500;color:var(--ink);padding:6px 9px;border-radius:7px}
.pop .row:hover{background:var(--paper-deep);color:var(--ink)}
.pop .row i{font-style:normal;font-size:11px;color:var(--ink-soft)}
.pop .row[aria-current]{background:var(--oxblood);color:#F6F0E3;font-weight:600}
.pop .row[aria-current] i{color:#E9C9CC}
.pop .foot{border-top:1px solid var(--line);margin-top:8px;padding:8px 9px 3px;
  display:flex;justify-content:space-between;gap:12px}
.pop .foot a{font-size:11.5px;font-weight:600;color:var(--oxblood)}
.pager{display:flex;gap:6px;justify-content:center;margin-top:26px;align-items:center;flex-wrap:wrap}
.pager a,.pager span{border:1px solid var(--line);background:var(--card);border-radius:8px;padding:7px 13px;
  font-size:12.5px;font-weight:600;color:var(--ink-soft)}
.pager a:hover{border-color:var(--oxblood);color:var(--oxblood)}
.pager [aria-current]{background:var(--oxblood);border-color:var(--oxblood);color:#F6F0E3}
.pager .el{border:0;background:none;padding:0 4px}

/* ---------- author / publisher ---------- */
.ahero{display:grid;grid-template-columns:1fr;gap:24px;margin-top:22px;align-items:start}
@media(min-width:720px){.ahero{grid-template-columns:168px 1fr}}
@media(min-width:1040px){.ahero{grid-template-columns:168px 1fr 240px;gap:34px}}
.portrait{width:100%;max-width:168px;aspect-ratio:1;border-radius:14px;
  background:linear-gradient(155deg,#8C7355,#5A4530);display:flex;align-items:center;justify-content:center;
  font-family:var(--serif);font-size:52px;color:#F0E2C2;box-shadow:0 10px 26px rgba(43,33,24,.26);overflow:hidden}
.portrait img{width:100%;height:100%;object-fit:cover}
.ahero h1{font-family:var(--serif);font-size:clamp(25px,5vw,34px);font-weight:600;line-height:1.15}
.badge-kit{display:inline-flex;align-items:center;gap:6px;background:#F2E6C4;color:#8F681E;
  font-size:11px;font-weight:700;padding:5px 12px;border-radius:999px;letter-spacing:.04em}
.timeline{display:flex;gap:2px;margin-top:6px;border-top:1px solid var(--line);padding-top:16px;align-items:flex-end}
.tl{flex:1;text-align:center}
.tl .b{width:100%;background:var(--gold-soft);border:1px solid var(--gold);border-bottom:0;border-radius:3px 3px 0 0}
.tl .y{font-size:10.5px;color:var(--ink-soft);font-weight:600;margin-top:6px}

/* ---------- search ---------- */
.sres{display:grid;grid-template-columns:1fr;gap:26px;margin-top:20px}
@media(min-width:900px){.sres{grid-template-columns:1fr 250px;gap:30px}}
.sgroup{margin-bottom:24px}
.sgh{display:flex;align-items:baseline;gap:11px;margin-bottom:11px}
.sgh h2{font-family:var(--serif);font-size:18px;font-weight:600}
.sgh .ct{font-size:11.5px;color:var(--ink-soft)}
.srow{display:flex;gap:15px;padding:13px 0;border-bottom:1px solid var(--line)}
.srow .cvw{width:52px;flex-shrink:0}
.srow .si{flex:1;min-width:0}
.srow .st{font-family:var(--serif);font-size:16px;font-weight:600;line-height:1.25}
.srow:hover .st{color:var(--oxblood)}
.srow .sa{font-size:12.5px;color:var(--ink-soft);margin-top:3px}
.srow .sm{font-size:11.5px;color:var(--ink-soft);margin-top:6px;display:flex;gap:9px;flex-wrap:wrap;align-items:center}
.ppl{width:52px;height:52px;border-radius:50%;background:var(--paper-deep);border:1px solid var(--line);
  display:flex;align-items:center;justify-content:center;font-family:var(--serif);font-size:19px;
  color:var(--ink-soft);flex-shrink:0;overflow:hidden}
.ppl img{width:100%;height:100%;object-fit:cover}
.matchline{background:#F2E6C4;color:#8F681E;font-size:10.5px;font-weight:700;letter-spacing:.04em;
  padding:3px 9px;border-radius:999px;display:inline-block}
.facets{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:15px}
.facets h2{font-size:9.5px;letter-spacing:.18em;text-transform:uppercase;color:var(--ink-soft);margin-bottom:10px}
.facets .fr{display:flex;justify-content:space-between;font-size:13px;padding:6px 0}
.facets .fr span{color:var(--ink-soft);font-size:11.5px}
.facets .fr:hover{color:var(--oxblood)}

/* ---------- empty / thin ---------- */
.thin{text-align:center;padding:42px 22px;background:var(--card);border:1px dashed var(--line);border-radius:14px}
.thin .fl{font-size:22px;color:var(--gold);margin-bottom:12px}
.thin h1,.thin h2{font-family:var(--serif);font-size:22px;font-weight:600}
.thin p{color:var(--ink-soft);font-size:14px;line-height:1.72;max-width:480px;margin:11px auto 0}

/* ---------- footer ---------- */
.sfoot{background:var(--night);color:#B8A88C;padding:30px 0;margin-top:44px}
.sfoot-in{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:26px}
.sfoot h2{font-size:9.5px;letter-spacing:.2em;text-transform:uppercase;color:var(--gold);margin-bottom:10px}
.sfoot a,.sfoot p{display:block;font-size:12.5px;color:#B8A88C;line-height:2}
.sfoot a:hover{color:#F0E2C2}
.sfoot .fb{font-family:var(--serif);font-size:17px;color:#F6F0E3;margin-bottom:6px}
.sfoot .legal{margin-top:22px;padding-top:16px;border-top:1px solid rgba(240,226,194,.14);
  font-size:11.5px;color:#8a7a62}

@media(prefers-reduced-motion:no-preference){
  .bk,.tcard,.lang,.pair{transition:.15s}
}
`;
