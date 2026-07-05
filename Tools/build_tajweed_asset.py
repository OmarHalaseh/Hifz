#!/usr/bin/env python3
"""
Build Hifz/Resources/quran-tajweed.json — the companion tajweed-colouring asset.

This is a SEPARATE asset from quran.json on purpose: the verified Arabic origin
of truth (quran.json `ar`, Tanzil Uthmani, SHA-pinned) is never regenerated or
touched by this tool. The mushaf page view loads this companion only for
colouring; if it is absent the reader falls back to plain text.

  * Source: alquran.cloud `quran-tajweed` edition (Tanzil's coloured tajweed
    text). Fetched to Tools/.cache/ and reused if present.
  * The edition marks rules inline as `[code[covered letters]`, and tags may
    nest; a stack parser turns each ayah into a list of (rule-code, text) runs.
  * Independent cross-check: the consonantal skeleton (rasm) of every ayah is
    compared against quran.json's verified `ar`. Any real disagreement aborts
    the build rather than shipping a mismatched overlay.
  * A SHA-256 over the canonical runs is embedded and printed so a unit test can
    pin it; re-running must reproduce the same hash.

Rule codes (confirmed by enumerating the whole edition) map to tajweed rules in
TajweedText.swift; this tool is colour-agnostic and ships the codes verbatim.

Usage:  python3 Tools/build_tajweed_asset.py
"""
import json, os, re, sys, hashlib, unicodedata, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache")
QURAN = os.path.join(HERE, "..", "Hifz", "Resources", "quran.json")
OUT = os.path.join(HERE, "..", "Hifz", "Resources", "quran-tajweed.json")

TAJWEED_URL = "https://api.alquran.cloud/v1/quran/quran-tajweed"

# The full set of rule codes present in the edition (enumerated at build time).
KNOWN_CODES = set("hnfogpsaqluwicmdb")

# --- rasm (consonantal skeleton) normalization ---
# This compares two legitimately different editions (Tanzil dagger-alef vs the
# tajweed edition), so the skeleton is deliberately coarse: it collapses the
# hamza/alef spelling variants that differ between them (e.g. Tanzil `ءَا` vs
# tajweed `أَ` for al-ākhirah, or dagger alef vs a full alef letter) and keeps
# only the bare consonantal outline. Its job is to catch a misaligned or
# corrupted overlay, not to enforce identical orthography.
ANNOT = set(range(0x0610, 0x061B)) | set(range(0x06D6, 0x06EE)) | {0x0640, 0x0656, 0x0657, 0x0658}
ZW = {0x200C, 0x200D, 0x200E, 0x200F, 0xFEFF}
DROP_HAMZA = set("ءٕٔ")                       # standalone hamza + hamza above/below signs
ALEF = set("اٱآأإىٲٳٮ") | {"ٰ"}              # alef family + maksura (incl. dotless-beh carrier U+066E) + dagger alef


def skeleton(t):
    out = []
    def emit(ch):
        # Collapse consecutive alefs: the two editions differ on whether a long-ā
        # is one glyph or a maqsura carrier plus a dagger alef (e.g. Tanzil
        # `مِيكَىٰلَ` vs tajweed `مِيكَـٰلَ`), which both reduce to a single alef here.
        if ch == "ا" and out and out[-1] == "ا":
            return
        out.append(ch)
    for ch in unicodedata.normalize("NFC", t):
        if ch in DROP_HAMZA:
            continue
        if ch in ALEF:
            emit("ا"); continue
        if ch == "ؤ":
            emit("و"); continue
        if ch == "ئ":
            # hamza on a (dotless-ya / maqsura) seat — one edition writes `ئ`, the
            # other a maqsura + hamza-below; treat the seat as an alef either way.
            emit("ا"); continue
        if unicodedata.combining(ch) or ord(ch) in ANNOT or ord(ch) in ZW or ch == " ":
            continue
        emit(ch)
    return "".join(out)


def fetch(url, name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print(f"  downloading {name} ...")
        subprocess.run(
            ["curl", "-sfL", "--max-time", "90", "-A", "hifz-asset-builder", "-o", path, url],
            check=True,
        )
    return path


_OPEN = re.compile(r'\[([a-zA-Z]+)(?::\d+)?\[')


def parse_runs(t):
    """Turn `[code[...]` markup (possibly nested) into [(code|None, text), ...],
    coalescing adjacent runs with the same active code."""
    runs = []
    stack = []
    i, n = 0, len(t)
    while i < n:
        if t[i] == '[':
            m = _OPEN.match(t, i)
            if m:
                stack.append(m.group(1))
                i = m.end()
                continue
        if t[i] == ']' and stack:
            stack.pop()
            i += 1
            continue
        # Stray formatting brackets (a source glitch: a span marked with no rule
        # code, e.g. `ٱفْتَرَ[ٮٰ]هُ` at 32:3). Arabic text has no ASCII brackets,
        # so drop them and keep the enclosed letters as plain text.
        if t[i] in "[]":
            i += 1
            continue
        code = stack[-1] if stack else None
        if runs and runs[-1][0] == code:
            runs[-1][1].append(t[i])
        else:
            runs.append((code, [t[i]]))
        i += 1
    if stack:
        raise ValueError(f"unbalanced tajweed markup, unclosed {stack}")
    return [(c, "".join(chs)) for c, chs in runs]


def main():
    print("Building companion tajweed asset (source: alquran.cloud quran-tajweed) ...")
    tj = json.load(open(fetch(TAJWEED_URL, "quran-tajweed.json"), encoding="utf-8"))
    text = {(s["number"], a["numberInSurah"]): a["text"]
            for s in tj["data"]["surahs"] for a in s["ayahs"]}
    assert len(text) == 6236, f"expected 6236 ayahs, got {len(text)}"

    # Reference Arabic (verified origin of truth) for the rasm cross-check.
    ref = json.load(open(QURAN, encoding="utf-8"))
    ref_ar = {(s["number"], a["n"]): a["ar"] for s in ref["surahs"] for a in s["ayahs"]}

    order = sorted(text.keys())

    # A couple of surah-opening ayahs (95:1, 97:1) still carry a prepended basmala
    # in the verified asset — Tanzil wrote it as `بِّسْمِ` (extra shadda), so the
    # original stripper's startswith missed them. The tajweed edition has the pure
    # ayah, so strip a leading basmala from the reference before comparing.
    basmala_skel = skeleton(ref_ar[(1, 1)])

    surahs_out = []
    unknown = set()
    rasm_mm = []
    for s in range(1, 115):
        ayahs = []
        a = 1
        while (s, a) in text:
            runs = parse_runs(text[(s, a)])
            for c, _ in runs:
                if c is not None and c not in KNOWN_CODES:
                    unknown.add(c)
            plain = "".join(t for _, t in runs)
            ref_skel = skeleton(ref_ar[(s, a)])
            if a == 1 and s not in (1, 9) and ref_skel.startswith(basmala_skel):
                ref_skel = ref_skel[len(basmala_skel):]
            if skeleton(plain) != ref_skel:
                rasm_mm.append((s, a))
            # compact runs: [code, text]; "" code means "no rule / plain".
            ayahs.append({"n": a, "runs": [[c or "", t] for c, t in runs]})
            a += 1
        surahs_out.append({"number": s, "ayahs": ayahs})

    # Known-benign rasm differences (same words the main asset already whitelists).
    KNOWN_RASM_OK = {(12, 39), (12, 41)}
    real_rasm = [k for k in rasm_mm if k not in KNOWN_RASM_OK]
    print(f"  rasm mismatches vs verified `ar`: {len(rasm_mm)} "
          f"(known-benign {len(rasm_mm) - len(real_rasm)}, real {len(real_rasm)})")
    if unknown:
        print(f"ABORT: unexpected tajweed rule codes {sorted(unknown)}", file=sys.stderr)
        sys.exit(1)
    if real_rasm:
        print("ABORT: tajweed overlay disagrees with verified Arabic — refusing to bundle.",
              file=sys.stderr)
        for k in real_rasm[:10]:
            print("   ", k, "tj=", text[k], file=sys.stderr)
        sys.exit(1)

    # Canonical checksum over the runs (rule code + text, ayah order).
    canonical = "\n".join(
        f"{s['number']}|{a['n']}|" + "".join(f"{c}~{t}|" for c, t in a["runs"])
        for s in surahs_out for a in s["ayahs"]
    )
    sha = hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    asset = {
        "meta": {
            "edition": "quran-tajweed (Tanzil coloured tajweed, via alquran.cloud)",
            "source": "api.alquran.cloud/v1/quran/quran-tajweed",
            "note": "Companion colouring overlay for the mushaf page view; the "
                    "verified Arabic origin of truth lives in quran.json.",
            "ayahCount": len(text),
            "runsSHA256": sha,
        },
        "surahs": surahs_out,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(asset, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(OUT)
    print(f"  wrote {OUT} ({size/1_000_000:.2f} MB)")
    print(f"  runsSHA256 = {sha}")
    print("Done. Pin the hash in HifzTests/TajweedAssetTests.swift if it changed.")


if __name__ == "__main__":
    main()
