"""Echo energy field, resonance, perturbation, and SA acceptance."""
import numpy as np
import pandas as pd


class QEEngine:
    def __init__(self, cells, nets, bins_df, paths, cong, args):
        self.cells   = cells.copy()
        self.nets    = nets
        self.bins_df = bins_df.copy()
        self.paths   = paths
        self.cong    = cong
        self.args    = args
        self.n_rows  = int(bins_df["row"].max()) + 1
        self.n_cols  = int(bins_df["col"].max()) + 1
        self.echo    = np.zeros((self.n_rows, self.n_cols))
        self._build_cell_bin_map()
        self._build_path_cell_sets()

    def _build_cell_bin_map(self):
        b = self.bins_df
        self._cell_bin = {}
        for _, c in self.cells.iterrows():
            m = b[(b.llx <= c.x) & (c.x < b.urx) &
                  (b.lly <= c.y) & (c.y < b.ury)]
            self._cell_bin[c["name"]] = (
                (int(m.iloc[0].row), int(m.iloc[0].col))
                if not m.empty else (0, 0))

    def _build_path_cell_sets(self):
        self._path_cells = {
            int(r.path_id): str(r.cell_sequence).split(",")
            for _, r in self.paths.iterrows()
        }

    def update_echo_field(self):
        args   = self.args
        new_e  = (1.0 - args.lambda_d) * self.echo.copy()
        T_char = max(abs(float(self.cells["slack"].min())), 1e-6)

        for _, c in self.cells.iterrows():
            if c["fixed"]:
                continue
            br, bc = self._cell_bin.get(c["name"], (0, 0))
            crit   = float(c["criticality"])
            phi_t  = max(0.0, -float(c["slack"])) / T_char
            cr     = self.cong[(self.cong.row == br) & (self.cong.col == bc)]
            phi_c  = float(cr["overflow"].values[0]) if not cr.empty else 0.0
            new_e[br, bc] += 1.5 * crit * phi_t + 1.0 * phi_c

        sig2 = args.sigma_b ** 2
        for r in range(self.n_rows):
            for c in range(self.n_cols):
                for dr in (-1, 0, 1):
                    for dc in (-1, 0, 1):
                        if dr == 0 and dc == 0:
                            continue
                        nr, nc = r + dr, c + dc
                        if 0 <= nr < self.n_rows and 0 <= nc < self.n_cols:
                            new_e[r, c] += (args.kappa *
                                np.exp(-(dr**2 + dc**2) / sig2) *
                                self.echo[nr, nc])
        self.echo = new_e

    def _echo_grad(self, x, y):
        b0 = self.bins_df.iloc[0]
        bw = max(float(b0.urx) - float(b0.llx), 1.0)
        bh = max(float(b0.ury) - float(b0.lly), 1.0)
        r  = int(np.clip(y / bh, 0, self.n_rows - 1))
        c  = int(np.clip(x / bw, 0, self.n_cols - 1))
        gx = (self.echo[r, min(c+1, self.n_cols-1)] -
              self.echo[r, max(c-1, 0)]) / 2.0
        gy = (self.echo[min(r+1, self.n_rows-1), c] -
              self.echo[max(r-1, 0), c]) / 2.0
        return gx, gy

    def _resonance(self, name):
        row = self.cells[self.cells["name"] == name]
        if row.empty:
            return 0.0, 0.0
        row = row.iloc[0]
        fx = fy = 0.0
        sig2 = 5000.0 ** 2   # σ_r = 5000 DBU = 5 µm (resonance radius)
        for cells_list in self._path_cells.values():
            if name not in cells_list:
                continue
            for other_name in cells_list:
                if other_name == name:
                    continue
                oth = self.cells[self.cells["name"] == other_name]
                if oth.empty:
                    continue
                oth  = oth.iloc[0]
                dx   = float(oth.x) - float(row.x)
                dy   = float(oth.y) - float(row.y)
                dist = np.sqrt(dx**2 + dy**2) + 1e-9
                R = (float(row.criticality) * float(oth.criticality) *
                     np.exp(-dist**2 / (2 * sig2)))
                fx += R * dx / dist
                fy += R * dy / dist
        return fx, fy

    def propose_moves(self):
        args    = self.args
        alpha_t = args.alpha0 * (1.0 - args.iter / args.max_iter) ** 1.5
        moves   = []
        for _, c in self.cells.iterrows():
            if c["fixed"]:
                moves.append({"name": c["name"], "new_x": c.x, "new_y": c.y,
                              "delta_cost": 0.0, "status": "SKIP_FIXED"})
                continue
            gx, gy = self._echo_grad(float(c.x), float(c.y))
            rx, ry = self._resonance(c["name"])
            moves.append({
                "name":       c["name"],
                "new_x":      float(c.x) - alpha_t * gx + args.xi * rx,
                "new_y":      float(c.y) - alpha_t * gy + args.xi * ry,
                "delta_cost": 0.0,
                "status":     "PROPOSE"
            })
        return moves

    def apply_acceptance(self, proposals, cost_eval):
        args = self.args
        Tc   = max(args.tc0 * (1.0 - args.iter / args.max_iter), 1e-6)
        base = cost_eval.compute(self.cells)
        out  = []
        for prop in proposals:
            if prop["status"] != "PROPOSE":
                out.append(prop)
                continue
            nm   = prop["name"]
            mask = self.cells["name"] == nm
            ox   = float(self.cells.loc[mask, "x"].values[0])
            oy   = float(self.cells.loc[mask, "y"].values[0])
            self.cells.loc[mask, "x"] = prop["new_x"]
            self.cells.loc[mask, "y"] = prop["new_y"]
            nc   = cost_eval.compute(self.cells)
            dC   = nc - base
            if dC < 0 or np.random.random() < np.exp(-dC / Tc):
                prop["status"] = "ACCEPT"
                prop["delta_cost"] = dC
                base = nc
            else:
                self.cells.loc[mask, "x"] = ox
                self.cells.loc[mask, "y"] = oy
                prop["status"] = "REJECT"
                prop["delta_cost"] = dC
            out.append(prop)
        return out
