<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/banner-dark.svg">
  <img src="docs/images/banner-light.svg" alt="Yeti — an unofficial player for nugs.net, on the Mac and iPhone" width="838">
</picture>

Yeti is an unofficial player for nugs.net. Not affiliated with, authorized, sponsored or endorsed by nugs.net or Apple. Requires your own nugs.net subscription.

[![CI](https://github.com/tsvb/applenugs/actions/workflows/ci.yml/badge.svg)](https://github.com/tsvb/applenugs/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/tsvb/applenugs?label=release&color=F2E27A)](https://github.com/tsvb/applenugs/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-9FABCE)](https://github.com/tsvb/applenugs/releases/latest)
[![License](https://img.shields.io/github/license/tsvb/applenugs?color=9FABCE)](LICENSE)

</div>

Yeti is an unofficial native Mac and iPhone player for [nugs.net](https://nugs.net), built by one person
for one subscription. A real queue, gapless segues so a live set doesn't break at the seams, lossless where
nugs offers it, and whole shows offline on the phone. It plays what your subscription already gives you,
and nothing else.

**Why Yeti?** It's named for the Goose song "Yeti." The project began life as AppleNugs, which is why the
repository, the bundle identifiers and the installed `.app` still carry that name.

**[Download Yeti 1.5 for macOS](https://github.com/tsvb/applenugs/releases/download/v1.5/AppleNugs-1.5.dmg)** — signed
and notarized, opens with no Gatekeeper warning, and updates itself from then on. Requires macOS 14 or
later. [All releases](https://github.com/tsvb/applenugs/releases). The design shown on this page is on
`main` and arrives with the next release; 1.5 predates it.

<img src="docs/images/mac-home.png" alt="Yeti on the Mac: Home with the show that's playing hung on a card in a clear plastic bubble, the nice list of most-played artists, artist photos in the crate, and the dashboard open beside it" width="838">

## The look

The toy aisle. The show you're playing hangs on a peg, sealed in a clear plastic bubble on a card, with a
yellow price sticker on the corner that says what you're actually hearing: "Lossless", and "24/96" once the
decoder confirms it. The play button is a sticker too. Pink foil marks only the things that move with time:
the scrub bar, the progress ring, the sweep across a new track's title. Artists are photos in circles, shows
are square covers, and everything else stays out of the way on a dark night-blue shelf.

## What it does

**Playback.** The next track is resolved and parked in an `AVQueuePlayer` while the current one is still
playing, so a segue lands where the band put it. Lossless first (ALAC, then FLAC), falling through to
MQA, AAC and HLS when a format isn't offered. A real queue you can reorder and clear, and it picks up where you
left off after a relaunch.

**The quality readout is measured, not guessed.** Format, platform tier, sample rate, bit depth, channels
and buffer-ahead come from the decoder. If the dashboard says ALAC 24/96, it is ALAC 24/96.

**Library.** An artist page opens with the artist's photo and one scope at a time — Shows, Videos or
Albums, each with its count — over a filter that takes a venue, a city or a date, as a flat
reverse-chronological list under sticky month headers. Search, follow artists, save shows and videos.

**The nice list.** Home keeps a running tally of who you actually listen to: total hours, and your top
artists by plays and time. A play counts once you've heard half a track or four minutes of it, whichever
comes first. It lives on your device, and you can reset it from the account menu.

**Video.** Pick up where you left off, live and coming-up streams, just-streamed replays, a paged
on-demand grid, chapters, a quality cap, and full screen on the Mac. Audio and video share one playback
arbiter, so they never talk over each other.

**Sign-in on nugs.net's own page.** Browser sign-in — email, Apple, Google, Facebook, SiriusXM — through
`ASWebAuthenticationSession` with OAuth2 Authorization Code and PKCE. The app never asks for, sees or
stores your password. Tokens live in the Keychain and refresh about a minute before they expire.

**System integration.** Media keys, Control Center, AirPods and lock-screen transport via
`MPRemoteCommandCenter`; cover art in the system widget; AirPlay from the now-playing screens.

## The artist library

A catalog of live music is not an album grid. Goose has hundreds of shows in here, and they differ by date
and venue rather than by cover art, so the artist page is a filter over dense one-line rows under sticky
month headers, newest first.

<img src="docs/images/mac-artist.png" alt="The Goose artist page in Yeti on the Mac: the band's photo in a circle beside the name, show and video counts and a Follow button, then a Shows/Videos/Albums picker over a filter field and one-line rows of venue, city and date under month headers" width="838">

## On the phone

The iPhone app shares the same core: a five-tab shell, background audio with lock-screen transport, a
full-screen now-playing card, and a now-playing pill that rides above every screen in Apple's tab-bar
accessory slot, with a progress ring drawn around the artwork.

Download whole shows in the best lossless format offered and they play with no network, gapless
included; the player prefers a local file whenever it has one. Downloads are encrypted on the device and
play only inside Yeti. Launch in airplane mode and it offers to listen offline directly.

<p align="center">
<img src="docs/images/iphone.png" alt="Yeti's full-screen now-playing card on an iPhone: the show's cover sealed in the bubble with a Lossless sticker, the track title, a pink scrub bar and the transport stickers" width="300">
</p>

**On the iPhone Duo**, the unfolded display gets the room it deserves: Home splits into two columns, with
what's playing on the left and your favorites, the nice list and the crate beside it, and the now-playing
screen puts the queue next to the player. Folded, it's the phone app.

<img src="docs/images/duo.png" alt="Yeti on the unfolded iPhone Duo: Home in two columns, the playing show's card on the left and favorite shows' covers and the nice list on the right, with the now-playing pill along the bottom naming the show" width="838">

The iPhone app is **personal-install only** — build it yourself and run it on your own device. There is no
App Store build and no TestFlight.

## Unofficial, and what that means

> [!IMPORTANT]
> Yeti is an independent, unofficial player. It is not affiliated with, authorized, sponsored, or endorsed
> by nugs.net or Apple. It signs in with your own account, identifies itself to nugs.net's servers honestly
> as "Yeti," and plays exactly what your subscription already entitles you to play. Offline downloads are
> encrypted and only playable inside the app. It redistributes nothing and circumvents no DRM. You are
> responsible for complying with the [nugs.net Terms of Use](https://www.nugs.net/terms.html). See
> [NOTICE.md](NOTICE.md).

## Install

Download the [signed DMG](https://github.com/tsvb/applenugs/releases/latest), drag it to Applications, and
let Sparkle handle updates from there. "Check for Updates…" lives under the app menu.

To build it yourself you need **Xcode 27.1 or later** (the iOS app compiles against the iOS 27.1 SDK for
the iPhone Duo layouts; it still runs on iOS 26.1) and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is generated, not committed:

```sh
xcodegen generate
open AppleNugs.xcodeproj   # then ⌘R
```

Sign in on nugs.net's own page in the system browser sheet. Tokens are stored in the Keychain, with a
`chmod 600` file fallback inside the app's own container for unsigned and ad-hoc builds that have no
Keychain entitlement.

## Keyboard control (macOS)

| Key | Action |
| --- | --- |
| <kbd>/</kbd> | Focus search |
| <kbd>space</kbd> | Play / pause |
| <kbd>n</kbd> / <kbd>p</kbd> | Next / previous track |
| <kbd>←</kbd> / <kbd>→</kbd> | Seek −10s / +10s (⇧ for ∓30s) |
| <kbd>0</kbd> | Seek to start |
| <kbd>1</kbd>–<kbd>9</kbd> | Seek to 10%–90% of the track |
| <kbd>Esc</kbd> | Blur a focused input |
| <kbd>⌃⌘→</kbd> / <kbd>⌃⌘←</kbd> | Next / previous (menu) |
| <kbd>⌘⇧F</kbd> | Focus search (menu) |
| <kbd>⌥⌘I</kbd> | Toggle the dashboard panel |
| <kbd>⌥⌘P</kbd> | Open the Now Playing window |

Plain-letter keys go through a window-level event monitor and pass through untouched while a text field
has focus. On the iPhone, transport lives on screen and on the lock screen instead.

<details>
<summary><b>Build it yourself</b> — schemes, the iOS target, tests</summary>

Everything under `AppleNugs/` is shared by both apps except `AppleNugs/macOS/` (Sparkle glue, keyboard
monitor, split-view shell, the dashboard miniplayer) and `AppleNugs/iOS/` (app entry, tab shell,
now-playing screens, the pill, the iPhone Duo arrangement, orientation gate). `project.yml` excludes each
platform directory from the other target; small in-file divergences use `#if os(...)`. The design system
is one token struct, `Theme`, with its parts in `AppleNugs/Theme/Components/`; the design sheets it was
built from are in [`docs/design/`](docs/design/).

Schemes are `AppleNugs` (macOS), `AppleNugs-iOS`, and `AppleNugsTests`. The project must stay
warning-free under `SWIFT_STRICT_CONCURRENCY=complete` on both app schemes.

```sh
xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs -configuration Debug build
```

The committed configuration is **ad-hoc signed** so it builds in CI and on any machine with no Apple
Developer team. Producing a signed, notarized build is covered in [DISTRIBUTION.md](DISTRIBUTION.md).

**iOS, personal install.** A team selected in Xcode is wiped by the next `xcodegen generate`. To make it
stick, export your team ID first:

```sh
export APPLENUGS_TEAM_ID=YOUR_TEAM_ID   # then: xcodegen generate
```

or headless against the simulator:

```sh
xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs-iOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Sparkle is macOS-only; update an iOS install by rebuilding. After the first install, `xcodebuild` against
the device destination plus `xcrun devicectl device install app` does the whole cycle without a cable.

**Tests.** Several hundred pure-logic tests in a host-free bundle — no app launch, no `@testable`:

```sh
xcodebuild test -project AppleNugs.xcodeproj -scheme AppleNugsTests
```

</details>

<details>
<summary><b>Why native, and not a web app</b></summary>

nugs.net's cross-origin (CORS) policy rules out a browser-based client that isn't served from nugs.net
itself. A native app talks to nugs.net directly, so there is no proxy tier to run and nothing of yours
passes through a machine that isn't yours:

```
┌──────────────────────────────┐    TLS    ┌──────────┐
│ Yeti (macOS / iOS)           │ ────────► │ nugs.net │
│ SwiftUI · AVFoundation       │           └──────────┘
│ tokens in the Keychain       │
└──────────────────────────────┘
```

</details>

Details of the nugs.net protocol are intentionally not documented here.

## What's not here

No shuffle and no repeat. There are partial transport-control implementations in the codebase already,
and they want collapsing into one before either of those gets written.

No CONTRIBUTING, no code of conduct, no issue templates, no security policy. This is one person's music
player, and the paperwork would be set dressing. If something is broken,
[open an issue](https://github.com/tsvb/applenugs/issues) and say what it did.

## License

[MIT](LICENSE) for the Yeti source. It covers this code only and grants no rights in nugs.net's or
Apple's services, content, or marks — see [NOTICE.md](NOTICE.md).

Made by [Tim VanBenschoten](https://timvanbenschoten.com).
