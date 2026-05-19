# OpenROAD Native Integration Notes

## Current External Interface (Python prototype)

The QEPC engine communicates with OpenROAD through CSV files and Tcl exec calls:

```
OpenROAD (Tcl) ──exec──► qe_placer.py ──► proposed_moves.csv
                ◄──apply──qepc_apply_moves (Tcl reads CSV, calls inst.setOrigin)
```

This interface has ~100 ms CSV I/O overhead per iteration (negligible vs. 4.8 s/iter).
For C++ integration, this overhead disappears entirely (direct memory access).

## C++ Integration Plan

### Step 1: Add BinGrid Accessor to PlacerBase (upstream PR)

File: `src/gpl/src/placerBase.h`
```cpp
// ADD to public interface of PlacerBase:
int numBinX() const { return binCntX_; }
int numBinY() const { return binCntY_; }
float binDensity(int x, int y) const {
    return bins_[y * binCntX_ + x].density();
}
odb::Rect binRect(int x, int y) const;
```

### Step 2: Add Per-Cell Slack Query to STA (likely already available)

In OpenSTA, per-pin slack is available via `Sta::pinSlack(const Pin* pin, const MinMax* minMax)`.
For cells, take the worst slack across all output pins:
```cpp
float worstCellSlack(odb::dbInst* inst, sta::Sta* sta) {
    float worst = sta::INF;
    for (auto iterm : inst->getITerms()) {
        if (iterm->getIoType() == odb::dbIoType::OUTPUT) {
            const sta::Pin* pin = network_->dbToSta(iterm);
            float s = sta->pinSlack(pin, sta::MinMax::max());
            worst = std::min(worst, s);
        }
    }
    return worst;
}
```

### Step 3: QEEngine Class in gpl/src/qe/

New directory: `src/gpl/src/qe/`
Files:
- `QEEngine.h` / `QEEngine.cpp` — main engine class
- `QEParams.h` — parameter struct
- `EchoField.h` / `EchoField.cpp` — 2-D grid with update and gradient methods
- `ResonanceField.h` — path-based resonance computation

### Step 4: Tcl Command Registration

In `src/gpl/src/MakeGpl.cpp`:
```cpp
// Register new commands
openroad::Tcl_Command(interp, "qepc_init",  qepcinitCmd,  tcl_interp_, nullptr);
openroad::Tcl_Command(interp, "qepc_run",   qepcrunCmd,   tcl_interp_, nullptr);
openroad::Tcl_Command(interp, "qepc_report",qepcreportCmd,tcl_interp_, nullptr);
```

## Runtime Projection (C++ vs Python)

| Operation | Python (current) | C++ (projected) | Speedup |
|-----------|-----------------|-----------------|---------|
| Echo field update | 1.75 s/iter | 15 ms/iter | 117× |
| Move proposals | 1.56 s/iter | 12 ms/iter | 130× |
| CSV I/O | 0.10 s/iter | 0 (in-memory) | ∞ |
| Legalization | 1.03 s/iter | 1.03 s/iter | 1× |
| **Total/iter** | **4.8 s** | **~1.1 s** | **~4.4×** |
| **Total QEPC (mac32)** | **14.6 min** | **~3.3 min** | **~4.4×** |

## Risks and Mitigations

1. **API stability:** OpenROAD restructures internal APIs ~2× per year.
   Mitigation: Use only `odb::dbInst`, `odb::dbNet`, `odb::dbBTerm` (stable ODB layer).

2. **BinGrid ownership:** `PlacerBase::bins_` is currently private with no accessor.
   Mitigation: Submit upstream PR; temporarily use a parallel grid with same dimensions.

3. **STA thread safety:** `Sta::pinSlack()` requires the STA to be up-to-date.
   Must call `sta->updateTiming(false)` before querying slacks.

4. **Memory:** Echo field is `float[n_bins_x][n_bins_y]` — negligible (<1 MB for any realistic design).
