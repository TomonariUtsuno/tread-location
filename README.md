# tread

写真作品「tread」に関連する、車輪の取得位置を閲覧するためのウェブマップです。

## Features

- 地図上のピンから車輪番号と写真を表示
- 車輪番号一覧から取得位置へ移動
- スマートフォンでの閲覧に対応

## Website

https://tomonariutsuno.github.io/tread-location/

## Technology

- HTML
- CSS
- JavaScript
- Leaflet
- OpenStreetMap

## Data maintenance

[`wheels.json`](wheels.json) is the canonical catalogue. [`data.js`](data.js) is a
generated browser compatibility file and must not be edited directly.

Run the following from the repository root before committing data changes:

```sh
python3 -B scripts/generate-data-js.py
python3 scripts/validate-wheels.py
python3 -B scripts/generate-data-js.py --check
python3 -B -m unittest discover -s tests
```

The catalogue validates the published image contract: PNG, 533 × 800 px, 8-bit RGB
without alpha, stored as `wheels/wNNN.png`. It also checks wheel number and image-path
uniqueness, coordinate bounds, missing references, and unused image files. GitHub
Actions runs these checks only; it never changes or deploys repository content.

The future updater accepts one coordinate field in either of these forms:

```text
N34°31'22.98" E135°36'27.93"
34.52305000, 135.60775833
```

It normalizes common Unicode punctuation and whitespace, then stores only the resulting
decimal `lat` and `lng` values in `wheels.json`. The original input text is intentionally
kept only in the updater's unsaved draft: it is presentation-specific and would make the
canonical geographical data inconsistent. Ambiguous or invalid input is reported rather
than silently reordered or corrected.

## Local draft updater (macOS)

The local SwiftUI updater is a draft-only tool: it reads `wheels.json` and images for
validation and map preview, but never writes repository data, images, or GitHub.
It uses only macOS frameworks and does not rely on system Python when it runs.

From the repository root on a Mac with Xcode installed:

```sh
swift run TreadUpdater
```

Use `swift test` to run the Swift regression tests. The same coordinate-case fixture is
also exercised by the Python validation tests, so both implementations remain aligned.

## Installable macOS app

### Normal use

On a Mac with Xcode (or its command-line tools) installed, create the app from the
repository root:

```sh
./scripts/build-macos-app.sh
```

This creates [`dist/Tread Updater.app`](dist/Tread%20Updater.app). In Finder, drag that
app to `/Applications`, then double-click it to launch. Re-run the same command after an
updater change, quit the old copy, and replace the app in `/Applications` with the newly
generated one.

The app is a Universal Binary for Apple Silicon and Intel Macs. Its Finder/Dock icon is
generated from `Packaging/AppIcon-master.png`, the supplied 6090 × 6053 px RGBA master.
The generator preserves the image's aspect ratio and transparent pixels, centers it on a
square transparent canvas, converts the output to sRGB, and writes all standard macOS
icon sizes; it never crops or redraws the artwork.

GitHub authentication is stored only in the macOS Keychain. Never paste a PAT into chat,
Git, this README, logs, screenshots, or any other shared text. A locally built app is
ad-hoc signed but is not notarized. macOS may ask you to confirm the first launch; use
Finder's **Open** command only after verifying that the app came from your local build.
The installable app and `swift run` use separate, stable Keychain service identifiers, so
their credentials cannot be confused. Register authentication separately in the version
you intend to use; no Keychain sharing entitlement is requested.

### Developer and verification details

`scripts/build-macos-app.sh` builds the Swift Package in release mode for both `arm64`
and `x86_64`, embeds `wheels.json` and the unmodified `wheels/` image directory inside the
app, produces an ICNS resource, and applies an ad-hoc signature. It does not need an
Xcode project, a Python runtime at app launch, a developer certificate, or any external
service. The app uses its bundled catalogue when launched from Finder and the repository
catalogue when launched with `swift run` in a working tree.

Verify an existing build with:

```sh
./scripts/verify-macos-app.sh
lipo -archs "dist/Tread Updater.app/Contents/MacOS/TreadUpdater"
```

For development troubleshooting, start the unbundled app at the repository root with
`swift run TreadUpdater`. Run `swift test` for Swift tests and the commands in
[Data maintenance](#data-maintenance) for the Python and catalogue checks.

The local signature is sufficient for personal installation on the building Mac, but it
is not a Developer ID signature or Apple notarization. Before distributing the app to
other people, use a Developer ID certificate and Apple notarization; do not add Apple ID,
certificates, private keys, or PATs to this repository or to build scripts.

## GitHub publishing preparation

The updater's publish flow is intentionally explicit: it first fetches the current
`main` HEAD, shows the complete confirmation plan, rechecks that HEAD immediately before
publishing, then creates image blobs, a tree, and one commit before a non-force ref
update. A failure before the ref update cannot partially publish images or data.

Before using publishing for the first time, create a GitHub fine-grained personal access
token limited to `TomonariUtsuno/tread-location`, with **Contents: Read and write**.
Register it in the updater's GitHub authentication screen. The updater stores it only in
the macOS Keychain, never in this repository, `UserDefaults`, logs, or a settings file.
The publish flow is tested with mocks; no token is required to build or test the app.

## Copyright

Photographs and project content © 2026 Tomonari Utsuno.  
Map data © OpenStreetMap contributors.
