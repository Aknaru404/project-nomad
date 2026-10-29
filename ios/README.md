# NOMAD for iPad

A native iPadOS app that runs a subset of Project NOMAD entirely on the iPad, with no server and no internet once your content is loaded.

| Tab | What it does | Replaces on the server |
|---|---|---|
| Library | Reads Kiwix `.zim` files (Wikipedia, medical references, books) with title search | Kiwix |
| Maps | Shows `.pmtiles` region maps with the NOMAD base style | ProtoMaps / map service |
| Notes | Markdown notes saved as `.md` files | FlatNotes |
| Data Tools | Bundled CyberChef | CyberChef |

Not included: AI chat, Kolibri, Supply Depot, benchmark, automatic updates. These need the Docker stack.

## Get the app onto an iPad (free Apple ID)

GitHub Actions builds an unsigned app. A sideloading tool signs it with your own Apple ID when it installs it.

1. On GitHub, open **Actions > Build iPad App**, pick the latest green run and download the `NOMAD-unsigned-ipa` artifact. Unzip it to get `NOMAD-unsigned.ipa`.
2. Install [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io) on a Mac or Windows PC.
3. Connect the iPad by cable, drag the `.ipa` into the tool, and sign in with your Apple ID.
4. On the iPad, enable **Settings > Privacy & Security > Developer Mode** (iPadOS asks for a restart), then trust your Apple ID under **Settings > General > VPN & Device Management**.
5. Re-sign every 7 days. A free Apple ID's signature expires after 7 days. AltStore can refresh it automatically over Wi-Fi.

A paid Apple Developer account removes the 7-day limit and allows TestFlight.

## Load content

Content files stay on the iPad. Either:

- tap **Import** in the Library or Maps tab and pick the file, or
- copy files in the Files app to **On My iPad > NOMAD > ZIM** or **> Maps**. This is better for multi-GB files.

Where to get content:

- **ZIM files:** [download.kiwix.org/zim](https://download.kiwix.org/zim/), or copy them from a NOMAD server's storage.
- **Maps:** copy the `.pmtiles` files a NOMAD server has downloaded, or extract a region with the [pmtiles CLI](https://docs.protomaps.com/pmtiles/cli) (`pmtiles extract`).

## Build locally (Mac with Xcode 16+)

```bash
cd ios
./scripts/fetch-assets.sh        # MapLibre, PMTiles, NOMAD map styles/fonts, CyberChef
brew install xcodegen
xcodegen generate                # writes NOMAD.xcodeproj
open NOMAD.xcodeproj             # set your Team under Signing, then Run on the iPad
```

ZIM reader tests: `cd ios/ZimKit && swift test`.

## Layout

- `ZimKit/`: Swift package that reads ZIM files directly (zstd and xz clusters, old and new namespace schemes, title index search). Its tests use a fixture built with `Tests/make_fixture.py`.
- `NOMAD/`: the SwiftUI app.
  - `zim://` and `nomad://` URL scheme handlers feed web content to `WKWebView`.
  - `nomad://` supports HTTP byte ranges, which PMTiles needs.
- `NOMAD/Resources/Web/`: the MapLibre map page. It builds its style the same way as `admin/app/services/map_service.ts`.
- `project.yml`: the XcodeGen project spec.
- `scripts/fetch-assets.sh`: downloads the pinned third-party assets, which are not committed.
