#!/usr/bin/env bash
# harvest_reports.sh  <baseline_dir> <qepc_dir> <output_csv>
set -euo pipefail

BASELINE=$1
QEPC=$2
OUT=$3

mkdir -p "$(dirname "$OUT")"

extract_wns() {
    local rpt=$1
    grep -m1 "slack" "$rpt" 2>/dev/null | awk '{print $NF}' || echo "N/A"
}

extract_tns() {
    local rpt=$1
    grep "tns" "$rpt" 2>/dev/null | awk '{print $NF}' | head -1 || echo "N/A"
}

extract_hpwl() {
    local log=$1
    grep -i "HPWL\|hpwl" "$log" 2>/dev/null | tail -1 | awk '{print $NF}' || echo "N/A"
}

extract_overflow() {
    local log=$1
    grep -i "overflow" "$log" 2>/dev/null | tail -1 | awk '{print $NF}' || echo "N/A"
}

extract_area() {
    local rpt=$1
    grep -i "design area" "$rpt" 2>/dev/null | awk '{print $NF}' || echo "N/A"
}

echo "metric,baseline,qepc" > "$OUT"

for metric_fn in wns tns hpwl overflow area; do
    case $metric_fn in
        wns)
            b=$(extract_wns "$BASELINE/final_timing.rpt" 2>/dev/null || echo "N/A")
            q=$(extract_wns "$QEPC/final_timing.rpt"    2>/dev/null || echo "N/A")
            ;;
        tns)
            b=$(extract_tns "$BASELINE/final_timing.rpt" 2>/dev/null || echo "N/A")
            q=$(extract_tns "$QEPC/final_timing.rpt"     2>/dev/null || echo "N/A")
            ;;
        hpwl)
            b=$(extract_hpwl "$BASELINE/3_1_place_gp.log" 2>/dev/null || echo "N/A")
            q=$(extract_hpwl "$QEPC/run.log"              2>/dev/null || echo "N/A")
            ;;
        overflow)
            b=$(extract_overflow "$BASELINE/3_1_place_gp.log" 2>/dev/null || echo "N/A")
            q=$(extract_overflow "$QEPC/run.log"              2>/dev/null || echo "N/A")
            ;;
        area)
            b=$(extract_area "$BASELINE/design_area.rpt" 2>/dev/null || echo "N/A")
            q=$(extract_area "$QEPC/design_area.rpt"     2>/dev/null || echo "N/A")
            ;;
    esac
    echo "${metric_fn},${b},${q}" >> "$OUT"
done

echo "[harvest] QoR table written to $OUT"
cat "$OUT"
