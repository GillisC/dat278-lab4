
import argparse
import csv
from typing import List, Dict, Tuple
import matplotlib.pyplot as plt
import matplotlib.transforms as transforms

def load_rows(csv_file: str) -> List[Dict[str, str]]:
    with open(csv_file, newline='') as f:
        reader = csv.DictReader(f)
        return list(reader)

def to_float(s: str) -> float:
    return float(s.strip())

def pareto_front_minimize(points: List[Tuple[float, float]]):
    """Return indices of Pareto-optimal points (minimize both x and y).
    points: list of (x, y)
    """
    # Sort by x (time) ascending, then sweep and keep strictly decreasing y (energy)
    indexed = list(enumerate(points))
    indexed.sort(key=lambda t: (t[1][0], t[1][1]))
    pareto_idx = []
    best_y = float('inf')
    for idx, (x, y) in indexed:
        if y < best_y:
            pareto_idx.append(idx)
            best_y = y
    # Keep original order of x for a nicer line
    pareto_idx.sort(key=lambda i: points[i][0])
    return pareto_idx

def main():
    parser = argparse.ArgumentParser(description="Plot Pareto curve (Execution Time vs Energy).")
    parser.add_argument("--csv", required=True, help="CSV with columns: config,governor,freq_mhz,time_s,energy_j")
    parser.add_argument("--out", default=None, help="Optional path to save the figure (PNG).")

    args = parser.parse_args()

    rows = load_rows(args.csv)
    labels = [r.get("freq_mhz", "") for r in rows]
    times = [to_float(r["time_ms"]) for r in rows]
    energies = [to_float(r["energy_mj"]) for r in rows]

    # Compute Pareto front (minimize time and energy)
    pts = list(zip(times, energies))
    pf_idx = pareto_front_minimize(pts)

    # Plot
    plt.figure(figsize=(7, 5))
    plt.scatter(times, energies, label="All configurations")
    for lab, x, y in zip(labels, times, energies):
        trans = transforms.ScaledTranslation(5/72, 0, plt.gcf().dpi_scale_trans)
        plt.text(x, y, lab, fontsize=8, transform=plt.gca().transData + trans)

    # Pareto line
    pf_times = [times[i] for i in pf_idx]
    pf_energies = [energies[i] for i in pf_idx]
    plt.plot(pf_times, pf_energies, "o-", label="Pareto front")

    plt.title("Pareto Curve")
    plt.xlabel("Execution Time (ms)")
    plt.ylabel("Energy (mJ)")

    # Optional: invert axes so 'better' is visually down/left.
    # Comment these lines if you prefer the conventional orientation.
    plt.gca().invert_xaxis()
    plt.gca().invert_yaxis()

    # plt.grid(True)
    plt.legend()
    #plt.tight_layout()

    if args.out:
        plt.savefig(args.out, dpi=150)
    plt.show()

if __name__ == "__main__":
    main()
