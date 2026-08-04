#!/usr/bin/env python3
"""Run the edge renderer's tests without installing anything.

The Pages Functions are ES modules written for the Cloudflare Workers runtime,
and this repo has no node_modules and isn't getting one (CLAUDE.md: the landing
page stays dependency-free, no build step). But "we can't run it" is not an
acceptable reason to ship an untested renderer, so:

  * concatenate the modules in dependency order, stripping `import`/`export`,
  * shim the handful of Workers globals the pure render path touches,
  * execute the result with macOS's built-in JavaScriptCore
    (`osascript -l JavaScript`) — already on every Mac, nothing to install.

This exercises the real rendering code, not a copy of it. What it can't cover is
the runtime plumbing (cache API, real fetch); that gets verified against the
deployed site instead.

    ./landing-page/tests/run.py
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# The last line of the generated program — the harness's result. Under
# JavaScriptCore the value of the final expression is the output; node needs it
# wrapped in console.log, so it's named here and swapped in run_js.
TAIL = "JSON.stringify({passes: __passes, failures: __failures});"

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "functions" / "_lib"

# Dependency order. jsonld imports ORIGIN from layout, so layout comes first.
MODULES = [
    "html.js",
    "css.js",
    "api.js",
    "suggest.js",
    "layout.js",
    "jsonld.js",
    "components.js",
    "pages/book.js",
    "pages/people.js",
    "pages/home.js",
    "pages/discover.js",
    "lists.js",
    "pages/more.js",
]

# Route modules that are worth testing directly (not under _lib).
EXTRA_MODULES = ["img/c.js", "[[path]].js"]

# Handles the multi-line form too — `import {\n  a,\n  b,\n} from '...'` — which a
# single-line pattern silently leaves behind as a syntax error 1,000 lines into
# the generated program.
IMPORT_RE = re.compile(r"^\s*import\s[\s\S]*?from\s*['\"][^'\"]*['\"]\s*;?[ \t]*$", re.MULTILINE)
EXPORT_CONST_RE = re.compile(
    r"^\s*export\s+(?=(?:async\s+)?(?:const|function|class|let|var)\s)", re.MULTILINE
)
EXPORT_BARE_RE = re.compile(r"^\s*export\s*\{[^}]*\}\s*;?\s*$", re.MULTILINE)

# Minimal stand-ins for the Workers globals the render path touches. Response is
# the only one that matters: `page()` returns one, and the tests read its body
# and headers.
SHIM = """
class Headers {
  // Accepts a plain object OR another Headers, because `new Headers(res.headers)`
  // is exactly what layout.unavailable() does and it works in the real runtime.
  constructor(init) {
    this.m = new Map();
    if (init instanceof Headers) { for (const [k, v] of init.m) this.m.set(k, v); }
    else if (init) for (const k in init) this.set(k, init[k]);
  }
  set(k, v) { this.m.set(String(k).toLowerCase(), String(v)); }
  get(k) { const v = this.m.get(String(k).toLowerCase()); return v === undefined ? null : v; }
  has(k) { return this.m.has(String(k).toLowerCase()); }
}
class Response {
  constructor(body, init) {
    this.bodyText = body == null ? '' : String(body);
    this.status = (init && init.status) || 200;
    this.ok = this.status >= 200 && this.status < 300;
    this.headers = new Headers(init && init.headers);
  }
  text() { return this.bodyText; }
}

// JavaScriptCore has no URL constructor (it is a Web API, not ECMAScript), and
// node's differs from the Workers runtime in edge cases. This approximation
// exists so the cover proxy's allowlist logic can be exercised at all — without
// it `allowedSource` threw on every input and returned null, which made every
// rejection assertion pass VACUOUSLY. A security test that passes because the
// function refuses everything is worse than no test.
//
// It is deliberately strict and simple. It is NOT authoritative: the real
// allowlist behaviour is probed against the deployed /img/c endpoint, which runs
// the actual runtime's URL parser. Treat failures here as real and passes here
// as necessary-but-not-sufficient.
class URL {
  constructor(input) {
    const m = /^([a-zA-Z][a-zA-Z0-9+.\-]*:)\/\/(?:([^:@/]*)(?::([^@/]*))?@)?([^:/?#]*)(?::(\d+))?([^?#]*)(\?[^#]*)?(#.*)?$/.exec(
      String(input),
    );
    if (!m) throw new TypeError('Invalid URL');
    this.protocol = m[1].toLowerCase();
    this.username = m[2] || '';
    this.password = m[3] || '';
    this.hostname = (m[4] || '').toLowerCase();
    this.port = m[5] || '';
    this.pathname = m[6] || '';
    this.search = m[7] || '';
    this.hash = m[8] || '';
    this.href = String(input);
  }
  toString() { return this.href; }
}
class Request { constructor(url, init) { this.url = url; this.method = (init && init.method) || 'GET'; } }
const caches = { default: { match() { return null; }, put() {} } };
function fetch() { throw new Error('fetch is not available in the test harness'); }
"""

HARNESS = """
var __failures = [], __passes = 0;
function assert(cond, label) {
  if (cond) { __passes++; } else { __failures.push(label); }
}
function assertIncludes(haystack, needle, label) {
  assert(String(haystack).indexOf(needle) !== -1, label + '  (missing: ' + needle + ')');
}
function assertExcludes(haystack, needle, label) {
  assert(String(haystack).indexOf(needle) === -1, label + '  (unexpectedly present: ' + needle + ')');
}
"""


# Modules other modules pull in wholesale (`import * as ld from './jsonld.js'`).
# Stripping the import leaves the alias undefined, so it's rebuilt from the
# module's real exports — derived, not hand-listed, so adding an export to
# jsonld.js can't quietly break the harness.
NAMESPACE_ALIASES = {"jsonld.js": "ld"}
EXPORTED_NAME_RE = re.compile(
    r"^\s*export\s+(?:async\s+)?(?:function|const|class|let|var)\s+([A-Za-z_$][\w$]*)",
    re.MULTILINE,
)


def build_source() -> str:
    parts = [SHIM, HARNESS]
    for name in MODULES:
        text = (LIB / name).read_text()
        exported = EXPORTED_NAME_RE.findall(text)
        text = IMPORT_RE.sub("", text)
        text = EXPORT_BARE_RE.sub("", text)
        text = EXPORT_CONST_RE.sub("", text)
        parts.append(f"// ===== {name} =====\n{text}")
        alias = NAMESPACE_ALIASES.get(name)
        if alias:
            fields = ", ".join(exported)
            parts.append(f"const {alias} = {{ {fields} }};")
    for name in EXTRA_MODULES:
        text = (ROOT / "functions" / name).read_text()
        text = IMPORT_RE.sub("", text)
        text = EXPORT_BARE_RE.sub("", text)
        text = EXPORT_CONST_RE.sub("", text)
        parts.append(f"// ===== {name} =====\n{text}")
    parts.append((Path(__file__).parent / "cases.js").read_text())
    parts.append(TAIL)
    return "\n".join(parts)


def run_js(source: str) -> subprocess.CompletedProcess:
    """Execute with whatever JS runtime this machine has.

    node on CI (ubuntu runners ship it), JavaScriptCore via osascript on a Mac
    with no node installed. Either way nothing is installed and no package.json
    appears in this repo.
    """
    if shutil.which("node"):
        # The harness prints the result; node needs it on stdout explicitly.
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as fh:
            fh.write(source.replace(TAIL, "console.log(" + TAIL.rstrip(";") + ");"))
            path = fh.name
        try:
            return subprocess.run(["node", path], capture_output=True, text=True)
        finally:
            os.unlink(path)
    if shutil.which("osascript"):
        return subprocess.run(
            ["osascript", "-l", "JavaScript", "-e", source], capture_output=True, text=True
        )
    raise SystemExit("No JavaScript runtime found (need node or macOS osascript).")


def main() -> int:
    source = build_source()
    proc = run_js(source)
    if proc.returncode != 0:
        print("JavaScript failed to execute:\n" + (proc.stderr or proc.stdout), file=sys.stderr)
        return 2

    try:
        result = json.loads(proc.stdout.strip())
    except json.JSONDecodeError:
        print("Unexpected harness output:\n" + proc.stdout, file=sys.stderr)
        return 2

    failures = result["failures"]
    for failure in failures:
        print(f"  FAIL  {failure}")
    total = result["passes"] + len(failures)
    if failures:
        print(f"\n{len(failures)} failed, {result['passes']} passed ({total} assertions)")
        return 1
    print(f"{result['passes']} assertions passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
