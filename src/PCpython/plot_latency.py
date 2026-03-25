"""
plot_latency.py
FPGA Fault-Tolerant Test System - Algorithm Latency Comparison Plotter

Description:
  Generates a grouped bar chart comparing the processing latency (clock cycles)
  of 6 algorithms across 3 metrics:
    - Avg_Clk     : Total average cycles per trial (enc + inj + dec + comp)
    - Avg_Enc_Clk : Average encoder cycles per trial
    - Avg_Dec_Clk : Average decoder cycles per trial

  Data source: manually read from the CSV test result files
  (Avg_Clk_Per_Trial, Avg_Enc_Clk_Per_Trial, Avg_Dec_Clk_Per_Trial columns).
  Use BER_Index=0 (no injection, baseline) row for the cleanest latency values.

  Chart layout:
    - Grouped bar chart: 3 bars per algorithm (Total / Enc / Dec)
    - Y-axis: clock cycles (integer)
    - Value labels on top of each bar
    - Log-scale Y-axis option (useful when 3NRM/C-RRNS-MLD latency >> others)

Usage:
  1. Read Avg_Clk_Per_Trial, Avg_Enc_Clk_Per_Trial, Avg_Dec_Clk_Per_Trial
     from the BER_Index=0 row of each algorithm's CSV result file.
  2. Fill in the LATENCY_DATA dictionary below.
  3. Run: python plot_latency.py

Output:
  latency_comparison.png  (saved to sum_result/, auto-opened)

Clock frequency reference: 50 MHz (20 ns per cycle)
  1 cycle = 20 ns
  100 cycles = 2 μs
  1000 cycles = 20 μs
"""

import os
import sys
import subprocess
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

# ─────────────────────────────────────────────────────────────────────────────
# ★ DATA ENTRY SECTION ★
#
# Fill in the average clock cycle counts from the BER_Index=0 row of each
# algorithm's CSV test result file (Random Single Bit, no injection baseline).
#
# How to read from CSV:
#   Open the CSV file → find the row where BER_Index = 0
#   Read the following columns:
#     Avg_Clk_Per_Trial     → fill into 'Total'
#     Avg_Enc_Clk_Per_Trial → fill into 'Enc'
#     Avg_Dec_Clk_Per_Trial → fill into 'Dec'
#
# All values are INTEGER clock cycle counts.
# ─────────────────────────────────────────────────────────────────────────────

LATENCY_DATA = {
    # Algorithm name must match ALGO_ORDER below
    # '2NRM-RRNS' = 2NRM-RRNS-Parallel (displayed as "2NRM-RRNS-Parallel" in chart)
    '2NRM-RRNS': {
        'Total': 33,   # ← Avg_Clk_Per_Trial     from BER_Index=0 row
        'Enc':   7,    # ← Avg_Enc_Clk_Per_Trial from BER_Index=0 row
        'Dec':   24,   # ← Avg_Dec_Clk_Per_Trial from BER_Index=0 row
    },
    # 2NRM-RRNS-Serial: same encoder, sequential FSM decoder (~225 cycles typical)
    '2NRM-RRNS-Serial': {
        'Total': 372,    # ← Fill after synthesis (Avg_Clk_Per_Trial)
        'Enc':   7,    # ← Fill after synthesis (Avg_Enc_Clk_Per_Trial)
        'Dec':   363,    # ← Fill after synthesis (Avg_Dec_Clk_Per_Trial)
    },
    '3NRM-RRNS': {
        'Total': 851,
        'Enc':   5,
        'Dec':   844,
    },
    'C-RRNS-MLD': {
        'Total': 935,
        'Enc':   5,
        'Dec':   928,
    },
    'C-RRNS-MRC': {
        'Total': 16,
        'Enc':   5,
        'Dec':   9,
    },
    'C-RRNS-CRT': {
        'Total': 14,
        'Enc':   5,
        'Dec':   7,
    },
    'RS': {
        'Total': 143,
        'Enc':   4,
        'Dec':   137,
    },
}

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR     = os.path.dirname(os.path.abspath(__file__))
SUM_RESULT_DIR = os.path.join(SCRIPT_DIR, 'result', 'sum_result')
OUTPUT_FILE    = os.path.join(SUM_RESULT_DIR, 'latency_comparison.png')

# Algorithm display order (fixed)
ALGO_ORDER = [
    '2NRM-RRNS',
    '2NRM-RRNS-Serial',
    '3NRM-RRNS',
    'C-RRNS-MLD',
    'C-RRNS-MRC',
    'C-RRNS-CRT',
    'RS',
]

# Metric styles: (color, label)
METRIC_STYLE = {
    'Total': {'color': 'steelblue',   'label': 'Total (Avg_Clk)'},
    'Enc':   {'color': 'darkorange',  'label': 'Encoder (Avg_Enc_Clk)'},
    'Dec':   {'color': 'forestgreen', 'label': 'Decoder (Avg_Dec_Clk)'},
}

# Use logarithmic Y-axis?
# Set True when algorithms have very different latencies (e.g., 3NRM=851 vs CRT=14)
# Set False for linear scale (better when values are similar)
USE_LOG_SCALE = True

# Clock frequency for time annotation
CLK_FREQ_MHZ = 50.0


def check_data_filled():
    """Check if any data has been filled in."""
    all_zero = all(
        all(v == 0 for v in data.values())
        for data in LATENCY_DATA.values()
    )
    if all_zero:
        print("[WARNING] All latency data is 0!")
        print("          Please fill in LATENCY_DATA in this script.")
        print()
        print("  How to read data from CSV files:")
        print("  1. Open each algorithm's CSV file in sum_result/")
        print("  2. Find the row where BER_Index = 0 (first data row)")
        print("  3. Read these columns:")
        print("       Avg_Clk_Per_Trial     → 'Total'")
        print("       Avg_Enc_Clk_Per_Trial → 'Enc'")
        print("       Avg_Dec_Clk_Per_Trial → 'Dec'")
        print()
        return False
    return True


def plot_latency():
    """Generate the grouped bar chart for latency comparison."""

    algos   = ALGO_ORDER
    n_algos = len(algos)
    metrics = ['Total', 'Enc', 'Dec']

    # Extract data arrays
    data = {m: [LATENCY_DATA[algo][m] for algo in algos] for m in metrics}

    # ── Layout ────────────────────────────────────────────────────────────────
    fig, ax = plt.subplots(figsize=(13, 7))

    # Bar width and positions
    bar_width = 0.22
    x = np.arange(n_algos)

    # Offsets for 3 bars per group: [-1, 0, +1] × bar_width
    offsets = np.array([-1.0, 0.0, 1.0]) * bar_width

    for i, metric in enumerate(metrics):
        style = METRIC_STYLE[metric]
        vals  = data[metric]
        xpos  = x + offsets[i]

        bars = ax.bar(xpos, vals,
                      width=bar_width,
                      color=style['color'],
                      alpha=0.85,
                      label=style['label'],
                      zorder=3)

        # Value labels on top of each bar
        for bar, val in zip(bars, vals):
            if val > 0:
                # Format: show integer cycles + time in μs
                time_us = val / CLK_FREQ_MHZ  # cycles / (MHz) = μs
                if time_us >= 1.0:
                    time_str = f"{time_us:.1f}μs"
                else:
                    time_str = f"{time_us*1000:.0f}ns"
                label = f"{val}\n({time_str})"
                ax.text(bar.get_x() + bar.get_width() / 2,
                        bar.get_height() * (1.05 if USE_LOG_SCALE else 1.02),
                        label,
                        ha='center', va='bottom',
                        fontsize=7.0, color='black', fontweight='bold',
                        linespacing=1.2)

    # ── Axis formatting ───────────────────────────────────────────────────────
    ax.set_xlabel('Algorithm', fontsize=13)
    ax.set_ylabel('Clock Cycles (log scale)' if USE_LOG_SCALE else 'Clock Cycles',
                  fontsize=12)

    # X-axis labels: rename '2NRM-RRNS' → '2NRM-RRNS-Parallel' for clarity
    xticklabels = ['2NRM-RRNS-Parallel' if a == '2NRM-RRNS' else a for a in algos]
    ax.set_xticks(x)
    ax.set_xticklabels(xticklabels, fontsize=10, rotation=10, ha='right')
    ax.set_xlim(-0.5, n_algos - 0.5)

    if USE_LOG_SCALE:
        ax.set_yscale('log')
        # Set Y lower limit to 1 to avoid log(0) issues
        all_vals = [v for m in metrics for v in data[m] if v > 0]
        if all_vals:
            ax.set_ylim(bottom=1, top=max(all_vals) * 3)
        ax.yaxis.set_major_formatter(ticker.ScalarFormatter())
        ax.yaxis.set_minor_formatter(ticker.NullFormatter())
    else:
        all_vals = [v for m in metrics for v in data[m]]
        ax.set_ylim(0, max(all_vals) * 1.3 if all_vals else 1000)
        ax.yaxis.set_major_locator(ticker.AutoLocator())

    # Grid
    ax.grid(True, axis='y', linestyle='--', alpha=0.4, zorder=0,
            which='both' if USE_LOG_SCALE else 'major')
    ax.set_axisbelow(True)

    # ── Title ─────────────────────────────────────────────────────────────────
    scale_note = "(Log Scale)" if USE_LOG_SCALE else "(Linear Scale)"
    ax.set_title(
        f'Algorithm Processing Latency Comparison — @{CLK_FREQ_MHZ:.0f}MHz {scale_note}\n'
        f'(Average across all BER points; most algorithms are BER-independent)',
        fontsize=13, fontweight='bold', pad=14
    )

    # ── Legend ────────────────────────────────────────────────────────────────
    ax.legend(fontsize=11, loc='upper right',
              framealpha=0.85, edgecolor='gray')

    plt.tight_layout()

    # ── Save & Open ───────────────────────────────────────────────────────────
    plt.savefig(OUTPUT_FILE, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"[OK] Saved: {OUTPUT_FILE}")

    try:
        if sys.platform.startswith('win'):
            os.startfile(OUTPUT_FILE)
        elif sys.platform.startswith('darwin'):
            subprocess.Popen(['open', OUTPUT_FILE])
        else:
            subprocess.Popen(['xdg-open', OUTPUT_FILE])
    except Exception:
        pass


def main():
    print("=" * 60)
    print("Algorithm Latency Comparison Plotter")
    print(f"Output: {OUTPUT_FILE}")
    print("=" * 60)
    print()

    if not check_data_filled():
        print("[ACTION REQUIRED]")
        print("  Fill in LATENCY_DATA in this script, then run again.")
        return

    print(f"[INFO] Data loaded (clock cycles @ {CLK_FREQ_MHZ:.0f}MHz):")
    print(f"  {'Algorithm':<14} {'Total':>8} {'Enc':>8} {'Dec':>8}  "
          f"{'Total(μs)':>10} {'Enc(μs)':>8} {'Dec(μs)':>8}")
    print("  " + "-" * 72)
    for algo in ALGO_ORDER:
        d = LATENCY_DATA[algo]
        t_us  = d['Total'] / CLK_FREQ_MHZ
        e_us  = d['Enc']   / CLK_FREQ_MHZ
        dc_us = d['Dec']   / CLK_FREQ_MHZ
        print(f"  {algo:<14} {d['Total']:>8} {d['Enc']:>8} {d['Dec']:>8}  "
              f"{t_us:>9.2f}μs {e_us:>7.2f}μs {dc_us:>7.2f}μs")
    print()

    plot_latency()
    print("[DONE] Chart generated and opened.")


if __name__ == '__main__':
    main()
