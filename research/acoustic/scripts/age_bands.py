"""Patients and recordings per age band, from metadata only (run download_metadata.sh first).

Bands: <2 months, 2-11 months, 1-5 years (12 months up to the 6th birthday), older, unknown.
Writes results/age_bands.json and prints Markdown tables.
"""
from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
D = HERE / "data"
BANDS = ["<2 mo", "2-11 mo", "1-5 y", "older", "unknown"]


def band_years(age: float | None) -> str:
    if age is None:
        return "unknown"
    if age < 2 / 12:
        return "<2 mo"
    if age < 1:
        return "2-11 mo"
    if age < 6:
        return "1-5 y"
    return "older"


def table(title, rows: dict, cols):
    print(f"\n### {title}\n")
    print("| Band | " + " | ".join(cols) + " |")
    print("|---|" + "---|" * len(cols))
    for b in rows:
        print(f"| {b} | " + " | ".join(str(rows[b].get(c, 0)) for c in cols) + " |")


# ------------------------------------------------------------------ SPRSound
def sprsound():
    repo = D / "sprsound" / "repo"
    recs = {}  # recording id -> dict
    for p in repo.rglob("*.json"):
        if ".git" in p.parts or "example" in p.parts:
            continue
        m = re.match(r"^([^_]*)_([\d.]+)_(\d)_(p\d+)_(\d+)$", p.stem)  # pid is blank when anonymised
        if not m:
            continue
        pid, age, _, loc, rid = m.groups()
        try:
            j = json.loads(p.read_text())
        except Exception:
            continue
        r = recs.setdefault(rid, {"pid": pid, "age": float(age), "events": set(), "record": None,
                                  "folders": set()})
        r["folders"].add(str(p.parent.relative_to(repo)))
        for e in j.get("event_annotation", []) or []:
            r["events"].add(e.get("type"))
        if j.get("record_annotation"):
            r["record"] = j["record_annotation"]
    out = defaultdict(lambda: defaultdict(int))
    pats = defaultdict(lambda: defaultdict(set))
    for rid, r in recs.items():
        b = band_years(r["age"])
        if not r["pid"]:  # anonymised: cannot be grouped by patient, so counted apart
            out[b]["rec_no_patient_id"] += 1
            continue
        pkey = r["pid"]
        out[b]["recordings"] += 1
        pats[b]["patients"].add(pkey)
        ev = r["events"]
        for lab, keys in {"stridor": {"Stridor"}, "wheeze": {"Wheeze", "Wheeze+Crackle"},
                          "crackle": {"Coarse Crackle", "Fine Crackle", "Wheeze+Crackle"},
                          "rhonchi": {"Rhonchi"}}.items():
            if ev & keys:
                out[b][f"rec_{lab}"] += 1
                pats[b][f"pat_{lab}"].add(pkey)
    anon = sum(1 for r in recs.values() if not r["pid"])
    res = {b: {**out[b], **{k: len(v) for k, v in pats[b].items()}} for b in BANDS if b in out}
    all_events = defaultdict(int)
    for r in recs.values():
        for e in r["events"]:
            all_events[e] += 1
    return res, {"unique_recordings": len(recs), "recordings_with_anonymised_pid": anon,
                 "recordings_per_event_type": dict(all_events)}


# ------------------------------------------------------------------ CirCor
CIRCOR_MAP = {"Neonate": "Neonate (0-27 d)", "Infant": "Infant (28 d-1 y)", "Child": "Child (1-11 y)",
              "Adolescent": "Adolescent (12-18 y)", "Young Adult": "Young adult", "": "unknown",
              "nan": "unknown"}


def circor():
    rec_per_pid = defaultdict(int)
    for line in (D / "circor" / "RECORDS").read_text().split():
        rec_per_pid[line.split("/")[-1].split("_")[0]] += 1
    out = defaultdict(lambda: defaultdict(int))
    with open(D / "circor" / "training_data.csv") as f:
        for r in csv.DictReader(f):
            b = CIRCOR_MAP.get(r["Age"].strip(), r["Age"])
            pid = r["Patient ID"]
            out[b]["patients"] += 1
            out[b]["recordings"] += rec_per_pid[pid]
            out[b][f"murmur_{r['Murmur']}"] += 1
            out[b][f"outcome_{r['Outcome']}"] += 1
    return {k: dict(v) for k, v in out.items()}


# ------------------------------------------------------------------ ICBHI
def icbhi():
    ages = {}
    for line in (D / "icbhi" / "ICBHI_Challenge_demographic_information.txt").read_text().splitlines():
        f = line.split()
        if f:
            ages[f[0]] = None if f[1] == "NA" else float(f[1])
    diag = dict(l.split()[:2] for l in (D / "icbhi" / "ICBHI_Challenge_diagnosis.txt").read_text().splitlines() if l.strip())
    out = defaultdict(lambda: defaultdict(int))
    pats = defaultdict(set)
    devices = defaultdict(lambda: defaultdict(int))
    for line in (D / "icbhi" / "ICBHI_challenge_train_test.txt").read_text().splitlines():
        if not line.strip():
            continue
        name = line.split()[0]
        pid = name.split("_")[0]
        b = band_years(ages.get(pid))
        out[b]["recordings"] += 1
        pats[b].add(pid)
        devices[b][name.split("_")[-1]] += 1
    res = {b: {"patients": len(pats[b]), "recordings": out[b]["recordings"],
               "devices": dict(devices[b]),
               "diagnoses": dict(sorted(_count(diag[p] for p in pats[b] if p in diag).items()))}
           for b in BANDS if b in out}
    return res


def _count(it):
    c = defaultdict(int)
    for x in it:
        c[x] += 1
    return c


# ------------------------------------------------------------------ Coswara
def coswara():
    out = defaultdict(int)
    with open(D / "coswara" / "combined_data.csv") as f:
        for r in csv.DictReader(f):
            try:
                a = float(r["a"])
            except (KeyError, ValueError):
                a = None
            out[band_years(a)] += 1
    return dict(out)


def main():
    spr, spr_meta = sprsound()
    res = {"sprsound": spr, "sprsound_meta": spr_meta, "circor": circor(), "icbhi": icbhi(),
           "coswara_participants": coswara()}
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "age_bands.json").write_text(json.dumps(res, indent=2))
    table("SPRSound (all released folders, unique recordings)", spr,
          ["patients", "recordings", "pat_stridor", "rec_stridor", "pat_wheeze", "rec_wheeze",
           "pat_crackle", "rec_crackle", "rec_no_patient_id"])
    print(json.dumps(spr_meta))
    table("CirCor (training set; dataset's own age categories)", res["circor"],
          ["patients", "recordings", "murmur_Present", "murmur_Absent", "murmur_Unknown"])
    print(json.dumps(res["icbhi"], indent=1))
    print("Coswara participants by band:", res["coswara_participants"])


if __name__ == "__main__":
    main()
