#!/usr/bin/env python3
"""QEPC external echo engine. Called once per QEPC iteration from Tcl."""
import argparse
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(__file__))
from qe_engine import QEEngine
from qe_cost   import CostEvaluator
from qe_io     import load_all, write_moves


def parse_args():
    p = argparse.ArgumentParser(description="QEPC echo engine")
    p.add_argument("--cells",    required=True)
    p.add_argument("--nets",     required=True)
    p.add_argument("--bins",     required=True)
    p.add_argument("--paths",    required=True)
    p.add_argument("--cong",     required=True)
    p.add_argument("--out",      required=True)
    p.add_argument("--iter",     type=int, default=1)
    p.add_argument("--max_iter", type=int, default=200)
    p.add_argument("--seed",     type=int,
                   default=int(os.environ.get("QEPC_SEED", 42)))
    for k, v in [("lambda_d", 0.20), ("kappa", 0.30), ("sigma_b", 3.0),
                 ("xi", 0.40), ("alpha0", 2.0), ("tc0", 0.05),
                 ("epsilon", 1e-4)]:
        env_key = f"QEPC_{k.upper()}"
        p.add_argument(f"--{k}", type=float,
                       default=float(os.environ.get(env_key, v)))
    return p.parse_args()


def main():
    args = parse_args()
    np.random.seed(args.seed)

    cells, nets, bins_df, paths, cong = load_all(
        args.cells, args.nets, args.bins, args.paths, args.cong)

    if bins_df.empty:
        print("[QEPC] WARNING: bins.csv is empty; using 1x1 fallback grid")
        bins_df = pd.DataFrame([{
            "row": 0, "col": 0,
            "llx": 0, "lly": 0, "urx": 150000, "ury": 150000,
            "density": 0.0, "congestion": 0.0, "echo_energy": 0.0
        }])

    cost_eval  = CostEvaluator(cells.copy(), nets, bins_df)
    engine     = QEEngine(cells, nets, bins_df, paths, cong, args)

    cost_prev  = cost_eval.compute(cells)
    engine.update_echo_field()
    proposals  = engine.propose_moves()
    accepted   = engine.apply_acceptance(proposals, cost_eval)
    cost_cur   = cost_eval.compute(engine.cells)

    rel_delta  = abs(cost_prev - cost_cur) / (cost_prev + 1e-12)
    converged  = rel_delta < args.epsilon

    write_moves(accepted, args.out, converged)

    n_acc = sum(1 for m in accepted if m["status"] == "ACCEPT")
    print(f"[QEPC] iter={args.iter:3d}  accepted={n_acc:5d}  "
          f"cost_prev={cost_prev:.4f}  cost_cur={cost_cur:.4f}  "
          f"rel_delta={rel_delta:.2e}  converged={converged}")


if __name__ == "__main__":
    main()
