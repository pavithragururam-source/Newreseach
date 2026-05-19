#!/usr/bin/env bash
# ispd2015_adapt.sh — Adapt ISPD 2015 benchmarks to ASAP7 cell library
# Requires: adaptec*.def and cell mapping table (docs/ispd2015_asap7_cellmap.csv)
set -euo pipefail

BENCH_DIR=${BENCH_DIR:-$(cd "$(dirname "$0")/../benchmarks" && pwd)}
DESIGN_DIR=${DESIGN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
ADAPT_DIR="${BENCH_DIR}/adapted"
SCRIPTS="${DESIGN_DIR}/scripts"

mkdir -p "$ADAPT_DIR"

if [[ ! -f "${DESIGN_DIR}/docs/ispd2015_asap7_cellmap.csv" ]]; then
    echo "[ispd_adapt] ERROR: Cell map not found at docs/ispd2015_asap7_cellmap.csv"
    echo "  Generate with: python3 ${SCRIPTS}/gen_cellmap.py --asap7_lib <path> --ispd_lib <path>"
    exit 1
fi

for benchmark in adaptec1 adaptec3; do
    src="${BENCH_DIR}/ispd2015/${benchmark}.def"
    if [[ ! -f "$src" ]]; then
        echo "[ispd_adapt] SKIP: $src not found (require ISPD 2015 contest benchmark files)"
        continue
    fi

    out="${ADAPT_DIR}/${benchmark}_asap7.def"
    echo "[ispd_adapt] Adapting $benchmark → $out"

    python3 - <<PYEOF
import re, sys, csv

# Load cell name mapping (ISPD cell → ASAP7 equivalent)
cell_map = {}
with open("${DESIGN_DIR}/docs/ispd2015_asap7_cellmap.csv") as f:
    for row in csv.DictReader(f):
        cell_map[row['ispd_cell']] = row['asap7_cell']

# Re-map DEF COMPONENTS section
with open("${src}") as fin, open("${out}", "w") as fout:
    in_components = False
    for line in fin:
        if re.match(r"^COMPONENTS\s+\d+", line):
            in_components = True
        elif re.match(r"^END COMPONENTS", line):
            in_components = False

        if in_components:
            # Replace cell master names: "- inst_name CELL_NAME ..."
            m = re.match(r"(\s*-\s+\S+\s+)(\S+)(.*)", line)
            if m:
                mapped = cell_map.get(m.group(2), m.group(2))
                line = m.group(1) + mapped + m.group(3) + "\n" if not line.endswith("\n") else m.group(1) + mapped + m.group(3)
        fout.write(line)

print(f"[ispd_adapt] Done: {len(cell_map)} cell types mapped")
PYEOF

    # Generate synthetic SDC for adapted benchmark
    cat > "${ADAPT_DIR}/${benchmark}.sdc" <<SDCEOF
# Synthetic SDC for ${benchmark} adapted to ASAP7
# Target: 1.0 GHz (aggressive; adjust period based on actual WNS)
create_clock -name clk -period 1.0 [get_ports clk]
set_input_delay  -clock clk -max 0.3 [all_inputs]
set_input_delay  -clock clk -min 0.0 [all_inputs]
set_output_delay -clock clk -max 0.3 [all_outputs]
set_output_delay -clock clk -min 0.0 [all_outputs]
set_clock_uncertainty -setup 0.05 [get_clocks clk]
set_clock_uncertainty -hold  0.02 [get_clocks clk]
set_driving_cell -lib_cell BUFx2_ASAP7_75t_R -pin Y [all_inputs]
set_load 5 [all_outputs]
SDCEOF

    echo "[ispd_adapt] Generated SDC: ${ADAPT_DIR}/${benchmark}.sdc"
done

echo "[ispd_adapt] Adaptation complete. Files in: ${ADAPT_DIR}/"
echo "[ispd_adapt] NOTE: Adapted benchmarks use drive-strength equivalence only."
echo "             Timing results are directional; not comparable to ISPD contest scores."
