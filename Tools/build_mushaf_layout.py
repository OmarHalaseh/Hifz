#!/usr/bin/env python3
"""
Build Hifz/Resources/mushaf-layout.json — the KFGQPC 15-line Madani mushaf
line-layout asset (the deferred "P4" line data). This is what lets the app
memorize by row / quarter-page / half-page / page instead of by ayah.

Provenance & correctness policy (see Tools/README.md):
  * Line layout ORIGIN: the King Fahd Glorious Qur'an Printing Complex "Madani"
    mushaf — 604 pages, 15 lines/page, Hafs 'an 'Asim. The per-line word ranges
    are the QPC (Quranic Universal Library / KFGQPC) 15-line layout.
  * We consume a redistribution of that layout as per-page JSON:
      https://github.com/zonetecde/mushaf-layout  (pinned commit below)
    Each page lists its lines; every text line carries a `verseRange`, its words
    (`location` = "surah:ayah:word"), and the printed line `text`.
  * Independent cross-check: the set of ayahs the layout places on each page is
    verified, per page, against the bundled quran.json page numbering (Tanzil
    Madani 604). Any disagreement is printed and aborts the build.
  * A SHA-256 over the canonical line data is embedded and printed so a unit test
    can pin it; re-running this script must reproduce the same hash.

Emitted schema (terse keys, matching the quran.json convention):
  { "meta": {...},
    "pages": [ { "p": 1, "lines": [
        { "l": 1, "k": "h", "s": 1 },          # surah header (s = surah number)
        { "l": 2, "k": "b" },                  # basmala
        { "l": 3, "k": "t", "segs": [[s,a,wf,wt], ...], "t": "..." }  # ayah text
    ] } ] }

Usage:  python3 Tools/build_mushaf_layout.py
Inputs are downloaded to Tools/.cache/ (reused if already present).
"""
import json, os, sys, hashlib, subprocess, tarfile

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache")
OUT = os.path.join(HERE, "..", "Hifz", "Resources", "mushaf-layout.json")
QURAN = os.path.join(HERE, "..", "Hifz", "Resources", "quran.json")

# Pinned redistribution of the QPC/KFGQPC 15-line Madani layout.
REPO = "zonetecde/mushaf-layout"
COMMIT = "72116ce4d405d67823804f0eed795c1e6409b4af"
TARBALL = f"https://codeload.github.com/{REPO}/tar.gz/{COMMIT}"
TOTAL_PAGES = 604


def fetch(url, name):
    # curl (present on macOS, reliable TLS) rather than urllib, whose framework
    # build here lacks a CA bundle — same policy as build_quran_asset.py.
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print(f"  downloading {name} ...")
        subprocess.run(
            ["curl", "-sfL", "--max-time", "180", "-A", "hifz-asset-builder", "-o", path, url],
            check=True,
        )
    return path


def load_pages(tar_path):
    """Return {page_number: raw page dict} from the pinned tarball."""
    pages = {}
    with tarfile.open(tar_path, "r:gz") as tf:
        for m in tf.getmembers():
            # .../mushaf/page-XXX.json
            if not m.isfile() or "/mushaf/page-" not in m.name or not m.name.endswith(".json"):
                continue
            num = int(os.path.basename(m.name)[len("page-"):-len(".json")])
            pages[num] = json.load(tf.extractfile(m))
    return pages


def segments(words):
    """Collapse a line's words into contiguous per-ayah segments.

    Each word `location` is "surah:ayah:word" (word 1-based within the ayah).
    Returns [[surah, ayah, wordFrom, wordTo], ...] in reading order.
    """
    segs = []
    for w in words:
        s, a, wi = (int(x) for x in w["location"].split(":"))
        if segs and segs[-1][0] == s and segs[-1][1] == a:
            segs[-1][3] = max(segs[-1][3], wi)
            segs[-1][2] = min(segs[-1][2], wi)
        else:
            segs.append([s, a, wi, wi])
    return segs


def build_line(raw):
    kind = raw["type"]
    if kind == "surah-header":
        return {"l": raw["line"], "k": "h", "s": int(raw["surah"])}
    if kind == "basmala":
        return {"l": raw["line"], "k": "b"}
    if kind == "text":
        return {"l": raw["line"], "k": "t",
                "segs": segments(raw["words"]), "t": raw["text"]}
    raise ValueError(f"unknown line type {kind!r} on line {raw.get('line')}")


def canonical(pages_out):
    """Deterministic serialization the Swift loader re-hashes to catch corruption."""
    lines = []
    for pg in pages_out:
        for ln in pg["lines"]:
            if ln["k"] == "h":
                lines.append(f"{pg['p']}|{ln['l']}|h|{ln['s']}")
            elif ln["k"] == "b":
                lines.append(f"{pg['p']}|{ln['l']}|b|")
            else:
                segs = ",".join(f"{s}:{a}:{wf}:{wt}" for s, a, wf, wt in ln["segs"])
                lines.append(f"{pg['p']}|{ln['l']}|t|{segs}|{ln['t']}")
    return "\n".join(lines)


def main():
    print(f"Fetching mushaf layout ({REPO}@{COMMIT[:7]}) ...")
    raw_pages = load_pages(fetch(TARBALL, f"mushaf-layout-{COMMIT[:7]}.tar.gz"))
    assert len(raw_pages) == TOTAL_PAGES, f"expected {TOTAL_PAGES} pages, got {len(raw_pages)}"

    pages_out, total_lines = [], 0
    for p in range(1, TOTAL_PAGES + 1):
        raw = raw_pages[p]
        assert raw["page"] == p, f"page file {p} declares page {raw['page']}"
        out_lines = [build_line(ln) for ln in raw["lines"]]
        # line numbers must be 1..N contiguous and in order
        nums = [ln["l"] for ln in out_lines]
        assert nums == list(range(1, len(nums) + 1)), f"page {p} line numbers {nums}"
        pages_out.append({"p": p, "lines": out_lines})
        total_lines += len(out_lines)

    # --- cross-check page coverage vs bundled quran.json (Tanzil Madani 604) ---
    quran = json.load(open(QURAN, encoding="utf-8"))
    quran_page = {}  # page -> set of (surah, ayah)
    for s in quran["surahs"]:
        for a in s["ayahs"]:
            quran_page.setdefault(a["page"], set()).add((s["number"], a["n"]))
    layout_page = {}
    for pg in pages_out:
        acc = set()
        for ln in pg["lines"]:
            if ln["k"] == "t":
                for s, a, _, _ in ln["segs"]:
                    acc.add((s, a))
        layout_page[pg["p"]] = acc

    mismatches = [p for p in range(1, TOTAL_PAGES + 1)
                  if layout_page[p] != quran_page.get(p, set())]
    print(f"  page coverage vs quran.json: {TOTAL_PAGES - len(mismatches)}/{TOTAL_PAGES} pages agree")
    if mismatches:
        print("ABORT: layout/quran.json disagree on which ayahs sit on these pages:",
              file=sys.stderr)
        for p in mismatches[:8]:
            only_layout = sorted(layout_page[p] - quran_page.get(p, set()))
            only_quran = sorted(quran_page.get(p, set()) - layout_page[p])
            print(f"   page {p}: layout-only={only_layout} quran-only={only_quran}", file=sys.stderr)
        sys.exit(1)

    sha = hashlib.sha256(canonical(pages_out).encode("utf-8")).hexdigest()

    asset = {
        "meta": {
            "mushaf": "KFGQPC Madani — 604 pages, 15 lines/page, Hafs 'an 'Asim",
            "layoutOrigin": "KFGQPC / Quranic Universal Library (QUL) QPC 15-line layout",
            "layoutSource": f"github.com/{REPO}@{COMMIT}",
            "pageNumbering": "Madani 604 (verified against bundled quran.json)",
            "pages": TOTAL_PAGES,
            "totalLines": total_lines,
            "layoutSHA256": sha,
        },
        "pages": pages_out,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(asset, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(OUT)
    print(f"\nWROTE {os.path.relpath(OUT, os.path.join(HERE, '..'))}  "
          f"({size/1024:.0f} KB, {TOTAL_PAGES} pages, {total_lines} lines)")
    print(f"Layout SHA-256: {sha}")
    print("Verification PASSED: 604 pages, contiguous line numbers, page coverage matches quran.json.")


if __name__ == "__main__":
    main()
