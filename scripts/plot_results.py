#!/usr/bin/env python3
"""Draw the report figures from results/ (run experiments.py first).

    python3 scripts/plot_results.py

Needs matplotlib (pip install matplotlib). Writes PDF and PNG files to
report/figures/.
"""

import csv
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch, Rectangle

import asm

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"
FIGURES = ROOT / "report" / "figures"

INK = "#0b0b0b"
INK_2 = "#52514e"
GRID = "#e4e3df"
BUBBLE = "#efeeeb"

SYSTEMS = ["vonneumann", "harvard", "split_cache", "unified_cache"]
SYSTEM_LABELS = {"vonneumann": "von Neumann", "harvard": "Harvard",
                 "split_cache": "Split L1 caches", "unified_cache": "Unified L1 cache"}
SYSTEM_COLORS = {"vonneumann": "#2a78d6", "harvard": "#eb6834",
                 "split_cache": "#1baf7a", "unified_cache": "#eda100"}
SYSTEM_MARKERS = {"vonneumann": "o", "harvard": "s", "split_cache": "^", "unified_cache": "D"}
BENCHMARKS = ["collatz", "crc32", "qsort", "matmul", "listwalk", "memcpy"]

plt.rcParams.update({
    "font.family": "serif",
    "font.serif": ["Times New Roman", "Times", "DejaVu Serif"],
    "font.size": 8,
    "axes.edgecolor": INK_2,
    "axes.labelcolor": INK,
    "xtick.color": INK_2,
    "ytick.color": INK_2,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "legend.frameon": False,
})


def save(figure, name):
    FIGURES.mkdir(parents=True, exist_ok=True)
    figure.savefig(FIGURES / f"{name}.pdf", bbox_inches="tight")
    figure.savefig(FIGURES / f"{name}.png", bbox_inches="tight", dpi=200)
    plt.close(figure)
    print(f"report/figures/{name}.pdf")


def read_rows(name):
    with open(RESULTS / name) as csv_file:
        rows = list(csv.DictReader(csv_file))
    for row in rows:
        for key, value in row.items():
            if key not in ("system", "benchmark"):
                row[key] = float(value)
    return rows


def geometric_mean(values):
    return math.exp(sum(math.log(value) for value in values) / len(values))


def plot_latency(rows):
    by_key = {(r["system"], r["benchmark"], int(r["mem_wait"])): r for r in rows}
    waits = sorted({int(r["mem_wait"]) for r in rows})
    figure, (line_axis, bar_axis) = plt.subplots(1, 2, figsize=(7.0, 2.5), gridspec_kw={"width_ratios": [1, 1.35]})

    for system in SYSTEMS:
        means = [geometric_mean([by_key[(system, b, w)]["cpi"] for b in BENCHMARKS]) for w in waits]
        line_axis.plot(waits, means, color=SYSTEM_COLORS[system], linewidth=2, marker=SYSTEM_MARKERS[system],
                       markersize=5, markeredgecolor="white", markeredgewidth=1, label=SYSTEM_LABELS[system])
    line_axis.set_xlabel("Main-memory wait states per word")
    line_axis.set_ylabel("CPI (geometric mean, 6 benchmarks)")
    line_axis.set_xticks(waits)
    line_axis.set_ylim(0, None)
    line_axis.grid(True, color=GRID, linewidth=0.6)
    line_axis.set_axisbelow(True)
    line_axis.legend(loc="upper left")
    line_axis.set_title("(a) CPI as main memory gets slower", fontsize=8, color=INK)

    width = 0.2
    for index, system in enumerate(SYSTEMS):
        x_positions = [i + (index - 1.5) * (width + 0.01) for i in range(len(BENCHMARKS))]
        values = [by_key[(system, b, 4)]["cpi"] for b in BENCHMARKS]
        bar_axis.bar(x_positions, values, width, color=SYSTEM_COLORS[system], label=SYSTEM_LABELS[system])
    bar_axis.set_xticks(range(len(BENCHMARKS)))
    bar_axis.set_xticklabels(BENCHMARKS)
    bar_axis.set_ylabel("CPI")
    bar_axis.yaxis.grid(True, color=GRID, linewidth=0.6)
    bar_axis.set_axisbelow(True)
    bar_axis.set_title("(b) CPI per benchmark at 4 wait states", fontsize=8, color=INK)

    figure.tight_layout()
    save(figure, "cpi_latency")


CAUSES = [("retire", "Instruction retires", "#2a78d6"),
          ("why_fetch", "Fetch stall", "#eb6834"),
          ("why_data", "Data stall", "#1baf7a"),
          ("why_load_use", "Load-use stall", "#eda100"),
          ("why_branch", "Branch flush", "#e87ba4")]


def plot_stack(rows):
    by_key = {(r["system"], r["benchmark"], int(r["mem_wait"])): r for r in rows}
    figure, axes = plt.subplots(1, 2, figsize=(7.0, 1.9), sharex=False)
    for axis, benchmark in zip(axes, ("matmul", "listwalk")):
        for position, system in enumerate(reversed(SYSTEMS)):
            r = by_key[(system, benchmark, 4)]
            left = 0.0
            for key, _, color in CAUSES:
                value = 1.0 if key == "retire" else r[key] / r["instret"]
                axis.barh(position, value, left=left, height=0.62, color=color, edgecolor="white", linewidth=1)
                left += value
            other = (r["why_reset"] + r["why_fence"]) / r["instret"]
            axis.text(left + other + 0.08, position, f"{r['cpi']:.2f}", va="center", fontsize=7, color=INK_2)
        axis.set_yticks(range(len(SYSTEMS)))
        axis.set_yticklabels([SYSTEM_LABELS[s] for s in reversed(SYSTEMS)])
        axis.set_xlabel("Cycles per instruction")
        axis.xaxis.grid(True, color=GRID, linewidth=0.6)
        axis.set_axisbelow(True)
        axis.set_title(f"{benchmark}, 4 wait states", fontsize=8, color=INK)
    handles = [Patch(facecolor=color, label=label) for _, label, color in CAUSES]
    figure.legend(handles=handles, loc="lower center", ncol=5, bbox_to_anchor=(0.5, -0.08), fontsize=7)
    figure.tight_layout(rect=(0, 0.06, 1, 1))
    save(figure, "cpi_stack")


def plot_cache_sweep(rows):
    by_key = {(r["system"], r["benchmark"], int(r["cache_sets"])): r for r in rows}
    sets = sorted({int(r["cache_sets"]) for r in rows})
    total_bytes = [2 * s * 16 for s in sets]
    figure, (cpi_axis, hit_axis) = plt.subplots(1, 2, figsize=(7.0, 2.3))

    for system in ("split_cache", "unified_cache"):
        means = [geometric_mean([by_key[(system, b, s)]["cpi"] for b in BENCHMARKS]) for s in sets]
        cpi_axis.plot(total_bytes, means, color=SYSTEM_COLORS[system], linewidth=2, marker=SYSTEM_MARKERS[system],
                      markersize=5, markeredgecolor="white", markeredgewidth=1, label=SYSTEM_LABELS[system])
    cpi_axis.set_xscale("log", base=2)
    cpi_axis.set_xticks(total_bytes)
    cpi_axis.set_xticklabels([f"{b // 1024} KB" if b >= 1024 else f"{b} B" for b in total_bytes])
    cpi_axis.set_xlabel("Total L1 capacity (split: I + D)")
    cpi_axis.set_ylabel("CPI (geometric mean)")
    cpi_axis.grid(True, color=GRID, linewidth=0.6)
    cpi_axis.set_axisbelow(True)
    cpi_axis.legend(loc="upper right")
    cpi_axis.set_title("(a) Split vs unified cache, 4 wait states", fontsize=8, color=INK)

    # Palette slots 5-8, so benchmarks never borrow a system's colour from panel (a).
    benchmark_styles = (("qsort", "#e87ba4", "o"), ("matmul", "#008300", "s"),
                        ("listwalk", "#6250d6", "^"), ("memcpy", "#e34948", "D"))
    for benchmark, color, marker in benchmark_styles:
        rates = [100 * (1 - by_key[("split_cache", benchmark, s)]["dc_miss"] / by_key[("split_cache", benchmark, s)]["dc_access"])
                 for s in sets]
        hit_axis.plot([s * 16 for s in sets], rates, color=color, linewidth=2, marker=marker, markersize=4,
                      markeredgecolor="white", markeredgewidth=1, label=benchmark)
    hit_axis.set_xscale("log", base=2)
    hit_axis.set_xticks([s * 16 for s in sets])
    hit_axis.set_xticklabels([f"{s * 16 // 1024} KB" if s * 16 >= 1024 else f"{s * 16} B" for s in sets])
    hit_axis.set_xlabel("D-cache capacity")
    hit_axis.set_ylabel("D-cache hit rate (%)")
    hit_axis.grid(True, color=GRID, linewidth=0.6)
    hit_axis.set_axisbelow(True)
    hit_axis.legend(loc="lower right", ncol=2)
    hit_axis.set_title("(b) D-cache hit rate against size", fontsize=8, color=INK)

    figure.tight_layout()
    save(figure, "cache_sweep")


def read_trace(system):
    cycles = []
    for line in (RESULTS / f"trace_memcpy_{system}.txt").read_text().splitlines():
        fields = {}
        for item in line.split()[2:]:
            key, value = item.split("=")
            fields[key] = value
        stages = {}
        for stage in ("id", "ex", "mem", "wb"):
            valid, pc = fields[stage].split(":")
            stages[stage] = int(pc, 16) if valid == "1" else None
        stages["if"] = int(fields["if"], 16) if fields["ir"] == "1" else None
        stages["dport"] = fields["dreq"] == "1" and fields["drdy"] == "1"
        cycles.append(stages)
    return cycles


def plot_pipeline():
    program, _ = asm.assemble((ROOT / "programs" / "memcpy.s").read_text())

    def mnemonic(pc):
        return program[pc // 4][1].split()[0]

    window = 18
    figure, axes = plt.subplots(2, 1, figsize=(7.0, 3.4))
    for axis, system in zip(axes, ("vonneumann", "harvard")):
        trace = read_trace(system)[:window]
        rows = [("if", "IF  (I-port)"), ("id", "ID"), ("ex", "EX"), ("mem", "MEM (D-port)"), ("wb", "WB")]
        for row_index, (stage, label) in enumerate(rows):
            y = len(rows) - 1 - row_index
            for column, cycle in enumerate(trace):
                pc = cycle[stage]
                if pc is None:
                    fill, text, color = BUBBLE, "", INK_2
                    if stage == "if":
                        text = "wait"
                else:
                    text, color = mnemonic(pc), INK
                    fill = "white"
                    if stage == "if":
                        fill = "#d4e4f7"
                    if stage == "mem" and text in ("lw", "sw"):
                        fill = "#fbd9cb"
                axis.add_patch(Rectangle((column + 0.04, y + 0.1), 0.92, 0.8, facecolor=fill, edgecolor=GRID, linewidth=0.6))
                axis.text(column + 0.5, y + 0.5, text, ha="center", va="center", fontsize=6.5, color=color)
        retired = sum(1 for cycle in trace if cycle["wb"] is not None)
        axis.set_xlim(0, window)
        axis.set_ylim(0, len(rows))
        axis.set_yticks([len(rows) - 1 - i + 0.5 for i in range(len(rows))])
        axis.set_yticklabels([label for _, label in rows])
        axis.set_xticks([c + 0.5 for c in range(window)])
        axis.set_xticklabels([str(c + 1) for c in range(window)])
        axis.tick_params(length=0)
        for spine in axis.spines.values():
            spine.set_visible(False)
        axis.set_title(f"{SYSTEM_LABELS[system]}, 0 wait states: {retired} instructions finish in {window} cycles",
                       fontsize=8, color=INK, loc="left")
    axes[1].set_xlabel("Cycle (memcpy copy loop, steady state)")
    handles = [Patch(facecolor="#d4e4f7", label="instruction fetched"), Patch(facecolor="#fbd9cb", label="data access"),
               Patch(facecolor=BUBBLE, label="bubble / fetch waiting")]
    figure.legend(handles=handles, loc="lower center", ncol=3, bbox_to_anchor=(0.5, -0.03), fontsize=7)
    figure.tight_layout(rect=(0, 0.04, 1, 1))
    save(figure, "pipeline_trace")


if __name__ == "__main__":
    latency_rows = read_rows("latency_sweep.csv")
    plot_latency(latency_rows)
    plot_stack(latency_rows)
    plot_cache_sweep(read_rows("cache_sweep.csv"))
    plot_pipeline()
