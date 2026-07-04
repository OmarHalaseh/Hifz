#!/usr/bin/env python3
"""
Build Hifz/Resources/quran.json — the verified Quran reference asset (A1).

Provenance & correctness policy (see Tools/README.md):
  * Arabic text ORIGIN OF TRUTH: tanzil.net Uthmani (Hafs), with pause marks.
    This is a memorization app; a single wrong harakah teaches an error, so the
    text comes from the Tanzil origin — never from a convenience API response.
  * Independent cross-check: alquran.cloud (a separately maintained Tanzil
    derivative) is fetched ONLY to verify, per-ayah, that the consonantal
    skeleton (rasm) and the page/juz numbering agree. Any real disagreement is
    printed and aborts the build rather than being silently accepted.
  * Page/juz/sajda numbering: Tanzil metadata (Madani mushaf, 604 pages, 30 juz).
  * Translation: alquran.cloud en.sahih (Saheeh International).
  * Transliteration: alquran.cloud en.transliteration.
  * A SHA-256 over the canonical Arabic is embedded in the asset and printed so a
    unit test can pin it; re-running this script must reproduce the same hash.

Target mushaf (documented, must match P4 rendering): King Fahd Glorious Qur'an
Printing Complex "Madani" mushaf — 604 pages, 15 lines/page, Hafs 'an 'Asim.
NOTE: this asset ships ayah->page (604) but NOT ayah->line. Faithful 15-line line
positions require word-level QCF layout data and are deferred to a P4-prep task;
shipping an approximate line map would violate "must match exactly".

Usage:  python3 Tools/build_quran_asset.py
Inputs are downloaded to Tools/.cache/ (reused if already present).
"""
import json, os, sys, hashlib, unicodedata, subprocess, xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache")
OUT = os.path.join(HERE, "..", "Hifz", "Resources", "quran.json")

TANZIL_TEXT = ("https://tanzil.net/pub/download/index.php"
               "?marks=true&sajdah=true&rukoo=false&quranType=uthmani&outType=txt-2&agree=true")
TANZIL_META = "https://tanzil.net/res/text/metadata/quran-data.xml"
AQC = "https://api.alquran.cloud/v1/quran/{}"


def fetch(url, name):
    # Uses curl (present on macOS, reliable TLS) rather than urllib, whose
    # framework build here lacks a CA bundle.
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print(f"  downloading {name} ...")
        subprocess.run(
            ["curl", "-sfL", "--max-time", "90", "-A", "hifz-asset-builder", "-o", path, url],
            check=True,
        )
    return path


def load_tanzil(path):
    d = {}
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        p = line.split("|")
        if len(p) == 3:
            d[(int(p[0]), int(p[1]))] = p[2].replace("﻿", "").strip()
    return d


def load_aqc(path):
    d = json.load(open(path, encoding="utf-8"))
    out = {}
    for s in d["data"]["surahs"]:
        for a in s["ayahs"]:
            out[(s["number"], a["numberInSurah"])] = a
    return out


# --- rasm (consonantal skeleton) normalization, for verification only ---
ANNOT = set(range(0x0610, 0x061B)) | set(range(0x06D6, 0x06EE)) | {0x0640, 0x0670, 0x0656, 0x0657, 0x0658}
HAMZA = set("ءأإؤئآ") | {"ٔ", "ٕ"}

def skeleton(t):
    out = []
    for ch in unicodedata.normalize("NFC", t):
        if ch in HAMZA:
            out.append("ٴ"); continue
        if unicodedata.combining(ch) or ord(ch) in ANNOT or ch == " ":
            continue
        if ch in "اٱآأإى":     # unify alef family + alef-maksura carrier
            out.append("ا"); continue
        out.append(ch)
    return "".join(out)


def main():
    print("Fetching sources (origin: tanzil.net; cross-check: alquran.cloud) ...")
    tz = load_tanzil(fetch(TANZIL_TEXT, "tanzil-uthmani.txt"))
    meta_path = fetch(TANZIL_META, "tanzil-metadata.xml")
    aqc_ar = load_aqc(fetch(AQC.format("quran-uthmani"), "aqc_uthmani.json"))
    aqc_en = load_aqc(fetch(AQC.format("en.sahih"), "aqc_sahih.json"))
    aqc_tr = load_aqc(fetch(AQC.format("en.transliteration"), "aqc_translit.json"))

    assert len(tz) == 6236, f"expected 6236 ayahs, got {len(tz)}"

    # Tanzil (and alquran.cloud) prepend the basmala to ayah 1 of every surah
    # except Al-Fatiha (basmala IS its ayah 1) and At-Tawbah (no basmala). In the
    # Hafs/Kufan numbering the basmala is not a counted ayah, so for a per-ayah
    # memorization app we strip it — the reader shows it as a surah header instead.
    # We strip from BOTH sources so the rasm cross-check below stays apples-to-apples.
    def make_stripper(basmala):
        def strip(s, a, t):
            if a == 1 and s not in (1, 9) and t.startswith(basmala):
                return t[len(basmala):].lstrip()
            return t
        return strip
    strip_tz = make_stripper(tz[(1, 1)])
    strip_aqc = make_stripper(aqc_ar[(1, 1)]["text"].replace("﻿", "").strip())
    tz = {k: strip_tz(k[0], k[1], v) for k, v in tz.items()}
    stripped = sum(1 for (s, a) in tz if a == 1 and s not in (1, 9))
    print(f"  stripped prepended basmala from {stripped} surah-opening ayahs")

    # --- metadata: ayah -> page / juz / sajda ---
    root = ET.parse(meta_path).getroot()
    pages = [(int(p.get("sura")), int(p.get("aya"))) for p in root.iter("page")]
    juzs = [(int(j.get("sura")), int(j.get("aya"))) for j in root.iter("juz")]
    sajdas = {(int(s.get("sura")), int(s.get("aya"))) for s in root.iter("sajda")}
    assert len(pages) == 604 and len(juzs) == 30 and len(sajdas) == 15

    order = sorted(tz.keys())  # canonical (sura, aya) order

    def build_map(starts):
        m, cur = {}, 0
        starts_set = {k: i + 1 for i, k in enumerate(starts)}
        for k in order:
            if k in starts_set:
                cur = starts_set[k]
            m[k] = cur
        return m

    page_of = build_map(pages)
    juz_of = build_map(juzs)

    # --- VERIFY against the independent source before writing anything ---
    print("Verifying against independent source (alquran.cloud) ...")
    rasm_mm = [k for k in order
               if skeleton(tz[k]) != skeleton(strip_aqc(k[0], k[1], aqc_ar[k]["text"].replace("﻿", "").strip()))]
    page_mm = [k for k in order if page_of[k] != aqc_ar[k]["page"]]
    juz_mm = [k for k in order if juz_of[k] != aqc_ar[k]["juz"]]
    KNOWN_RASM_OK = {(12, 39), (12, 41)}  # dagger-alif-over-maksura, same word (Yusuf)
    real_rasm = [k for k in rasm_mm if k not in KNOWN_RASM_OK]

    print(f"  rasm  mismatches: {len(rasm_mm)} (known-benign {len(rasm_mm) - len(real_rasm)}, real {len(real_rasm)})")
    print(f"  page  mismatches: {len(page_mm)}")
    print(f"  juz   mismatches: {len(juz_mm)}")
    if real_rasm or page_mm or juz_mm:
        print("ABORT: unresolved character/numbering mismatch — refusing to bundle.", file=sys.stderr)
        for k in (real_rasm + page_mm + juz_mm)[:10]:
            print("   ", k, "tz=", tz[k], file=sys.stderr)
        sys.exit(1)

    # --- structural check: per-surah ayah counts vs surahs.json ---
    surahs_json = json.load(open(os.path.join(HERE, "..", "Hifz", "Resources", "surahs.json"), encoding="utf-8"))
    expected_counts = {s["number"]: s["ayahCount"] for s in surahs_json}
    by_surah = {}
    for (s, a) in order:
        by_surah.setdefault(s, 0)
        by_surah[s] = max(by_surah[s], a)
    for s, cnt in expected_counts.items():
        assert by_surah[s] == cnt, f"surah {s}: {by_surah[s]} ayahs, expected {cnt}"

    # --- canonical checksum over the Arabic text ---
    canonical = "\n".join(f"{s}|{a}|{tz[(s, a)]}" for (s, a) in order)
    sha = hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    # --- assemble asset ---
    surahs_out = []
    for s in range(1, 115):
        ayahs = []
        a = 1
        while (s, a) in tz:
            rec = {"n": a, "ar": tz[(s, a)],
                   "en": aqc_en[(s, a)]["text"].strip(),
                   "tr": aqc_tr[(s, a)]["text"].strip(),
                   "juz": juz_of[(s, a)], "page": page_of[(s, a)]}
            if (s, a) in sajdas:
                rec["sajda"] = True
            ayahs.append(rec)
            a += 1
        surahs_out.append({"number": s, "ayahs": ayahs})

    asset = {
        "meta": {
            "arabicEdition": "Tanzil Uthmani (Hafs), with pause marks",
            "arabicSource": "tanzil.net",
            "translation": "Saheeh International (en.sahih via alquran.cloud)",
            "transliteration": "English transliteration (en.transliteration via alquran.cloud)",
            "mushaf": "KFGQPC Madani — 604 pages, 15 lines/page, Hafs 'an 'Asim",
            "pageNumbering": "Madani 604 (Tanzil metadata)",
            "ayahCount": len(tz),
            "arabicSHA256": sha,
        },
        "surahs": surahs_out,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(asset, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(OUT)
    print(f"\nWROTE {os.path.relpath(OUT, os.path.join(HERE, '..'))}  ({size/1024:.0f} KB, {len(tz)} ayahs)")
    print(f"Arabic SHA-256: {sha}")
    print("Verification PASSED: rasm + page + juz agree with independent source; surah counts match.")


if __name__ == "__main__":
    main()
