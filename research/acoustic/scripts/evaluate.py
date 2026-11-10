"""Experiments (a)-(c) on cached features: patient-grouped CV, thresholds, patient bootstrap CIs,
age bands and the phone-degradation test. Writes results/experiments.json.

  .venv/bin/python scripts/evaluate.py [--boot 1000] [--only murmur,outcome]

Design (fixed before looking at results):
  - Outer: StratifiedGroupKFold(5, shuffle, seed 0), grouped by patient; stratified on the unit label.
  - Units: SPRSound tasks are scored per recording. CirCor tasks are scored per PATIENT:
      murmur  : train on recordings (positive = patient Present AND that location is in
                "Murmur locations"); patient score = max over that patient's recordings;
                Unknown patients excluded.
      outcome : train on recordings labelled with the patient's Outcome; patient score = mean.
  - (b)/(c): StandardScaler + LogisticRegression(class_weight=balanced). C chosen from
    {0.001, 0.01, 0.1, 1} by inner StratifiedGroupKFold(3) AUROC on the training folds only.
  - Threshold: Youden's J on the inner out-of-fold scores (zero-shot: on the training units),
    then applied unchanged to the test fold. Sensitivity/specificity use these thresholds.
  - 95% CIs: percentile bootstrap over patients (1000 resamples), from the out-of-fold scores.
  - Degradation: the clean-trained fold models (same C and threshold) score degraded test folds.
"""
from __future__ import annotations

import argparse
import json
import sys
import warnings
from pathlib import Path

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import CACHE, CONDITIONS, LICENCE, RESULTS, manifest  # noqa: E402

warnings.filterwarnings("ignore")
CS = [0.001, 0.01, 0.1, 1.0]

# Zero-shot AudioSet class for each task, fixed in advance. Stridor has no AudioSet class.
TASKS = {
    "stridor": dict(dataset="sprsound", label="y_stridor", zs=37, zs_name="Wheeze (proxy: no stridor class)",
                    exploratory=True),
    "wheeze": dict(dataset="sprsound", label="y_wheeze", zs=37, zs_name="Wheeze"),
    "crackle": dict(dataset="sprsound", label="y_crackle", zs=293, zs_name="Crackle"),
    "murmur": dict(dataset="circor", label="murmur", zs=60, zs_name="Heart murmur", agg="max"),
    "outcome": dict(dataset="circor", label="outcome", zs=60, zs_name="Heart murmur (proxy)", agg="mean"),
}

FEATURES = {  # experiment -> (model cache dir, array key, kind)
    "a_app": ("yamnet_app", "scores_max", "zero"),
    "a_app_resp": ("yamnet_app", "app_resp", "zero_resp"),
    "a_float": ("yamnet_float", "scores_max", "zero"),
    "b_yamnet_lr": ("yamnet_float", "emb_mean", "lr"),
    "c_opera_lr": ("opera", "emb", "lr"),
    "c_opera_win_lr": ("opera", "emb_win", "lr"),
    "c_opera_first8_lr": ("opera", "emb_first8", "lr"),
}
MODEL_OF = {"a_app": "yamnet_app", "a_app_resp": "yamnet_app", "a_float": "yamnet_float",
            "b_yamnet_lr": "yamnet_float", "c_opera_lr": "opera", "c_opera_win_lr": "opera_win",
            "c_opera_first8_lr": "opera_first8"}


def load_feats(dataset, model, key, cond="clean"):
    p = CACHE / "emb" / dataset / model / cond / "features.npz"
    if not p.exists():
        return None
    z = np.load(p)
    if key not in z:
        return None
    return dict(zip(z["rid"].tolist(), z[key]))


# ------------------------------------------------------------------ task data
def task_data(task):
    t = TASKS[task]
    rows = manifest(t["dataset"])
    if t["dataset"] == "sprsound":
        rec_y = np.array([r[t["label"]] for r in rows])
        unit = np.array([r["rid"] for r in rows])          # unit = recording
        return rows, rec_y, unit, rec_y, unit, np.array([r["pid"] for r in rows]), \
            np.array([r["band"] for r in rows])
    if task == "murmur":
        rows = [r for r in rows if r["murmur"] in ("Present", "Absent")]
        rec_y = np.array([r["y_murmur_rec"] for r in rows])
        upos = {r["pid"]: int(r["murmur"] == "Present") for r in rows}
    else:
        rec_y = np.array([int(r["outcome"] == "Abnormal") for r in rows])
        upos = {r["pid"]: int(r["outcome"] == "Abnormal") for r in rows}
    unit = np.array([r["pid"] for r in rows])                # unit = patient
    uids = np.array(sorted(upos))
    band = {r["pid"]: r["band"] for r in rows}
    return rows, rec_y, unit, np.array([upos[u] for u in uids]), uids, uids, \
        np.array([band[u] for u in uids])


def aggregate(rec_score, rec_unit, uids, how):
    """Unit scores: identity for recordings, max/mean over a patient's recordings."""
    if how is None:
        return rec_score
    order = {u: i for i, u in enumerate(uids)}
    out = np.full(len(uids), np.nan)
    buckets = [[] for _ in uids]
    for s, u in zip(rec_score, rec_unit):
        if u in order:
            buckets[order[u]].append(s)
    for i, b in enumerate(buckets):
        if b:
            out[i] = np.max(b) if how == "max" else np.mean(b)
    return out


def youden(y, s):
    from sklearn.metrics import roc_curve
    if len(set(y)) < 2:
        return np.median(s)
    fpr, tpr, thr = roc_curve(y, s)
    return thr[np.argmax(tpr - fpr)]


def fit_lr(X, y, C):
    m = make_pipeline(StandardScaler(), LogisticRegression(C=C, class_weight="balanced", max_iter=3000))
    return m.fit(X, y)


# ------------------------------------------------------------------ CV
def run_cv(task, exp, conds):
    t = TASKS[task]
    model, key, kind = FEATURES[exp]
    rows, rec_y, rec_unit, unit_y, uids, unit_pid, unit_band = task_data(task)
    feats = load_feats(t["dataset"], model, key)
    if feats is None:
        return None
    X = np.stack([feats[r["rid"]] for r in rows]).astype(np.float64)
    if kind == "zero":
        X = X[:, t["zs"]]
    elif kind == "zero_resp":
        if t["dataset"] != "sprsound":
            return None
        X = X[:, 0]
    deg = {}
    for c in conds:
        if c != "clean" and kind == "lr":
            f = load_feats(t["dataset"], model, key, c)
            if f is not None:
                deg[c] = np.stack([f[r["rid"]] for r in rows]).astype(np.float64)
    agg = t.get("agg")
    rec_pid = np.array([r["pid"] for r in rows])
    upos_of = dict(zip(uids, unit_y))

    oof = {c: np.full(len(uids), np.nan) for c in ["clean", *deg]}
    pred = {c: np.full(len(uids), -1) for c in ["clean", *deg]}
    chosen = []
    outer = StratifiedGroupKFold(5, shuffle=True, random_state=0)
    # stratify recordings by their unit's label so positive patients spread across folds
    strat = np.array([upos_of.get(u, 0) for u in rec_unit])
    for tr, te in outer.split(np.zeros(len(rows)), strat, rec_pid):
        te_units = np.isin(uids, np.unique(rec_unit[te]))
        tr_units = np.isin(uids, np.unique(rec_unit[tr]))
        if kind.startswith("zero"):
            thr = youden(unit_y[tr_units], aggregate(X[tr], rec_unit[tr], uids, agg)[tr_units])
            s = aggregate(X[te], rec_unit[te], uids, agg)
            oof["clean"][te_units] = s[te_units]
            pred["clean"][te_units] = (s[te_units] >= thr).astype(int)
            continue
        # inner CV on the training folds: choose C, then the threshold
        inner = StratifiedGroupKFold(3, shuffle=True, random_state=1)
        inner_scores = {C: np.full(len(tr), np.nan) for C in CS}
        for itr, ite in inner.split(np.zeros(len(tr)), strat[tr], rec_pid[tr]):
            if len(set(rec_y[tr][itr])) < 2:
                continue
            for C in CS:
                m = fit_lr(X[tr][itr], rec_y[tr][itr], C)
                inner_scores[C][ite] = m.predict_proba(X[tr][ite])[:, 1]
        best, best_auc, best_thr = CS[0], -1, 0.5
        for C in CS:
            s = aggregate(inner_scores[C], rec_unit[tr], uids, agg)[tr_units]
            ok = ~np.isnan(s)
            if ok.sum() and len(set(unit_y[tr_units][ok])) == 2:
                a = roc_auc_score(unit_y[tr_units][ok], s[ok])
                if a > best_auc:
                    best, best_auc, best_thr = C, a, youden(unit_y[tr_units][ok], s[ok])
        chosen.append(best)
        m = fit_lr(X[tr], rec_y[tr], best)
        for c, Xc in [("clean", X), *deg.items()]:
            s = aggregate(m.predict_proba(Xc[te])[:, 1], rec_unit[te], uids, agg)
            oof[c][te_units] = s[te_units]
            pred[c][te_units] = (s[te_units] >= best_thr).astype(int)
    return dict(unit_y=unit_y, unit_pid=unit_pid, unit_band=unit_band, oof=oof, pred=pred,
                chosen_C=chosen)


# ------------------------------------------------------------------ metrics
def metrics(y, s, p):
    out = {}
    pos, neg = y == 1, y == 0
    out["sens"] = float((p[pos] == 1).mean()) if pos.any() else None
    out["spec"] = float((p[neg] == 0).mean()) if neg.any() else None
    out["auroc"] = float(roc_auc_score(y, s)) if pos.any() and neg.any() else None
    return out


def boot_ci(y, s, p, pid, n_boot, seed=0):
    rng = np.random.default_rng(seed)
    pats = np.unique(pid)
    idx_of = {q: np.where(pid == q)[0] for q in pats}
    vals = {"sens": [], "spec": [], "auroc": []}
    for _ in range(n_boot):
        pick = np.concatenate([idx_of[q] for q in rng.choice(pats, len(pats))])
        m = metrics(y[pick], s[pick], p[pick])
        for k in vals:
            if m[k] is not None:
                vals[k].append(m[k])
    return {k: ([float(np.percentile(v, 2.5)), float(np.percentile(v, 97.5))] if len(v) > 20 else None)
            for k, v in vals.items()}


def summarise(y, s, p, pid, n_boot):
    ok = ~np.isnan(s)
    y, s, p, pid = y[ok], s[ok], p[ok], pid[ok]
    m = metrics(y, s, p)
    m["ci"] = boot_ci(y, s, p, pid, n_boot)
    m["n_units"] = int(len(y))
    m["n_pos_units"] = int(y.sum())
    m["n_patients"] = int(len(np.unique(pid)))
    m["n_pos_patients"] = int(len(np.unique(pid[y == 1])))
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--boot", type=int, default=1000)
    ap.add_argument("--only")
    ap.add_argument("--force", action="store_true", help="recompute entries already saved")
    a = ap.parse_args()
    out_p = RESULTS / "experiments.json"
    res = json.loads(out_p.read_text()) if out_p.exists() else {}
    tasks = a.only.split(",") if a.only else list(TASKS)
    for task in tasks:
        for exp in FEATURES:
            if f"{task}|{exp}" in res and not a.force:
                continue                                   # resumable: done already
            r = run_cv(task, exp, CONDITIONS)
            if r is None:
                continue
            entry = {"task": task, "experiment": exp, "licence": LICENCE[MODEL_OF[exp]],
                     "exploratory": TASKS[task].get("exploratory", False),
                     "zero_shot_class": TASKS[task]["zs_name"] if exp.startswith("a_") else None,
                     "chosen_C": r["chosen_C"], "conditions": {}, "bands": {}}
            for c in r["oof"]:
                entry["conditions"][c] = summarise(r["unit_y"], r["oof"][c], r["pred"][c],
                                                   r["unit_pid"], a.boot)
            for b in sorted(set(r["unit_band"])):
                k = r["unit_band"] == b
                entry["bands"][b] = summarise(r["unit_y"][k], r["oof"]["clean"][k],
                                              r["pred"]["clean"][k], r["unit_pid"][k], a.boot)
            res[f"{task}|{exp}"] = entry
            c = entry["conditions"]["clean"]
            print(f"{task:8s} {exp:18s} AUROC {c['auroc']}  sens {c['sens']}  spec {c['spec']}  "
                  f"C={r['chosen_C']}", flush=True)
            out_p.write_text(json.dumps(res, indent=1))   # save after each, so it resumes


if __name__ == "__main__":
    main()
