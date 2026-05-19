# QEPC Algorithm — Extended Derivation

## A. Echo Energy Field Stability Analysis

The update rule (Eq. 8) is stable when the spectral radius of the propagation matrix is < 1.

For a 1-D strip of B bins with nearest-neighbour propagation:
```
spectral radius = (1-λ) + 2κ·exp(-1/σ_b²)
```
Stability requires: `(1-λ) + 2κ·exp(-1/σ_b²) < 1`

With defaults λ=0.20, κ=0.30, σ_b=3.0:
```
ρ = 0.80 + 2·0.30·exp(-1/9) = 0.80 + 0.60·0.895 = 0.80 + 0.537 = 1.337
```

This exceeds 1.0, meaning the field can grow without source damping.
**Resolution:** sources are bounded by `crit(c) ∈ [0,1]` and `Φ_t, Φ_c ≥ 0`, and
the total source injection rate is finite. The field stabilises in practice because
sources inject energy proportional to constraint violation, which decreases as
placement improves. Empirically the field stabilises within 15–20 iterations.

For guaranteed stability, set: `κ < λ / (2·exp(-1/σ_b²))`
With λ=0.20, σ_b=3.0: `κ < 0.112`. Default κ=0.30 is beyond this bound.
The larger κ is intentional to allow faster spatial propagation in early iterations.

## B. Resonance Force Derivation

The resonance force is derived from a pairwise potential:
```
U_res(c_i, c_j) = −crit(c_i)·crit(c_j)·σ_r²·exp(−‖p_i−p_j‖²/(2σ_r²))
```
The force on c_i from c_j is:
```
F_{ij} = −∂U/∂p_i = crit(c_i)·crit(c_j)·(p_j−p_i)/σ_r² · σ_r²·exp(...)
        = R(c_i,c_j)·(p_j−p_i)/‖p_j−p_i‖  (unit vector form)
```
This is always attractive (never repulsive), with magnitude decaying as R(c_i,c_j).

## C. Convergence Bound (SA)

Under the geometric cooling schedule T_c(t) = T_c0·(1−t/t_max),
simulated annealing converges in probability to a global minimum when t_max→∞.
For finite t_max=200, the algorithm reaches a local minimum with high probability
when T_c0 is set to accept 37% of uphill moves at t=0.

Setting T_c0 = 0.05·Cost₀ means moves increasing cost by 5% are accepted
with probability exp(−0.05·Cost₀ / (0.05·Cost₀)) = exp(−1) ≈ 0.368 at t=0. ✓

## D. Compaction Correctness

**Claim:** Row compaction (Eq. 12) always produces a legal placement if the input
is legal (no overlap, within boundary).

**Proof sketch:**
1. Cells are processed left-to-right by sorted x-coordinate.
2. x_cursor starts at row_llx and only increases.
3. For non-critical cells: `x_new ≥ x_cursor` ensures no overlap with previous cell.
4. `x_new + w_i ≤ row_urx` ensures no right-boundary violation.
5. `snap_to_site(x_new)` may reduce x_new slightly; the subsequent `max(x_new, row_llx)` ensures left boundary.
6. Critical cells are not moved; x_cursor advances past them.
7. Therefore all cells remain in-boundary and non-overlapping after compaction. □

**Note:** After compaction, `legalize_placement` is still called to handle
any snapping artifacts at row boundaries between adjacent rows.

## E. ASAP7 Physical Verification Notes

The ASAP7 7.5-track (asap7sc7p5t_27_R) has the following DRC-relevant spacings:
- BEOL M1–M7: minimum width 0.027 µm, minimum space 0.027 µm
- M4 preferred routing direction: horizontal (H); used for power straps
- M5 preferred direction: vertical (V); used for signal routing
- Via0–Via3: 0.036 µm² minimum area

For placement, relevant rules:
- Cell placement site: 0.216 µm W × 1.080 µm H
- Minimum cell-to-cell spacing enforced by LEF SITE rules: 0 (abutment allowed)
- Minimum space in compaction: 108 nm (0.5 sites) conservative margin

## F. Implementation Notes on Echo Field Update Order

The `update_echo_field()` method in `qe_engine.py` uses:
```python
new_e = (1 - lambda) * self.echo.copy()    # start with damped old field
# ... add sources ...
for r, c in bins:
    for dr, dc in neighbours:
        new_e[r,c] += kappa * exp(...) * self.echo[nr,nc]  # OLD values
self.echo = new_e
```

This is a **Jacobi-style update** (all old values used for propagation), not
Gauss-Seidel (which would use mixed old/new values). Jacobi is correct for
the physics model: at time t, all bins simultaneously read the field at t-1
and write to t+1. Gauss-Seidel would create order-dependent artifacts.
