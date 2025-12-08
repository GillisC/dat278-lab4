import matplotlib.pyplot as plt
import numpy as np
from datetime import datetime

# -------------------------------
# Editable parameters
# -------------------------------
# peak_flops = 9.59     # GFLOP/s single-threaded performance
peak_flops = 37.54    # GFLOP/s multi-threaded performance 
bandwidth = 7.74       # GB/s
# labels = ['matmul_1', 'matmul_2', 'matmul_3', 'matmul_4', 'matmul_5']
labels = ['fma', 'dot', 'poly', 'triad']
# measured_flops = [2.787, 1.128, 4.735, 0.522]  #÷ GFLOP/s single_threaded with default OI
# measured_flops = [3.08, 1.00, 4.31, 0.498]  #÷ GFLOP/s single_threaded with lower OI

# measured_flops = [5.48, 1.76, 5.46, 0.82]  # GFLOP/s multi_threaded with default OI
measured_flops = [7.718, 1.57, 7.72, 0.807]  # GFLOP/s multi_threaded with lower OI 
# OIs = [25, 0.25, 50, 0.125]             # FLOPs per byte with default OI
OIs = [3.75, 0.25, 5, 0.125]             # FLOPs per byte with lower OI
output_file = "roofline_multi_core_lower_OI.png"

# -------------------------------
# Compute intersection
# -------------------------------
ai_intersect = peak_flops / bandwidth
perf_intersect = peak_flops

# -------------------------------
# Generate Roofline
# -------------------------------
ai = np.logspace(-2, 3, 500)
mem_bound = bandwidth * ai
comp_bound = np.full_like(ai, peak_flops)
roof = np.minimum(mem_bound, comp_bound)

# -------------------------------
# Plot setup
# -------------------------------
plt.figure(figsize=(8, 6))
plt.loglog(ai, roof, label="Roofline", color="black", linewidth=2)
plt.loglog(ai, mem_bound, "--", color="gray", label="Memory BW limit")
plt.loglog(ai, comp_bound, "--", color="red", label="Compute peak")

# Intersection point
plt.scatter(ai_intersect, perf_intersect, color="green", s=100, marker="x", zorder=6)
plt.text(ai_intersect * 0.9, perf_intersect * 1.2,
         f"({ai_intersect:.2f}, {perf_intersect:.1f})",
         fontsize=12, color="#006600", ha="right", va="bottom")

# -------------------------------
# Colors for points
# -------------------------------
tab_colors = list(plt.get_cmap('tab10').colors)
# skip first few (they’re similar to blue/red/green)
avail_colors = tab_colors[3:]  

# -------------------------------
# Measured points and guide lines
# -------------------------------
for i, label in enumerate(labels):
    oi = OIs[i]
    perf = measured_flops[i]
    color = avail_colors[i % len(avail_colors)]

    # Compute roofline limit at this OI
    roof_y = min(peak_flops, bandwidth * oi)

    # Vertical dashed line to the roofline
    plt.loglog([oi, oi], [1e-2, roof_y], linestyle="--", color=color, alpha=0.6)

    # Scatter point
    plt.scatter(oi, perf, color=color, s=80, zorder=5, label=label)

# -------------------------------
# Final formatting
# -------------------------------
plt.title("Roofline Model", fontsize=14, weight="bold")
plt.xlabel("Operational Intensity (FLOPs / Byte)", fontsize=12)
plt.ylabel("Performance (GFLOP/s)", fontsize=12)
plt.legend()
plt.grid(True, which="both", linestyle="--", linewidth=0.5)
plt.tight_layout()

# Save image
plt.savefig(output_file, dpi=300)
plt.close()

print(f"✅ Roofline plot saved to '{output_file}'")
print(f"🟢 Intersection: OI = {ai_intersect:.2f} FLOPs/Byte, Perf = {perf_intersect:.2f} GFLOP/s")
