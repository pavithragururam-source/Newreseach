#!/usr/bin/env bash
# Run QEPC-enhanced placement flow
set -euo pipefail

DESIGN_NAME=${DESIGN_NAME:-mac32}
DESIGN_DIR=${DESIGN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
ORFS_ROOT=${ORFS_ROOT:-/ORFS}
QEPC_MAX_ITER=${QEPC_MAX_ITER:-200}
QEPC_SEED=${QEPC_SEED:-42}

export DESIGN_NAME DESIGN_DIR ORFS_ROOT QEPC_MAX_ITER QEPC_SEED

make -f "$DESIGN_DIR/flow/Makefile" qepc \
    DESIGN_NAME="$DESIGN_NAME" \
    DESIGN_DIR="$DESIGN_DIR" \
    ORFS_ROOT="$ORFS_ROOT"

echo "[qepc] Done. Reports in $DESIGN_DIR/results/qepc/"
