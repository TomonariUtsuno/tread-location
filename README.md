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

## Copyright

Photographs and project content © 2026 Tomonari Utsuno.  
Map data © OpenStreetMap contributors.
