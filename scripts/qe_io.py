"""CSV I/O layer for QEPC data schemas."""
import os
import pandas as pd

def load_all(cells_f, nets_f, bins_f, paths_f, cong_f):
    cells = pd.read_csv(cells_f)
    nets  = pd.read_csv(nets_f)
    bins  = pd.read_csv(bins_f)

    paths = (pd.read_csv(paths_f) if os.path.exists(paths_f)
             else pd.DataFrame(columns=["path_id","slack","weight","cell_sequence"]))
    cong  = (pd.read_csv(cong_f)  if os.path.exists(cong_f)
             else pd.DataFrame(columns=["row","col","h_util","v_util","overflow"]))

    for col, default in [("slack", 0.0), ("criticality", 0.0),
                         ("fixed", 0), ("width", 140), ("height", 280)]:
        if col not in cells.columns:
            cells[col] = default
    if "overflow" not in cong.columns:
        cong["overflow"] = 0.0

    return cells, nets, bins, paths, cong


def write_moves(moves, outfile, converged):
    df = pd.DataFrame(moves)
    df.to_csv(outfile, index=False)
    if converged:
        with open(outfile, "a") as f:
            f.write("CONVERGED,,,,\n")
