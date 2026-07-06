# `.well-known/` — universal / app-link association files

These two files let the Kitabi app claim `https://kitabi.in/b/*`, `/a/*` and `/p/*`
links so tapping a share link opens the app instead of the browser. Both are served
by Cloudflare Pages at `https://kitabi.in/.well-known/…` (no extension rewriting —
`apple-app-site-association` is deliberately extension-less).

Before universal links actually work, **two placeholders must be replaced with real
values**:

## `apple-app-site-association` (iOS)
- `appID` is `TEAMID.in.kitabi.kitabi`. Replace **`TEAMID`** with the real Apple
  Developer **Team ID** (found in the Apple Developer portal → Membership, a 10-char
  string like `A1B2C3D4E5`). Final form: `A1B2C3D4E5.in.kitabi.kitabi`.
- Must be served as `application/json` with **no** `.json` extension and over HTTPS
  with no redirect. Cloudflare Pages serves it correctly as-is.
- The matching `com.apple.developer.associated-domains` entitlement
  (`applinks:kitabi.in`) must be added in the iOS app (Xcode → Signing &
  Capabilities → Associated Domains).

## `assetlinks.json` (Android)
- Replace **`PLACEHOLDER_SHA256_FINGERPRINT`** with the real SHA-256 fingerprint of
  the app's signing certificate. Get it with:
  ```
  keytool -list -v -keystore <your-release.keystore> -alias <alias> | grep SHA256
  ```
  or, for Play App Signing, copy the SHA-256 from Play Console → Setup → App
  integrity → App signing key certificate. Format is uppercase hex, colon-separated:
  `AB:CD:EF:…`.
- You may list multiple fingerprints (debug + release + upload key) in the
  `sha256_cert_fingerprints` array.
- The Android app must declare an intent filter with `android:autoVerify="true"`
  for host `kitabi.in` and paths `/b/*`, `/a/*`, `/p/*`.

Until both placeholders are filled in, the pages still work fine in the browser —
only the "open in app" hand-off is inactive.
