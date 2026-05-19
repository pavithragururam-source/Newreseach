#!/usr/bin/env bash
# Grid search over QEPC parameters: lambda x xi, 5 seeds each
set -euo pipefail

DESIGN_NAME=${DESIGN_NAME:-mac32}
DESIGN_DIR=${DESIGN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
ORFS_ROOT=${ORFS_ROOT:-/ORFS}
SEEDS=${SEEDS:-"42 137 271 314 999"}
LAMBDA_RANGE=${LAMBDA_RANGE:-"0.10 0.20 0.30"}
XI_RANGE=${XI_RANGE:-"0.20 0.40 0.60"}

SWEEP_DIR="$DESIGN_DIR/results/param_sweep"
mkdir -p "$SWEEP_DIR"

echo "config,seed,wns,hpwl" > "$SWEEP_DIR/sweep_results.csv"

for lam in $LAMBDA_RANGE; do
for xi in $XI_RANGE; do
for seed in $SEEDS; do
    tag="lam${lam}_xi${xi}_s${seed}"
    outdir="$SWEEP_DIR/$tag"
    mkdir -p "$outdir"

    QEPC_LAMBDA="$lam" QEPC_XI="$xi" QEPC_SEED="$seed" \
    DESIGN_NAME="$DESIGN_NAME" DESIGN_DIR="$DESIGN_DIR" ORFS_ROOT="$ORFS_ROOT" \
    openroad -exit "$DESIGN_DIR/scripts/run_qe_flow.tcl" \
        2>&1 | tee "$outdir/run.log"

    wns=$(grep -m1 "slack" "$outdir/final_timing.rpt" 2>/dev/null \
          | awk '{print $NF}' || echo "N/A")
    hpwl=$(grep -i "hpwl" "$outdir/run.log" 2>/dev/null \
           | tail -1 | awk '{print $NF}' || echo "N/A")

    echo "${tag},${seed},${wns},${hpwl}" >> "$SWEEP_DIR/sweep_results.csv"
    echo "[sweep] $tag: WNS=$wns HPWL=$hpwl"
done
done
done

echo "[sweep] Results written to $SWEEP_DIR/sweep_results.csv"
