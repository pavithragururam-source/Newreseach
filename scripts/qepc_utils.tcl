# =============================================================================
# qepc_utils.tcl  —  QEPC helper procedures for OpenROAD Tcl scripting
# =============================================================================
# All procedures interact with OpenROAD's ODB (OpenDB) via ord:: and odb::
# namespaces. Procedures that require capabilities not natively exposed via
# Tcl are routed through external Python scripts (explicitly flagged below).
# =============================================================================

# ── ODB cell position export ──────────────────────────────────────────────────

proc qepc_export_cell_positions { outfile } {
    # Native: ord::get_db_block returns the current placed block.
    # Exports: name, x, y, width, height, fixed for all non-special instances.
    set block [ord::get_db_block]
    set fd [open $outfile w]
    puts $fd "name,x,y,width,height,fixed"
    foreach inst [$block getInsts] {
        if { [$inst isBlock] || [$inst isPad] } continue
        set nm     [$inst getName]
        set loc    [$inst getOrigin]
        set master [$inst getMaster]
        set w      [$master getWidth]
        set h      [$master getHeight]
        set fixed  [expr { [$inst isFixed] ? 1 : 0 }]
        puts $fd "${nm},[lindex $loc 0],[lindex $loc 1],${w},${h},${fixed}"
    }
    close $fd
}

proc qepc_export_nets { outfile } {
    # Native: iterates ODB nets and computes HPWL from bounding box.
    # NOTE: getBBox returns 0 for nets with no placed drivers — handled below.
    set block [ord::get_db_block]
    set fd [open $outfile w]
    puts $fd "id,name,num_pins,hpwl,is_clock,is_critical,cell_ids"
    set id 0
    foreach net [$block getNets] {
        if { [$net isSpecial] } continue
        set nm    [$net getName]
        set iterms [$net getITerms]
        set bterms [$net getBTerms]
        set np    [expr { [llength $iterms] + [llength $bterms] }]
        if { $np < 2 } { incr id; continue }

        # HPWL from bounding box
        set bbox [$net getBBox]
        set hpwl 0
        if { [$bbox isValid] } {
            set hpwl [expr { [$bbox dx] + [$bbox dy] }]
        }

        # Clock detection
        set iscl [expr { [$net getSigType] eq "CLOCK" ? 1 : 0 }]

        # Cell IDs (instance names connected to this net)
        set cell_ids {}
        foreach it $iterms {
            set cinst [$it getInst]
            if { $cinst ne "" } {
                lappend cell_ids [$cinst getName]
            }
        }
        puts $fd "${id},${nm},${np},${hpwl},${iscl},0,[join $cell_ids {,}]"
        incr id
    }
    close $fd
}

proc qepc_export_cong { cong_log outfile } {
    # If FastRoute log available, parse it (via Python).
    # Otherwise write empty CSV — QEPC initializes congestion to zero.
    if { $cong_log ne "" && [file exists $cong_log] } {
        exec python3 ${::env(DESIGN_DIR)}/scripts/parse_congestion.py \
            --log $cong_log --out $outfile
    } else {
        set fd [open $outfile w]
        puts $fd "row,col,h_util,v_util,overflow"
        close $fd
        puts "[QEPC] No congestion log; initializing to zero."
    }
}

# ── Merge positions and timing into unified cells.csv ─────────────────────────

proc qepc_merge_positions { pos_csv slack_csv {out_csv ""} } {
    # NOT natively available in Tcl; uses Python for DataFrame merge.
    # pos_csv  : name, x, y, width, height, fixed
    # slack_csv: name, slack, criticality  (from parse_timing.py)
    # out_csv  : merged output; if empty, writes back to slack_csv

    if { $out_csv eq "" } { set out_csv $slack_csv }

    exec python3 -c "
import pandas as pd, sys

pos   = pd.read_csv('${pos_csv}')
slack = pd.read_csv('${slack_csv}')

# If slack_csv has no rows (first pass), create placeholder
if slack.empty:
    slack = pd.DataFrame({'name': pos['name'], 'slack': 0.0, 'criticality': 0.0})

# Merge
merged = pos.merge(
    slack\[['name','slack','criticality']\],
    on='name', how='left').fillna({'slack': 0.0, 'criticality': 0.0})
merged.to_csv('${out_csv}', index=False)
print(f'\[merge\] {len(merged)} cells written to ${out_csv}')
"
}

# ── Apply proposed_moves.csv to OpenROAD DB ────────────────────────────────────

proc qepc_apply_moves { movefile } {
    # Applies moves with status=ACCEPT from the Python engine output.
    # Returns the count of cells actually moved.
    set n 0
    set block [ord::get_db_block]
    if { ![file exists $movefile] } {
        puts "[QEPC] Warning: movefile not found: $movefile"
        return 0
    }
    set fd [open $movefile r]
    gets $fd   ;# skip header
    while { [gets $fd line] >= 0 } {
        set f [split $line ","]
        if { [llength $f] < 5 } continue
        set nm    [lindex $f 0]
        set new_x [lindex $f 1]
        set new_y [lindex $f 2]
        set stat  [lindex $f 4]
        if { $stat ne "ACCEPT" } continue
        if { ![string is double -strict $new_x] } continue
        if { ![string is double -strict $new_y] } continue
        set inst [$block findInst $nm]
        if { $inst eq "" }            continue
        if { [$inst isFixed] }        continue
        $inst setOrigin [list [expr {int($new_x)}] [expr {int($new_y)}]]
        incr n
    }
    close $fd
    return $n
}

proc qepc_apply_moves_from_cells { before_csv after_csv } {
    # Apply position changes from compacted cells.csv back to ODB.
    # Computes delta from before_csv to after_csv and applies moves.
    set n 0
    set block [ord::get_db_block]

    exec python3 -c "
import pandas as pd
b = pd.read_csv('${before_csv}')
a = pd.read_csv('${after_csv}')
merged = b\[['name','x','y']\].merge(a\[['name','x','y']\], on='name', suffixes=('_b','_a'))
moved = merged\[merged.x_b != merged.x_a\]
moved\[\['name','x_a','y_a'\]\].rename(columns={'x_a':'new_x','y_a':'new_y'}).to_csv('/tmp/qepc_compact_moves.csv', index=False)
print(f'compact delta: {len(moved)} cells')
"
    # Now apply the compaction delta
    if { [file exists /tmp/qepc_compact_moves.csv] } {
        set fd [open /tmp/qepc_compact_moves.csv r]
        gets $fd   ;# skip header: name,new_x,new_y
        while { [gets $fd line] >= 0 } {
            set f [split $line ","]
            if { [llength $f] < 3 } continue
            set nm    [lindex $f 0]
            set new_x [lindex $f 1]
            set new_y [lindex $f 2]
            if { ![string is double -strict $new_x] } continue
            set inst [$block findInst $nm]
            if { $inst eq "" || [$inst isFixed] } continue
            $inst setOrigin [list [expr {int($new_x)}] [expr {int($new_y)}]]
            incr n
        }
        close $fd
    }
    return $n
}

# ── Metrics extraction ─────────────────────────────────────────────────────────

proc qepc_extract_wns { rptfile } {
    # Parse worst slack from report_checks output.
    # Format: "slack (VIOLATED)" or "slack 0.xxx"
    if { ![file exists $rptfile] } { return 0.0 }
    set fd [open $rptfile r]
    while { [gets $fd line] >= 0 } {
        if { [regexp {^\s*slack\s+([-\d.]+)} $line m sl] } {
            close $fd
            return [format "%.6f" $sl]
        }
    }
    close $fd
    return 0.0
}

proc qepc_get_hpwl {} {
    # Compute total HPWL from ODB net bounding boxes.
    # NOTE: OpenROAD does not expose a single HPWL query command via Tcl.
    # This procedure iterates all non-special nets.
    set total 0
    set block [ord::get_db_block]
    foreach net [$block getNets] {
        if { [$net isSpecial] } continue
        set bbox [$net getBBox]
        if { [$bbox isValid] } {
            incr total [expr { [$bbox dx] + [$bbox dy] }]
        }
    }
    return $total
}

proc qepc_log_iter { iter wns hpwl logfile } {
    # Append one row to iteration_log.csv
    if { $iter == 1 && ![file exists $logfile] } {
        set fd [open $logfile w]
        puts $fd "iteration,wns_ns,hpwl_dbu,timestamp"
        close $fd
    }
    set fd [open $logfile a]
    puts $fd "${iter},${wns},${hpwl},[clock seconds]"
    close $fd
}

proc qepc_read_convergence { movefile } {
    # Returns 1 if Python engine wrote "CONVERGED" as the last line.
    if { ![file exists $movefile] } { return 0 }
    set last ""
    set fd [open $movefile r]
    while { [gets $fd line] >= 0 } { set last $line }
    close $fd
    return [expr { [string match "*CONVERGED*" $last] ? 1 : 0 }]
}
