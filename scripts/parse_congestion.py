#!/usr/bin/env python3
"""
Parse FastRoute (global route) congestion report from OpenROAD.
FastRoute reports GCell overflow per layer; we aggregate to per-bin.
Output: congestion.csv with columns: row, col, h_util, v_util, overflow
"""
import re
import argparse
import pandas as pd


def parse_fastroute_log(log_path):
    """
    FastRoute log format (example):
      [INFO FRT-0036] Final usage 2D: H: 12345  V: 9876
      [INFO FRT-0037] Final capacity 2D: H: 15000  V: 12000
      [INFO FRT-0039] Total overflow: 42 (H: 28 V: 14)
      [INFO FRT-0075] GCell congestion {row=0 col=0}: H=0.82 V=0.75 overflow=0.00
    Returns list of {row, col, h_util, v_util, overflow}
    """
    rows = []
    total_overflow = 0.0
    total_h_cap    = 1.0
    total_v_cap    = 1.0
    total_h_use    = 0.0
    total_v_use    = 0.0

    try:
        with open(log_path) as f:
            content = f.read()
    except FileNotFoundError:
        return [], 0.0

    # Per-GCell congestion lines (verbose FastRoute output)
    gcell_pat = re.compile(
        r"GCell.*?row=(\d+).*?col=(\d+).*?H=([\d.]+).*?V=([\d.]+).*?overflow=([\d.]+)",
        re.IGNORECASE)
    for m in gcell_pat.finditer(content):
        rows.append({
            "row":      int(m.group(1)),
            "col":      int(m.group(2)),
            "h_util":   round(float(m.group(3)), 4),
            "v_util":   round(float(m.group(4)), 4),
            "overflow": round(float(m.group(5)), 4),
        })

    # Global overflow fallback
    ov_m = re.search(r"Total overflow:\s*([\d.]+)", content, re.IGNORECASE)
    if ov_m:
        total_overflow = float(ov_m.group(1))

    h_use_m = re.search(r"Final usage 2D: H:\s*(\d+)\s+V:\s*(\d+)", content)
    h_cap_m = re.search(r"Final capacity 2D: H:\s*(\d+)\s+V:\s*(\d+)", content)
    if h_use_m and h_cap_m:
        total_h_use = float(h_use_m.group(1))
        total_v_use = float(h_use_m.group(2))
        total_h_cap = max(1.0, float(h_cap_m.group(1)))
        total_v_cap = max(1.0, float(h_cap_m.group(2)))

    # If no per-cell data, synthesize from global overflow
    if not rows:
        h_util = round(total_h_use / total_h_cap, 4) if total_h_cap > 0 else 0.70
        v_util = round(total_v_use / total_v_cap, 4) if total_v_cap > 0 else 0.65
        rows.append({
            "row": 0, "col": 0,
            "h_util":   h_util,
            "v_util":   v_util,
            "overflow": round(max(0.0, (h_util + v_util) / 2.0 - 0.80), 4)
        })

    return rows, total_overflow


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--log", required=True,  help="FastRoute log")
    p.add_argument("--out", required=True,  help="congestion.csv output")
    args = p.parse_args()

    rows, total_ov = parse_fastroute_log(args.log)
    df = pd.DataFrame(rows)
    df.to_csv(args.out, index=False)
    print(f"[parse_congestion] {len(df)} GCells written to {args.out} "
          f"(total overflow={total_ov:.1f})")


if __name__ == "__main__":
    main()
