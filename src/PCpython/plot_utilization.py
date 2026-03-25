"""
plot_utilization.py
FPGA Fault-Tolerant Test System - Resource Utilization Comparison Plotter

Description:
  Reads resource utilization data (manually entered from Vivado utilization
  screenshots) and generates a grouped bar chart comparing 6 algorithms.

  Resources plotted:
    - LUT  : Look-Up Tables (logic complexity)
    - FF   : Flip-Flops / Registers (pipeline depth)
    - DSP  : DSP48E1 blocks (multiplier usage)
    - BRAM : Block RAM tiles (memory usage)

  Resources intentionally excluded:
    - IO   : Shared by all algorithms (UART/LED), not algorithm-specific
    - BUFG : Clock buffers, identical across all builds
    - MMCM : Shared clock generator, identical across all builds
    - CARRY4: Carry chains, subsumed by LUT count

  Chart layout:
    - Dual Y-axis: left for LUT/FF (large values), right for DSP/BRAM (small)
    - Grouped bars per algorithm, color-coded by resource type
    - Value labels on top of each bar

Usage:
  1. Open each 'utilization *.png' screenshot in sum_result/
  2. Fill in the UTILIZATION_DATA dictionary below with the actual numbers
  3. Run: python plot_utilization.py

Output:
  utilization_comparison.png  (saved to sum_result/, auto-opened)

Artix-7 xc7a100t Total Resources (for reference):
  LUT  : 63,400
  FF   : 126,800
  DSP  : 240
  BRAM : 135 (each = 36Kb tile)
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
# INPUT MODE: Fill in the UTILIZATION PERCENTAGE (Util% column) from each
# screenshot. The script will automatically convert to absolute counts.
#
# Vivado Utilization Report columns:
#   Site Type | Used | Fixed | Available | Util%
#   ──────────┼──────┼───────┼───────────┼──────
#   Slice LUTs│12736 │   0   │   63400   │20.09%   ← fill in 20.09 (the %)
#
# How to read each resource:
#   LUT  → "Slice LUTs" row,          "Util%" column  (e.g. 20.09)
#   FF   → "Slice Registers" row,     "Util%" column  (e.g. 29.00)
#   DSP  → "DSPs" row,                "Util%" column  (e.g. 5.00)
#   BRAM → "Block RAM Tile" row,      "Util%" column  (e.g. 20.00)
#
# The script converts: Used = round(Util% / 100 * Device_Total)
#   Artix-7 xc7a100t totals: LUT=63400, FF=126800, DSP=240, BRAM=135
# ─────────────────────────────────────────────────────────────────────────────

# Set to True: values below are Util% (will be auto-converted to absolute count)
# Set to False: values below are absolute Used counts
INPUT_AS_PERCENTAGE = True

UTILIZATION_DATA = {
    # Algorithm name must match the display order in ALGO_ORDER below
    # '2NRM-RRNS' = 2NRM-RRNS-Parallel (displayed as "2NRM-RRNS-Parallel" in chart)
    '2NRM-RRNS': {
        'LUT':  22,    # ← Fill from 'utilization 2NRM.png'  (Util% value)
        'FF':   29,    # ← Fill from 'utilization 2NRM.png'  (Util% value)
        'DSP':  0,     # ← Fill from 'utilization 2NRM.png'  (Util% value)
        'BRAM': 20,    # ← Fill from 'utilization 2NRM.png'  (Util% value)
    },
    # 2NRM-RRNS-Serial: same encoder as 2NRM-Parallel, only decoder differs
    '2NRM-RRNS-Serial': {
        'LUT':  4,     # ← Fill from 'utilization 2NRM-Serial.png' (Util% value)
        'FF':   2,     # ← Fill from 'utilization 2NRM-Serial.png' (Util% value)
        'DSP':  0,     # ← Fill from 'utilization 2NRM-Serial.png' (Util% value)
        'BRAM': 21,     # ← Fill from 'utilization 2NRM-Serial.png' (Util% value)
    },
    '3NRM-RRNS': {
        'LUT':  5,     # ← Fill from 'utilization 3NRM.png'  (Util% value)
        'FF':   2,     # ← Fill from 'utilization 3NRM.png'  (Util% value)
        'DSP':  1,     # ← Fill from 'utilization 3NRM.png'  (Util% value)
        'BRAM': 20,    # ← Fill from 'utilization 3NRM.png'  (Util% value)
    },
    'C-RRNS-MLD': {
        'LUT':  6,     # ← Fill from 'utilization C-RRNS-MLD.png'
        'FF':   2,
        'DSP':  1,
        'BRAM': 19,
    },
    'C-RRNS-MRC': {
        'LUT':  2,     # ← Fill from 'utilization C-RRNS-MRC.png'
        'FF':   1,
        'DSP':  1,
        'BRAM': 20,
    },
    'C-RRNS-CRT': {
        'LUT':  2,     # ← Fill from 'utilization C-RRNS-CRT.png'
        'FF':   1,
        'DSP':  1,
        'BRAM': 20,
    },
    'RS': {
        'LUT':  3,     # ← Fill from 'utilization RS.png'
        'FF':   2,
        'DSP':  0,
        'BRAM': 20,
    },
}

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR     = os.path.dirname(os.path.abspath(__file__))
SUM_RESULT_DIR = os.path.join(SCRIPT_DIR, 'result', 'sum_result')
OUTPUT_FILE    = os.path.join(SUM_RESULT_DIR, 'utilization_comparison.png')

# Algorithm display order (fixed, matches legend)
ALGO_ORDER = [
    '2NRM-RRNS',
    '2NRM-RRNS-Serial',
    '3NRM-RRNS',
    'C-RRNS-MLD',
    'C-RRNS-MRC',
    'C-RRNS-CRT',
    'RS',
]

# Artix-7 xc7a100t total resources (for utilization % annotation)
DEVICE_TOTAL = {
    'LUT':  63400,
    'FF':   126800,
    'DSP':  240,
    'BRAM': 135,
}

# Resource styles: (color, label)
RESOURCE_STYLE = {
    'LUT':  {'color': 'steelblue',   'label': 'LUT'},
    'FF':   {'color': 'darkorange',  'label': 'FF (Register)'},
    'DSP':  {'color': 'forestgreen', 'label': 'DSP48E1'},
    'BRAM': {'color': 'crimson',     'label': 'BRAM (36Kb)'},
}

# Resources on left Y-axis (large values) and right Y-axis (small values)
LEFT_RESOURCES  = ['LUT', 'FF']    # Hundreds to thousands
RIGHT_RESOURCES = ['DSP', 'BRAM']  # Single digits to tens


def check_data_filled():
    """Check if all data has been filled in (no zeros for all resources)."""
    all_zero = all(
        all(v == 0 for v in data.values())
        for data in UTILIZATION_DATA.values()
    )
    if all_zero:
        print("[WARNING] All utilization data is 0!")
        print("          Please fill in UTILIZATION_DATA in this script")
        print("          by reading values from the utilization PNG screenshots.")
        print()
        print("  Screenshots location:")
        print(f"  {SUM_RESULT_DIR}")
        print()
        print("  Files to read:")
        for algo in ALGO_ORDER:
            # Map algo name to screenshot filename
            name_map = {
                '2NRM-RRNS':        'utilization 2NRM.png',
                '2NRM-RRNS-Serial': 'utilization 2NRM-Serial.png',
                '3NRM-RRNS':        'utilization 3NRM.png',
                'C-RRNS-MLD':       'utilization C-RRNS-MLD.png',
                'C-RRNS-MRC':       'utilization C-RRNS-MRC.png',
                'C-RRNS-CRT':       'utilization C-RRNS-CRT.png',
                'RS':               'utilization RS.png',
            }
            print(f"    {algo:20s} ← {name_map.get(algo, '?')}")
        print()
        return False
    return True


def open_screenshots():
    """Open all utilization screenshots for reference."""
    name_map = {
        '2NRM-RRNS':  'utilization 2NRM.png',
        '3NRM-RRNS':  'utilization 3NRM.png',
        'C-RRNS-MLD': 'utilization C-RRNS-MLD.png',
        'C-RRNS-MRC': 'utilization C-RRNS-MRC.png',
        'C-RRNS-CRT': 'utilization C-RRNS-CRT.png',
        'RS':         'utilization RS.png',
    }
    print("[INFO] Opening utilization screenshots for reference...")
    for algo, fname in name_map.items():
        fpath = os.path.join(SUM_RESULT_DIR, fname)
        if os.path.isfile(fpath):
            try:
                if sys.platform.startswith('win'):
                    os.startfile(fpath)
                elif sys.platform.startswith('darwin'):
                    subprocess.Popen(['open', fpath])
                else:
                    subprocess.Popen(['xdg-open', fpath])
            except Exception:
                pass


def convert_to_absolute(raw_data: dict) -> dict:
    """
    If INPUT_AS_PERCENTAGE=True, convert Util% values to absolute Used counts.
    Formula: Used = round(Util% / 100 * Device_Total)
    """
    if not INPUT_AS_PERCENTAGE:
        return raw_data  # Already absolute counts

    converted = {}
    for algo, res_dict in raw_data.items():
        converted[algo] = {}
        for res, val in res_dict.items():
            total = DEVICE_TOTAL[res]
            converted[algo][res] = round(val / 100.0 * total)
    return converted


def plot_utilization():
    """Generate the grouped bar chart with dual Y-axes."""

    algos = ALGO_ORDER
    n_algos = len(algos)
    resources = ['LUT', 'FF', 'DSP', 'BRAM']

    # Convert percentage to absolute counts if needed
    abs_data = convert_to_absolute(UTILIZATION_DATA)

    # Extract data arrays (absolute counts)
    data = {res: [abs_data[algo][res] for algo in algos] for res in resources}

    # ── Layout ────────────────────────────────────────────────────────────────
    fig, ax1 = plt.subplots(figsize=(13, 7))
    ax2 = ax1.twinx()   # Right Y-axis for DSP and BRAM

    # Bar width and positions
    bar_width = 0.18
    x = np.arange(n_algos)

    # Offsets for 4 bars per group: [-1.5, -0.5, +0.5, +1.5] × bar_width
    offsets = np.array([-1.5, -0.5, 0.5, 1.5]) * bar_width

    bars_all = []
    labels_all = []

    for i, res in enumerate(resources):
        style = RESOURCE_STYLE[res]
        vals  = data[res]
        xpos  = x + offsets[i]

        # Choose axis
        ax = ax1 if res in LEFT_RESOURCES else ax2

        bars = ax.bar(xpos, vals,
                      width=bar_width,
                      color=style['color'],
                      alpha=0.85,
                      label=style['label'],
                      zorder=3)
        bars_all.append(bars)
        labels_all.append(style['label'])

        # Value labels on top of each bar
        # Show absolute count; if input was %, also show the original % value
        raw_vals = [UTILIZATION_DATA[algo][res] for algo in algos]
        for bar, val, raw in zip(bars, vals, raw_vals):
            if val > 0:
                if INPUT_AS_PERCENTAGE:
                    label = f"{val}\n({raw:.1f}%)"
                else:
                    label = str(val)
                ax.text(bar.get_x() + bar.get_width() / 2,
                        bar.get_height() + ax.get_ylim()[1] * 0.01,
                        label,
                        ha='center', va='bottom',
                        fontsize=7.0, color='black', fontweight='bold',
                        linespacing=1.2)

    # ── Axis formatting ───────────────────────────────────────────────────────
    ax1.set_xlabel('Algorithm', fontsize=13)
    ax1.set_ylabel('LUT / FF Count', fontsize=12, color='black')
    ax2.set_ylabel('DSP48E1 / BRAM (36Kb) Count', fontsize=12, color='black')

    # X-axis labels: rename '2NRM-RRNS' → '2NRM-RRNS-Parallel' for clarity
    xticklabels = [a.replace('2NRM-RRNS', '2NRM-RRNS-Parallel') if a == '2NRM-RRNS' else a
                   for a in algos]
    ax1.set_xticks(x)
    ax1.set_xticklabels(xticklabels, fontsize=10, rotation=10, ha='right')
    ax1.set_xlim(-0.5, n_algos - 0.5)

    # Y-axis: start from 0, add 20% headroom for value labels
    lut_ff_max = max(max(data['LUT']), max(data['FF']), 1)
    dsp_bram_max = max(max(data['DSP']), max(data['BRAM']), 1)
    ax1.set_ylim(0, lut_ff_max * 1.25)
    ax2.set_ylim(0, dsp_bram_max * 1.25)

    # Integer ticks on right axis
    ax2.yaxis.set_major_locator(ticker.MaxNLocator(integer=True))

    # Grid (behind bars)
    ax1.grid(True, axis='y', linestyle='--', alpha=0.4, zorder=0)
    ax1.set_axisbelow(True)

    # ── Title ─────────────────────────────────────────────────────────────────
    ax1.set_title(
        'FPGA Resource Utilization Comparison — Artix-7 xc7a100t\n'
        '(LUT & FF: left axis  |  DSP48E1 & BRAM: right axis)',
        fontsize=13, fontweight='bold', pad=14
    )

    # ── Legend ────────────────────────────────────────────────────────────────
    # Combine handles from both axes
    handles1, labels1 = ax1.get_legend_handles_labels()
    handles2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(handles1 + handles2, labels1 + labels2,
               fontsize=10, loc='upper left',
               framealpha=0.85, edgecolor='gray')

    # ── Utilization % annotation (small text below each group) ───────────────
    # If input was %, use directly; otherwise compute from absolute counts
    for i, algo in enumerate(algos):
        raw = UTILIZATION_DATA[algo]
        if INPUT_AS_PERCENTAGE:
            lut_pct  = raw['LUT']
            ff_pct   = raw['FF']
            dsp_pct  = raw['DSP']
            bram_pct = raw['BRAM']
        else:
            lut_pct  = raw['LUT']  / DEVICE_TOTAL['LUT']  * 100
            ff_pct   = raw['FF']   / DEVICE_TOTAL['FF']   * 100
            dsp_pct  = raw['DSP']  / DEVICE_TOTAL['DSP']  * 100
            bram_pct = raw['BRAM'] / DEVICE_TOTAL['BRAM'] * 100
        annotation = (f"LUT:{lut_pct:.1f}%\n"
                      f"FF:{ff_pct:.1f}%\n"
                      f"DSP:{dsp_pct:.1f}%\n"
                      f"BRAM:{bram_pct:.1f}%")
        ax1.text(i, -lut_ff_max * 0.18, annotation,
                 ha='center', va='top',
                 fontsize=6.5, color='gray',
                 transform=ax1.transData)

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
    print("FPGA Resource Utilization Comparison Plotter")
    print(f"Data source: {SUM_RESULT_DIR}")
    print("=" * 60)
    print()

    # Check if data is filled
    if not check_data_filled():
        # Open screenshots to help user fill in data
        open_screenshots()
        print("[ACTION REQUIRED]")
        print("  1. Read the LUT/FF/DSP/BRAM values from the opened screenshots")
        print("  2. Fill in the UTILIZATION_DATA dictionary in this script")
        print("  3. Run this script again to generate the chart")
        return

    print("[INFO] Data loaded:")
    print(f"  {'Algorithm':<14} {'LUT':>6} {'FF':>7} {'DSP':>5} {'BRAM':>6}")
    print("  " + "-" * 42)
    for algo in ALGO_ORDER:
        d = UTILIZATION_DATA[algo]
        print(f"  {algo:<14} {d['LUT']:>6} {d['FF']:>7} {d['DSP']:>5} {d['BRAM']:>6}")
    print()

    plot_utilization()
    print("[DONE] Chart generated and opened.")


if __name__ == '__main__':
    main()
