# =============================================================================
# run_qe_flow.tcl  —  QEPC top-level OpenROAD Tcl flow
# =============================================================================
# Invocation:  openroad -exit scripts/run_qe_flow.tcl
#
# Required environment variables (set via docker -e or shell export):
#   DESIGN_DIR   : project root (contains designs/, scripts/, results/)
#   DESIGN_NAME  : e.g., mac32
#   ORFS_ROOT    : path to OpenROAD-flow-scripts checkout
#   PLATFORM     : asap7 (default)
#   PLACE_DENSITY: target placement density (default 0.65)
#   QEPC_MAX_ITER: max QEPC iterations (default 200)
#   QEPC_COMPACT_FREQ: compaction every N iters (default 10)
# =============================================================================

source ${::env(DESIGN_DIR)}/scripts/qepc_utils.tcl

# ── Environment ───────────────────────────────────────────────────────────────
set DESIGN   $::env(DESIGN_NAME)
set DDIR     $::env(DESIGN_DIR)
set ORFS     $::env(ORFS_ROOT)
set PLATFORM [expr {[info exists ::env(PLATFORM)] ? $::env(PLATFORM) : "asap7"}]
set DENSITY  [expr {[info exists ::env(PLACE_DENSITY)] ? $::env(PLACE_DENSITY) : 0.65}]
set MAX_ITER [expr {[info exists ::env(QEPC_MAX_ITER)] ? $::env(QEPC_MAX_ITER) : 200}]
set COMP_FREQ [expr {[info exists ::env(QEPC_COMPACT_FREQ)] ? $::env(QEPC_COMPACT_FREQ) : 10}]
set RESULTS  ${DDIR}/results/qepc

file mkdir $RESULTS

puts "\n=========================================="
puts "  QEPC Flow: ${DESIGN} on ${PLATFORM}"
puts "  density=${DENSITY}  max_iter=${MAX_ITER}"
puts "==========================================\n"

# ── 1. Technology setup ────────────────────────────────────────────────────────
set PDK ${ORFS}/flow/platforms/${PLATFORM}

# ASAP7 7.5-track (asap7sc7p5t_27_R): tech LEF + cell LEF
# Assumption: Rev 27 standard cells, R variant (regular), 1x scaling
foreach lef_f [glob -nocomplain ${PDK}/lef/*.lef] {
    read_lef $lef_f
}

# Multi-corner liberty: use FF (fast) corner for setup analysis
#   asap7sc7p5t_SEQ_RVT_FF = sequential cells, regular Vt, fast-fast PVT
foreach lib_f [glob -nocomplain ${PDK}/lib/*FF*.lib] {
    read_liberty $lib_f
}

# ── 2. Netlist ─────────────────────────────────────────────────────────────────
set verilog_path ${DDIR}/designs/${DESIGN}/rtl/${DESIGN}.sv
if {![file exists $verilog_path]} {
    set verilog_path ${DDIR}/designs/${DESIGN}/rtl/${DESIGN}.v
}
read_verilog  $verilog_path
link_design   $DESIGN
read_sdc      ${DDIR}/designs/${DESIGN}/constraints/${DESIGN}.sdc

# ── 3. Floorplan ───────────────────────────────────────────────────────────────
# Die: 94µm × 94µm  Core: 90µm × 90µm  (2µm margin each side)
# DBU: 1 nm per DBU for ASAP7 → 94000 × 94000 DBU
# Site: asap7sc7p5t_27_R  (height 1080nm, width 216nm)
initialize_floorplan \
    -die_area  "0 0 94000 94000" \
    -core_area "2000 2000 92000 92000" \
    -site      asap7sc7p5t_27_R

place_pins \
    -hor_layers {M4} \
    -ver_layers {M5} \
    -random

# ── 4. Global Placement (RePlAce) ──────────────────────────────────────────────
puts "[QEPC] Running global_placement density=${DENSITY}..."
global_placement \
    -density        $DENSITY \
    -pad_left       2 \
    -pad_right      2

write_def ${RESULTS}/3_1_place_gp.def
write_db  ${RESULTS}/3_1_place_gp.odb

puts "[QEPC] Global placement complete."

# ── 5. Initial STA ────────────────────────────────────────────────────────────
estimate_parasitics -placement

set sta_rpt ${RESULTS}/pre_qepc_timing.rpt
catch {
    report_checks -path_delay max -nworst 50 \
        -fields {slew cap net fanout} \
        -format full_clock_expanded \
        > $sta_rpt
}

set wns_pre [qepc_extract_wns $sta_rpt]
puts "[QEPC] Pre-QEPC WNS = ${wns_pre} ns"

# ── 6. Export initial feature CSVs ────────────────────────────────────────────
# Cells with position from ODB, slack from STA report
qepc_export_cell_positions  ${RESULTS}/cell_pos.csv
exec python3 ${DDIR}/scripts/parse_timing.py \
    --rpt   $sta_rpt \
    --out   ${RESULTS}/cells.csv \
    --paths_out ${RESULTS}/timing_paths.csv

# Merge positions into cells.csv
qepc_merge_positions ${RESULTS}/cell_pos.csv ${RESULTS}/cells.csv

# Bin density grid from GP
exec python3 ${DDIR}/scripts/parse_gp_density.py \
    --log ${RESULTS}/3_1_place_gp.def \
    --out ${RESULTS}/bins.csv \
    --core_llx 2000 --core_lly 2000 \
    --core_urx 92000 --core_ury 92000

# Export nets
qepc_export_nets ${RESULTS}/nets.csv

# Congestion: zeros on first pass (no routing yet)
qepc_export_cong "" ${RESULTS}/congestion.csv

# ── 7. QEPC Iteration Loop ────────────────────────────────────────────────────
set iter      0
set converged 0
set cost_prev 1e18

puts "\n[QEPC] Starting echo engine loop (max=${MAX_ITER} iters)..."

while { !$converged && $iter < $MAX_ITER } {
    incr iter

    # Call external Python QEPC engine (one iteration)
    set py_rc [catch {
        exec python3 ${DDIR}/scripts/qe_placer.py \
            --cells    ${RESULTS}/cells.csv \
            --nets     ${RESULTS}/nets.csv \
            --bins     ${RESULTS}/bins.csv \
            --paths    ${RESULTS}/timing_paths.csv \
            --cong     ${RESULTS}/congestion.csv \
            --out      ${RESULTS}/proposed_moves.csv \
            --iter     $iter \
            --max_iter $MAX_ITER
    } py_msg]

    if { $py_rc != 0 } {
        puts "[QEPC] Engine error at iter ${iter}: ${py_msg}"
        break
    }
    puts "[QEPC] ${py_msg}"

    # Apply accepted moves to OpenROAD DB
    set n_moved [qepc_apply_moves ${RESULTS}/proposed_moves.csv]

    # Legalize after every move batch (OpenROAD native)
    if { $n_moved > 0 } {
        legalize_placement
    }

    # Compaction pass every COMP_FREQ iterations
    if { $iter % $COMP_FREQ == 0 } {
        # Write current positions to cells.csv, run Python compactor
        qepc_export_cell_positions ${RESULTS}/cells_pre_compact.csv
        catch {
            exec python3 ${DDIR}/scripts/qe_compactor.py \
                --cells      ${RESULTS}/cells_pre_compact.csv \
                --out        ${RESULTS}/cells_compacted.csv \
                --crit_thresh 0.80 \
                --core_llx   2000 --core_lly 2000 \
                --core_urx   92000 --row_height 1080
        } compact_msg
        puts "[QEPC] Compaction: ${compact_msg}"
        # Re-apply compacted positions to ODB
        qepc_apply_moves_from_cells \
            ${RESULTS}/cells_pre_compact.csv \
            ${RESULTS}/cells_compacted.csv
        legalize_placement
    }

    # Update STA for convergence metric
    estimate_parasitics -placement
    set iter_rpt ${RESULTS}/iter_${iter}_timing.rpt
    catch {
        report_checks -path_delay max -nworst 5 > $iter_rpt
    }
    set wns_cur [qepc_extract_wns $iter_rpt]
    set hpwl    [qepc_get_hpwl]

    # Log iteration
    qepc_log_iter $iter $wns_cur $hpwl ${RESULTS}/iteration_log.csv

    # Re-export updated cell positions for next iteration
    qepc_export_cell_positions ${RESULTS}/cell_pos.csv
    exec python3 ${DDIR}/scripts/parse_timing.py \
        --rpt   $iter_rpt \
        --out   ${RESULTS}/cells_slack_only.csv
    qepc_merge_positions ${RESULTS}/cell_pos.csv ${RESULTS}/cells_slack_only.csv \
        ${RESULTS}/cells.csv

    # Check convergence flag from Python engine
    set converged [qepc_read_convergence ${RESULTS}/proposed_moves.csv]
}

puts "\n[QEPC] Loop ended: iter=${iter} converged=${converged} WNS=${wns_cur}"

# ── 8. Detailed Placement (OpenDP) ────────────────────────────────────────────
puts "[QEPC] Running detailed_placement..."
detailed_placement
puts "[QEPC] Detailed placement complete."

# ── 9. Final Reports ──────────────────────────────────────────────────────────
estimate_parasitics -placement

catch { report_checks   -path_delay max -nworst 50 \
        -format full_clock_expanded \
        > ${RESULTS}/final_timing.rpt }
catch { report_design_area  > ${RESULTS}/design_area.rpt  }
catch { report_power         > ${RESULTS}/power.rpt        }
catch { report_checks -path_delay max -fields {slack} \
        > ${RESULTS}/wns_summary.rpt }

write_def ${RESULTS}/final_placed.def
write_db  ${RESULTS}/final_placed.odb

set wns_final [qepc_extract_wns ${RESULTS}/final_timing.rpt]
puts "\n[QEPC] ============ Flow Complete ============"
puts "[QEPC] Pre-QEPC  WNS : ${wns_pre} ns"
puts "[QEPC] Post-QEPC WNS : ${wns_final} ns"
puts "[QEPC] HPWL           : [qepc_get_hpwl] DBU"
puts "[QEPC] Iterations     : ${iter}"
puts "[QEPC] Results        : ${RESULTS}/"
puts "[QEPC] =========================================\n"

exit
