#!/usr/bin/env bash
# Run vanilla ORFS baseline for DESIGN_NAME
set -euo pipefail

DESIGN_NAME=${DESIGN_NAME:-mac32}
DESIGN_DIR=${DESIGN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
ORFS_ROOT=${ORFS_ROOT:-/ORFS}

export DESIGN_NAME DESIGN_DIR ORFS_ROOT

make -f "$DESIGN_DIR/flow/Makefile" baseline \
    DESIGN_NAME="$DESIGN_NAME" \
    DESIGN_DIR="$DESIGN_DIR" \
    ORFS_ROOT="$ORFS_ROOT"

echo "[baseline] Done. Reports in $DESIGN_DIR/results/baseline/"
