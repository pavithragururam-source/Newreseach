#!/usr/bin/env python3
"""Generate QoR comparison table: baseline vs QEPC."""
import argparse
import os
import pandas as pd


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--baseline", required=True)
    p.add_argument("--qepc",     required=True)
    p.add_argument("--out",      required=True)
    args = p.parse_args()

    os.makedirs(args.out, exist_ok=True)

    b_csv = os.path.join(args.baseline, "..", "comparison", "qor_table.csv")
    q_csv = os.path.join(args.qepc,     "iteration_log.csv")

    rows = []

    # Try to load harvested QoR CSV
    table_csv = os.path.join(args.out, "qor_table.csv")
    if os.path.exists(table_csv):
        df = pd.read_csv(table_csv)
        df["delta_pct"] = ((df["qepc"].astype(float) -
                            df["baseline"].astype(float)) /
                           df["baseline"].astype(float).abs() * 100).round(2)
        out_path = os.path.join(args.out, "qor_comparison.csv")
        df.to_csv(out_path, index=False)
        print(df.to_string(index=False))
        print(f"\n[compare] Written to {out_path}")
    else:
        print(f"[compare] No qor_table.csv found at {table_csv}; run 'make reports' first")

    # Convergence curve
    if os.path.exists(q_csv):
        ilog = pd.read_csv(q_csv)
        curve_path = os.path.join(args.out, "convergence.csv")
        ilog.to_csv(curve_path, index=False)
        print(f"[compare] Convergence log saved to {curve_path}")
        print(ilog.tail(5).to_string(index=False))


if __name__ == "__main__":
    main()
