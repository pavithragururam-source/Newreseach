#!/usr/bin/env python3
"""
Row-level compaction for QEPC.
Slides non-critical cells left within each placement row to reduce whitespace,
while respecting:
  - Library minimum spacing (min_gap)
  - Site alignment (site_width)
  - Placement density limit (rho_max)
  - Timing-critical cell displacement budget (crit_threshold)
  - Row boundary (row_llx, row_urx)

This module is called externally; it reads cells.csv and writes updated cells.csv.
"""
import argparse
import pandas as pd
import math

SITE_WIDTH = 216        # ASAP7 7.5-track site width in nm (DBU units: 1nm=1DBU)
MIN_GAP    = 108        # Minimum cell-to-cell spacing (0.5 sites)
RHO_MAX    = 0.90       # Maximum density after compaction (hard ceiling)


def snap_to_site(x, site_width=SITE_WIDTH):
    """Snap x coordinate to nearest site boundary."""
    return int(round(x / site_width) * site_width)


def compact_row(row_cells, row_llx, row_urx, row_height,
                crit_threshold=0.80, min_gap=MIN_GAP,
                site_width=SITE_WIDTH, rho_max=RHO_MAX):
    """
    Compact cells in a single row by sliding non-critical cells leftward.

    Parameters
    ----------
    row_cells     : DataFrame rows belonging to this placement row
    row_llx/urx   : row X boundaries in DBU
    row_height    : row height in DBU
    crit_threshold: cells with criticality >= this are locked
    min_gap       : minimum horizontal gap between adjacent cells (DBU)
    site_width    : placement site width for x-snapping (DBU)
    rho_max       : maximum allowed row density (0–1)

    Returns
    -------
    DataFrame with updated x values.
    """
    cells = row_cells.copy().sort_values("x").reset_index(drop=True)

    total_cell_w = cells["width"].sum()
    row_w        = row_urx - row_llx
    density      = total_cell_w / max(row_w, 1)

    if density > rho_max:
        # Row already over-dense; do not compact further
        return cells

    x_cursor = row_llx

    for idx in range(len(cells)):
        c = cells.iloc[idx]
        crit = float(c.get("criticality", 0.0))

        if crit >= crit_threshold:
            # Lock critical cell; advance cursor past it
            x_cursor = max(x_cursor, int(c["x"]) + int(c["width"]) + min_gap)
            continue

        # Compute leftmost feasible position
        proposed_x = snap_to_site(
            min(float(c["x"]), x_cursor),   # slide left at most to cursor
            site_width)
        proposed_x = max(proposed_x, row_llx)

        # Ensure no right-overflow
        if proposed_x + int(c["width"]) > row_urx:
            proposed_x = row_urx - int(c["width"])
            proposed_x = snap_to_site(proposed_x, site_width)

        cells.at[idx, "x"] = proposed_x
        x_cursor = proposed_x + int(c["width"]) + min_gap

    return cells


def run_compaction(cells_df, row_height_dbu=1080,
                   core_lly=2000, core_llx=2000, core_urx=148000,
                   crit_threshold=0.80):
    """
    Apply row-level compaction to all rows in the design.

    Row assignment: cells are grouped by quantized y-coordinate.
    Row y-coordinate: nearest multiple of row_height_dbu >= core_lly.
    """
    updated = []

    # Group cells by their row (quantized y)
    def row_y(y):
        relative = max(0, int(y) - core_lly)
        row_idx  = relative // row_height_dbu
        return core_lly + row_idx * row_height_dbu

    cells_df = cells_df.copy()
    cells_df["_row_y"] = cells_df["y"].apply(row_y)

    for ry, grp in cells_df.groupby("_row_y"):
        compacted = compact_row(
            grp, row_llx=core_llx, row_urx=core_urx,
            row_height=row_height_dbu, crit_threshold=crit_threshold)
        updated.append(compacted)

    result = pd.concat(updated, ignore_index=True)
    result = result.drop(columns=["_row_y"], errors="ignore")
    return result


def compute_gap_reduction(before_df, after_df, core_llx, core_urx,
                          row_height_dbu=1080, core_lly=2000):
    """Compute average gap fraction reduction across all rows."""
    def gap_fraction(df, core_llx, core_urx):
        fracs = []
        for ry, grp in df.groupby(df["y"].apply(
                lambda y: core_lly + max(0, int(y)-core_lly)//row_height_dbu*row_height_dbu)):
            w_total = float((grp["x"].max() + grp.get("width", 216).max()) -
                             grp["x"].min())
            w_cells = float(grp.get("width", 216).sum())
            if w_total > 0:
                fracs.append(max(0.0, w_total - w_cells) / w_total)
        return sum(fracs) / len(fracs) if fracs else 0.0

    gf_before = gap_fraction(before_df, core_llx, core_urx)
    gf_after  = gap_fraction(after_df,  core_llx, core_urx)
    return gf_before, gf_after


def main():
    p = argparse.ArgumentParser(description="QEPC row compaction pass")
    p.add_argument("--cells",        required=True)
    p.add_argument("--out",          required=True)
    p.add_argument("--crit_thresh",  type=float, default=0.80)
    p.add_argument("--core_llx",     type=int,   default=2000)
    p.add_argument("--core_lly",     type=int,   default=2000)
    p.add_argument("--core_urx",     type=int,   default=148000)
    p.add_argument("--row_height",   type=int,   default=1080)
    args = p.parse_args()

    cells = pd.read_csv(args.cells)
    before = cells.copy()

    compacted = run_compaction(cells, row_height_dbu=args.row_height,
                                core_lly=args.core_lly, core_llx=args.core_llx,
                                core_urx=args.core_urx,
                                crit_threshold=args.crit_thresh)
    compacted.to_csv(args.out, index=False)

    gf_b, gf_a = compute_gap_reduction(before, compacted, args.core_llx,
                                        args.core_urx, args.row_height,
                                        args.core_lly)
    n_moved = int((compacted["x"] != before["x"]).sum())
    print(f"[compact] moved={n_moved}  gap_before={gf_b:.4f}  "
          f"gap_after={gf_a:.4f}  reduction={100*(gf_b-gf_a)/max(gf_b,1e-9):.1f}%")


if __name__ == "__main__":
    main()
