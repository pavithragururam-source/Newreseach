#!/usr/bin/env python3
"""
Parse OpenROAD report_checks output into cells.csv and timing_paths.csv.
Handles full_clock_expanded format from OpenSTA inside OpenROAD.
"""
import re
import sys
import argparse
import pandas as pd
from collections import defaultdict


def parse_timing_report(rpt_path):
    """
    Returns:
        cells:  dict  name -> min_slack (most negative slack across all paths)
        paths:  list  of {path_id, slack, weight, cell_sequence}
    """
    cells   = defaultdict(lambda: float("inf"))   # name -> min slack
    paths   = []
    path_id = 0

    try:
        with open(rpt_path) as f:
            content = f.read()
    except FileNotFoundError:
        return cells, paths

    # Split on path header: "Startpoint:" or "---" separators
    raw_paths = re.split(r"(?=^Startpoint:)", content, flags=re.MULTILINE)

    for block in raw_paths:
        # Extract slack
        slack_m = re.search(r"slack\s+([-\d.]+)", block)
        if not slack_m:
            continue
        slack = float(slack_m.group(1))

        # Extract cell names on the data path (lines with "/CLK" or "/D" or "/A")
        # OpenSTA full format has lines like:
        #   cell_name/pin    rise/fall  time  ...
        cell_names = []
        for line in block.splitlines():
            # Match instance/pin entries with timing info
            m = re.match(r"\s+([\w/\[\]]+)/\w+\s+", line)
            if m:
                inst_name = m.group(1).split("/")[0]
                if inst_name and inst_name not in ("", "clk", "rst_n"):
                    if inst_name not in cell_names:
                        cell_names.append(inst_name)
                    # Track minimum slack per cell
                    if slack < cells[inst_name]:
                        cells[inst_name] = slack

        if len(cell_names) >= 2:
            # Weight amplifies tight timing paths exponentially
            T_char = 0.5   # ns normalization constant
            weight = round(pow(2.718, min(5.0, abs(min(slack, 0)) / T_char)), 3)
            paths.append({
                "path_id":       path_id,
                "slack":         round(slack, 6),
                "weight":        weight,
                "cell_sequence": ",".join(cell_names[:20])  # cap at 20 cells
            })
            path_id += 1

    return cells, paths


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--rpt",       required=True, help="report_checks output")
    p.add_argument("--out",       default=None,  help="cells.csv output")
    p.add_argument("--paths_out", default=None,  help="timing_paths.csv output")
    args = p.parse_args()

    cells_slack, paths = parse_timing_report(args.rpt)

    # Worst negative slack for criticality normalization
    wns = min(cells_slack.values()) if cells_slack else 0.0
    wns = min(wns, -1e-6)   # avoid division by zero

    if args.out:
        rows = []
        for name, slack in cells_slack.items():
            crit = round(max(0.0, min(1.0, -slack / abs(wns))), 4)
            rows.append({"name": name, "slack": round(slack, 6),
                         "criticality": crit})
        df = pd.DataFrame(rows)
        # Merge with existing cells.csv if present (add slack/criticality columns)
        try:
            existing = pd.read_csv(args.out)
            if "name" in existing.columns:
                existing = existing.drop(
                    columns=[c for c in ("slack", "criticality") if c in existing.columns])
                df = existing.merge(df, on="name", how="left").fillna(
                    {"slack": 0.0, "criticality": 0.0})
        except (FileNotFoundError, pd.errors.EmptyDataError):
            pass
        df.to_csv(args.out, index=False)
        print(f"[parse_timing] {len(df)} cells written to {args.out}")

    if args.paths_out:
        df_p = pd.DataFrame(paths)
        df_p.to_csv(args.paths_out, index=False)
        print(f"[parse_timing] {len(df_p)} timing paths written to {args.paths_out}")


if __name__ == "__main__":
    main()
