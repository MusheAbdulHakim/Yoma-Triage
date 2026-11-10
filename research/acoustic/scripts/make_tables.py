"""Turn results/*.json into Markdown tables (results/tables.md) for FEASIBILITY_REPORT.md."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import CACHE, LICENCE, RESULTS  # noqa: E402

EXP_NAME = {
    "a_app": "(a) YAMNet zero-shot, app's int8 model",
    "a_app_resp": "(a) YAMNet zero-shot, app's int8 model, app's respiratory score",
    "a_float": "(a) YAMNet zero-shot, official float model",
    "b_yamnet_lr": "(b) YAMNet embeddings + LR",
    "c_opera_lr": "(c) OPERA-CE embeddings + LR",
    "c_opera_win_lr": "(c) OPERA-CE, mean of 8 s windows + LR",
    "c_opera_first8_lr": "(c) OPERA-CE, first 8 s + LR",
}
MODEL = {"a_app": "yamnet_app", "a_app_resp": "yamnet_app", "a_float": "yamnet_float",
         "b_yamnet_lr": "yamnet_float", "c_opera_lr": "opera", "c_opera_win_lr": "opera_win",
         "c_opera_first8_lr": "opera_first8"}
TASK_TITLE = {
    "stridor": "Stridor (SPRSound, per recording). EXPLORATORY: only 9 patients with stridor",
    "wheeze": "Wheeze (SPRSound, per recording)",
    "crackle": "Crackles (SPRSound, per recording)",
    "murmur": "Heart murmur, Present vs Absent (CirCor, per patient; Unknown excluded)",
    "outcome": "Outcome, Abnormal vs Normal (CirCor, per patient)",
}
COND_NAME = {"clean": "clean", "hp100": "high-pass 100 Hz", "hp150": "high-pass 150 Hz",
             "noise10": "clinic-like noise, 10 dB SNR", "noise5": "clinic-like noise, 5 dB SNR",
             "level-20": "level -20 dB (noise floor -70 dBFS, 16-bit)"}


def f(x, ci=None, pct=False):
    if x is None:
        return "–"
    s = f"{x:.2f}"
    if ci:
        s += f" ({ci[0]:.2f}–{ci[1]:.2f})"
    return s


def row(m, key):
    return f(m[key], (m.get("ci") or {}).get(key))


def main():
    ex = json.loads((RESULTS / "experiments.json").read_text())
    L = []
    w = L.append
    for task, title in TASK_TITLE.items():
        w(f"\n#### {title}\n")
        w("| Experiment | Weight licence | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |")
        w("|---|---|---|---|---|---|---|")
        for exp in EXP_NAME:
            e = ex.get(f"{task}|{exp}")
            if not e:
                continue
            m = e["conditions"]["clean"]
            zs = f" [{e['zero_shot_class']}]" if e.get("zero_shot_class") and exp != "a_app_resp" else ""
            w(f"| {EXP_NAME[exp]}{zs} | {LICENCE[MODEL[exp]]} | {m['n_patients']} ({m['n_pos_patients']}) | "
              f"{m['n_units']} ({m['n_pos_units']}) | {row(m, 'auroc')} | {row(m, 'sens')} | {row(m, 'spec')} |")
    # age bands
    w("\n### By age band\n")
    for task, title in TASK_TITLE.items():
        w(f"\n#### {title}\n")
        w("| Experiment | Weight licence | Age band | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |")
        w("|---|---|---|---|---|---|---|---|")
        for exp in ["a_app", "b_yamnet_lr", "c_opera_lr"]:
            e = ex.get(f"{task}|{exp}")
            if not e:
                continue
            for b, m in e["bands"].items():
                w(f"| {EXP_NAME[exp]} | {LICENCE[MODEL[exp]]} | {b} | {m['n_patients']} ({m['n_pos_patients']}) | "
                  f"{m['n_units']} ({m['n_pos_units']}) | {row(m, 'auroc')} | {row(m, 'sens')} | {row(m, 'spec')} |")
    # degradation
    w("\n### Phone-degradation test (models trained on clean audio)\n")
    for task, title in TASK_TITLE.items():
        w(f"\n#### {title}\n")
        w("| Experiment | Weight licence | Condition | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |")
        w("|---|---|---|---|---|---|")
        for exp in ["b_yamnet_lr", "c_opera_lr"]:
            e = ex.get(f"{task}|{exp}")
            if not e:
                continue
            for c, m in e["conditions"].items():
                w(f"| {EXP_NAME[exp]} | {LICENCE[MODEL[exp]]} | {COND_NAME[c]} | {row(m, 'auroc')} | "
                  f"{row(m, 'sens')} | {row(m, 'spec')} |")
    # OPERA long-clip rules
    w("\n### OPERA-CE long clips: fixed-length rules against the official whole-clip embedding\n")
    w("| Dataset | Clips longer than 8 s after trimming | Rule | Cosine to whole-clip, median (5th percentile) |")
    w("|---|---|---|---|")
    for ds in ["sprsound", "circor"]:
        p = CACHE / "emb" / ds / "opera" / "clean" / "features.npz"
        if not p.exists():
            continue
        z = np.load(p)
        long_ = z["n_frames"][:, 0] > 251
        for rule, k in [("mean of 8 s windows", "emb_win"), ("first 8 s after trimming", "emb_first8")]:
            a, b = z[k][long_], z["emb"][long_]
            c = (a * b).sum(1) / np.linalg.norm(a, axis=1) / np.linalg.norm(b, axis=1)
            w(f"| {ds} | {long_.sum()} of {len(long_)} | {rule} | {np.median(c):.3f} ({np.percentile(c, 5):.3f}) |")
    w("\n| Task | Weight licence | Whole clip (official) AUROC | Mean of 8 s windows AUROC | First 8 s AUROC |")
    w("|---|---|---|---|---|")
    for task in TASK_TITLE:
        vals = [ex.get(f"{task}|{e}") for e in ["c_opera_lr", "c_opera_win_lr", "c_opera_first8_lr"]]
        if all(vals):
            w(f"| {task}{' (exploratory)' if task == 'stridor' else ''} | CC BY-NC 4.0 | " +
              " | ".join(row(v["conditions"]["clean"], "auroc") for v in vals) + " |")
    # baselines
    bp = RESULTS / "baselines.json"
    if bp.exists():
        b = json.loads(bp.read_text())
        w("\n### Non-AI baselines\n")
        w("| Measure | Weight licence | Condition | Recordings estimated / total | Patients | MAE (95% CI) | Median AE | Bias | Within ±5 /min |")
        w("|---|---|---|---|---|---|---|---|---|")
        for k, v in b.items():
            kind, c = k.split("|")
            a = v["all"]
            name = "Breathing rate (breaths/min)" if kind == "breath" else "Heart rate (beats/min)"
            w(f"| {name} | n/a (no model) | {COND_NAME[c]} | {v['n_estimated']} / {v['n_total']} | {a['n_patients']} | "
              f"{a['mae']:.1f} ({a['mae_ci'][0]:.1f}–{a['mae_ci'][1]:.1f}) | {a['median_ae']:.1f} | "
              f"{a['bias']:+.1f} | {a['within_5'] * 100:.0f}% |")
        w("\n| Measure | Weight licence | Age band | Recordings | Patients | MAE (95% CI) | Within ±5 /min |")
        w("|---|---|---|---|---|---|---|")
        for kind in ["breath", "heart"]:
            v = b.get(f"{kind}|clean")
            if v:
                for band, a in v["bands"].items():
                    w(f"| {'Breathing rate' if kind == 'breath' else 'Heart rate'} | n/a (no model) | {band} | {a['n']} | "
                      f"{a['n_patients']} | {a['mae']:.1f} ({a['mae_ci'][0]:.1f}–{a['mae_ci'][1]:.1f}) | {a['within_5'] * 100:.0f}% |")
        w("\n| Condition | Weight licence | Recordings | Spearman ρ, estimated vs reference beat-interval CV | Reference CV median | Estimated CV median |")
        w("|---|---|---|---|---|---|")
        for c in ["clean", "hp150", "noise10", "noise5"]:
            v = b.get(f"heart|{c}")
            if v:
                r = v["regularity"]
                w(f"| {COND_NAME[c]} | n/a (no model) | {r['n']} | {r['spearman_rho']:.2f} | {r['ref_cv_median']:.3f} | {r['est_cv_median']:.3f} |")
    cp = RESULTS / "coswara_reference.json"
    if cp.exists():
        c = json.loads(cp.read_text())
        w("\n### Coswara real phone audio against simulated degradation (medians)\n")
        w("| Audio | Recordings | Level (dBFS) | Energy below 150 Hz | Spectral centroid (Hz) | Frame-energy range (dB) |")
        w("|---|---|---|---|---|---|")
        for k, v in c.items():
            if not isinstance(v, dict):
                continue
            label = k.replace("|", ": ").replace("coswara_bandlimited_2000hz", "Coswara phone, band-limited to 2 kHz") \
                .replace("coswara_bandlimited_4000hz", "Coswara phone, band-limited to 4 kHz") \
                .replace("coswara_full_band", "Coswara phone, full band")
            for cn, cl in COND_NAME.items():
                label = label.replace(f": {cn}", f": {cl}") if label.endswith(cn) else label
            w(f"| {label} | {v['n']} | {v['level_dbfs']['median']:.1f} | {v['lf_share_150']['median']:.2f} | "
              f"{v['centroid_hz']['median']:.0f} | {v['dyn_range_db']['median']:.1f} |")
    (RESULTS / "tables.md").write_text("\n".join(L) + "\n")
    print("\n".join(L))


if __name__ == "__main__":
    main()
