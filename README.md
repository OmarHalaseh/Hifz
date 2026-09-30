# Hifz

[![Tests](https://github.com/OmarHalaseh/Hifz/actions/workflows/test.yml/badge.svg)](https://github.com/OmarHalaseh/Hifz/actions/workflows/test.yml)

Hifz is an iOS app for memorizing the Quran the way it is traditionally taught:
the **Sabaq / Sabqi / Manzil** cycle — today's new lesson, the recent material
still being consolidated, and the long-term review of everything already
memorized. It is built in SwiftUI and SwiftData, tracks memorization at the
level of the individual ayah, and schedules revision by **mushaf page** with
spaced repetition, so what you learn keeps coming back at the right moment
instead of quietly slipping away. All data stays on the device.

## Build

Requires Xcode and iOS 18 or later. The Xcode project is generated from
`project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not
checked in, so generate it first:

```sh
brew install xcodegen
xcodegen generate
open Hifz.xcodeproj
```

Re-run `xcodegen generate` after adding or removing source files.

## How it works

Memorization is tracked per ayah, but **revision is scheduled per mushaf page**.
A page's state — how fresh it is, its review interval, how solid it feels — is
derived by aggregating the spaced-repetition state of the ayahs printed on it,
so there is no separate page bookkeeping to drift out of sync.

An ayah moves through three tiers:

- **Sabaq** — the new lesson. Its size is yours to set (a row, quarter-page,
  half-page or full page) and flexes a little with your recent accuracy.
- **Sabqi** — pages memorized within the last **7 days**, recited in full every
  day, ahead of the long-term cycle.
- **Manzil** — the long-term rotation, under a **hard 30-day cap**:

  ```
  nextDue = lastReviewed + min(spacedRepetitionInterval, 30)
  ```

  which guarantees every memorized page — and therefore every surah — is
  revisited at least once a month. A mistake shrinks a page's interval so it
  returns sooner; flawless recall grows it, but never past the cap.

The daily Manzil load is budgeted in **lines**, never in surahs. A long surah
such as Al-Baqara spans many pages and is split across days, while each page
keeps its own ≤30-day guarantee independently. When more is due than the budget
allows, the most overdue pages go first, so no page can starve.

## Data sources & credits

The Quran data in `Hifz/Resources/` is third-party and is **not** covered by
this project's MIT license (see `LICENSE`). It is built by the scripts in
`Tools/`, each of which documents its own provenance and verification policy.

**`quran.json`** — built by `Tools/build_quran_asset.py`

- **Arabic text:** [Tanzil](https://tanzil.net) Uthmani (Hafs), with pause
  marks. This is the origin of truth and is used **unmodified** — a memorization
  app cannot afford a single wrong harakah, so the text comes from Tanzil
  directly rather than from a convenience API. A SHA-256 over the canonical
  Arabic is embedded in the asset and pinned by a unit test.
- **Page, juz and sajda numbering:** Tanzil metadata (Madani mushaf, 604 pages,
  30 juz).
- **English translation:** Saheeh International, via
  [alquran.cloud](https://alquran.cloud) (`en.sahih`).
- **Transliteration:** [alquran.cloud](https://alquran.cloud)
  (`en.transliteration`).
- **Cross-check:** alquran.cloud, a separately maintained Tanzil derivative, is
  fetched only to verify per-ayah that the consonantal skeleton and the
  page/juz numbering agree. Any real disagreement aborts the build.

**`quran-tajweed.json`** — built by `Tools/build_tajweed_asset.py`

- **Tajweed markup:** the `quran-tajweed` edition via
  [alquran.cloud](https://alquran.cloud) (Tanzil's coloured tajweed text). It is
  kept as a separate companion asset so the verified Arabic in `quran.json` is
  never touched; the reader falls back to plain text if it is absent. Every
  ayah's consonantal skeleton is checked against `quran.json` at build time.

**`mushaf-layout.json`** — built by `Tools/build_mushaf_layout.py`

- **Line layout:** the King Fahd Glorious Qur'an Printing Complex (KFGQPC)
  "Madani" mushaf — 604 pages, 15 lines per page, Hafs ʻan ʻĀsim. The per-line
  word ranges are the QPC (Quranic Universal Library / KFGQPC) 15-line layout,
  consumed as a pinned redistribution from
  [zonetecde/mushaf-layout](https://github.com/zonetecde/mushaf-layout). The
  ayahs the layout places on each page are verified page by page against the
  Tanzil page numbering in `quran.json`.

Ayah recitation audio is streamed from [everyayah.com](https://everyayah.com)
and is not redistributed with the app.

Jazākum Allāhu khayran to Tanzil, the KFGQPC, alquran.cloud and everyayah.com,
whose work this app depends on.
