"""Cost evaluator: α·HPWL + β·TNS + γ·Overflow + δ·Displacement + η·GapPenalty"""
import numpy as np
import pandas as pd


class CostEvaluator:
    ALPHA = 1.0
    BETA  = 2.5
    GAMMA = 3.0
    DELTA = 0.5
    ETA   = 1.2

    def __init__(self, cells0, nets, bins_df, rho_target=0.65):
        self.cells0    = cells0.copy()
        self.nets      = nets
        self.bins_df   = bins_df
        self.rho_tgt   = rho_target

    def compute(self, cells):
        return (self.ALPHA * self._hpwl(cells) +
                self.BETA  * self._tns(cells) +
                self.GAMMA * self._overflow(cells) +
                self.DELTA * self._displacement(cells) +
                self.ETA   * self._gap_penalty(cells))

    def _hpwl(self, cells):
        cp = cells.set_index("name")[["x", "y"]]
        total = 0.0
        for _, net in self.nets.iterrows():
            ids = str(net.get("cell_ids", "")).split(",")
            xs = [float(cp.loc[i, "x"]) for i in ids if i in cp.index]
            ys = [float(cp.loc[i, "y"]) for i in ids if i in cp.index]
            if len(xs) > 1:
                total += (max(xs) - min(xs)) + (max(ys) - min(ys))
        return total

    def _tns(self, cells):
        slacks = cells["slack"].astype(float)
        return float(slacks[slacks < 0].sum()) * -1.0

    def _overflow(self, cells):
        b = self.bins_df.copy()
        b["d"] = 0.0
        for _, c in cells.iterrows():
            mask = ((b.llx <= c.x) & (c.x < b.urx) &
                    (b.lly <= c.y) & (c.y < b.ury))
            area = float(c.get("width", 140)) * float(c.get("height", 280))
            bin_area = ((b.loc[mask, "urx"] - b.loc[mask, "llx"]) *
                        (b.loc[mask, "ury"] - b.loc[mask, "lly"]))
            b.loc[mask, "d"] += area / (bin_area + 1e-9)
        ov = np.maximum(0, b["d"] - self.rho_tgt)
        return float((ov ** 2).sum())

    def _displacement(self, cells):
        m = cells.merge(self.cells0[["name", "x", "y"]],
                        on="name", suffixes=("", "_0"))
        return float(((m.x - m.x_0)**2 + (m.y - m.y_0)**2).sum())

    def _gap_penalty(self, cells):
        total = 0.0
        count = 0
        for y_row, grp in cells.groupby("y"):
            x_min = float(grp["x"].min())
            x_max = float((grp["x"] + grp.get("width", 140)).max())
            tw = x_max - x_min
            if tw <= 0:
                continue
            cw = float(grp.get("width", 140).sum())
            total += max(0.0, tw - cw) / tw
            count += 1
        return total / (count + 1e-9)
