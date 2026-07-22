# `.well-known/` — universal / app-link association files

These two files let the Kitabi app claim `https://kitabi.in/b/*`, `/a/*` and `/p/*`
links (and the same paths on `www.kitabi.in`) so tapping a share link opens the app
instead of the browser. Both are served by Cloudflare Pages at
`https://kitabi.in/.well-known/…` — `apple-app-site-association` is deliberately
extension-less.

Both files are **filled in and live**. The app side has been ready since `cc25e72`:
the iOS entitlement (`applinks:kitabi.in`, `applinks:www.kitabi.in`), the Android
`autoVerify` intent filter, and the in-app listener (`app/lib/core/deep_links.dart`,
which routes `/b|a|p/:id` and survives a cold start).

## `apple-app-site-association` (iOS)

- `appID` is `62686X3746.in.kitabi.kitabi` — Apple Team ID + bundle id. The Team ID
  matches `DEVELOPMENT_TEAM` in `app/ios/Runner.xcodeproj/project.pbxproj`.
- Must be served as `application/json`, over HTTPS, with **no redirect**. Cloudflare
  Pages serves extension-less files as `application/octet-stream`, which iOS silently
  refuses — so `landing-page/_headers` sets the content type explicitly. If you ever
  move hosts, re-check this header first; the failure mode is invisible (the link just
  opens Safari, with no error anywhere).
- iOS fetches this through Apple's CDN and caches it. After changing it, a device may
  keep the old copy for up to ~24h. To force a refresh while testing, delete and
  reinstall the app, or use a development build (which fetches directly).

## `assetlinks.json` (Android)

Lists three SHA-256 fingerprints — all three are needed, because the certificate that
signs the installed app differs by how it was installed:

| Key | Fingerprint starts | Covers |
|---|---|---|
| **Play app signing key** (Google-managed) | `56:B8:7E:5D…` | **everyone who installs from the Play Store** |
| Upload key (`~/keys/kitabi-upload.jks`, alias `upload`) | `0E:BA:38:93…` | release builds installed directly (sideloaded AAB/APK) |
| Local debug key (`~/.android/debug.keystore`) | `FB:6E:F3:3D…` | `flutter run` / emulator builds, so links can be tested in dev |

The Play entry is the one that matters in production: Play re-signs the uploaded AAB
with Google's own key, so the upload-key fingerprint does *not* cover Play installs.
It came from Play Console → **Protected with Play** → Play Store protection → app
signing (Google moved this out of the old Test and release → App integrity page).

Note that page lists **MD5 (16 bytes), SHA-1 (20 bytes) and SHA-256 (32 bytes)**
fingerprints. Only SHA-256 belongs here — a SHA-1 in this array is not merely ignored,
it can invalidate the whole statement and take the working fingerprints down with it.
Count the colon-separated pairs before adding one: 32, or it's the wrong row.

Keep every entry a well-formed colon-separated uppercase hex fingerprint — a malformed
string can invalidate the whole statement, taking the valid fingerprints down with it.
That's why no placeholder is left in the array.

Before public launch, consider dropping the debug fingerprint — it only exists so links
can be tested on a dev build.

## Verifying

```bash
# Both must return content-type: application/json
curl -sI https://kitabi.in/.well-known/apple-app-site-association | grep -i content-type
curl -sI https://kitabi.in/.well-known/assetlinks.json | grep -i content-type
```

Google's own verifier should list the app:

```bash
curl -s "https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://kitabi.in&relation=delegate_permission/common.handle_all_urls"
```

On an Android device, check verification with:

```bash
adb shell pm get-app-links in.kitabi.kitabi
```

`kitabi.in` should read `verified`. If it reads `legacy_failure` or a numeric error,
the fingerprint doesn't match the installed build's signature — usually the
Play-signing case above.
