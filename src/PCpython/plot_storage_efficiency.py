"""
plot_storage_efficiency.py
FPGA Fault-Tolerant Test System - Storage Efficiency Comparison

Description:
  Generates a stacked bar chart comparing the codeword structure of 4 ECC
  algorithms for storing a 16-bit (0~65535) unsigned integer:

    Algorithm   | Data bits | Redundancy bits | Total codeword
    ------------|-----------|-----------------|---------------
    2NRM-RRNS   |    16     |      25         |     41 bits
    3NRM-RRNS   |    16     |      32         |     48 bits
    C-RRNS      |    16     |      45         |     61 bits
    RS(12,4)    |    16     |      32         |     48 bits

  Chart type: Stacked horizontal bar chart
    - Blue segment: Data bits (16 bits, same for all)
    - Orange segment: Redundancy/overhead bits
    - Total width = codeword length

  Also shows storage efficiency = Data bits / Total codeword bits

Usage:
  python plot_storage_efficiency.py

Output:
  storage_efficiency.png  (saved to sum_result/, auto-opened)
"""

import os
import sys
import subprocess
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

# ─────────────────────────────────────────────────────────────────────────────
# Algorithm Data
# ─────────────────────────────────────────────────────────────────────────────

DATA_BITS = 16  # Original data: 16-bit unsigned integer (0~65535)

ALGORITHMS = [
    {
        'name':       '2NRM-RRNS',
        'data_bits':  16,
        'total_bits': 41,
        # Moduli: {257,256,61,59,55,53} → 9+8+6+6+6+6 = 41 bits
        'moduli':     '{257, 256, 61, 59, 55, 53}',
        'color':      'steelblue',
        'error_corr': 't=2 (2 residues)',
    },
    {
        'name':       '3NRM-RRNS',
        'data_bits':  16,
        'total_bits': 48,
        # Moduli: {64,63,65,31,29,23,19,17,11} → 6+6+7+5+5+5+5+5+4 = 48 bits
        'moduli':     '{64,63,65,31,29,23,19,17,11}',
        'color':      'darkorange',
        'error_corr': 't=3 (3 residues)',
    },
    {
        'name':       'C-RRNS',
        'data_bits':  16,
        'total_bits': 61,
        # Moduli: {64,63,65,67,71,73,79,83,89} → 6+6+7+7+7+7+7+7+7 = 61 bits
        'moduli':     '{64,63,65,67,71,73,79,83,89}',
        'color':      'forestgreen',
        'error_corr': 't=3 (3 residues)',
    },
    {
        'name':       'RS(12,4)',
        'data_bits':  16,
        'total_bits': 48,
        # 4 data symbols × 4-bit + 8 parity symbols × 4-bit = 48 bits
        'moduli':     'GF(2⁴), 4 data + 8 parity symbols',
        'color':      'crimson',
        'error_corr': 't=4 (4 symbols)',
    },
]

# ─────────────────────────────────────────────────────────────────────────────
# Output path
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR     = os.path.dirname(os.path.abspath(__file__))
SUM_RESULT_DIR = os.path.join(SCRIPT_DIR, 'result', 'sum_result')
OUTPUT_FILE    = os.path.join(SUM_RESULT_DIR, 'storage_efficiency.png')
os.makedirs(SUM_RESULT_DIR, exist_ok=True)


def plot_storage_efficiency():
    """Generate storage overhead comparison chart."""

    n = len(ALGORITHMS)
    fig, (ax_bar, ax_eff) = plt.subplots(
        1, 2,
        figsize=(14, 5),
        gridspec_kw={'width_ratios': [3, 1]}
    )

    # ── Left: Codeword length comparison with baseline ───────────────────────
    # Shows: baseline (16 bits) + overhead (extra bits added by ECC)
    # This avoids the misconception that codeword = data + redundancy visually
    y_pos = np.arange(n)
    bar_height = 0.5

    for i, algo in enumerate(ALGORITHMS):
        total    = algo['total_bits']
        overhead = total - DATA_BITS   # Extra bits compared to raw 16-bit storage
        color    = algo['color']

        # Baseline segment: original 16 bits (gray, same for all)
        ax_bar.barh(i, DATA_BITS, height=bar_height,
                    color='lightgray', alpha=0.9, zorder=3,
                    edgecolor='gray', linewidth=0.8)
        # Overhead segment: extra bits added by ECC (algorithm color)
        ax_bar.barh(i, overhead, left=DATA_BITS, height=bar_height,
                    color=color, alpha=0.85, zorder=3,
                    edgecolor='white', linewidth=0.5)

        # Label: baseline
        ax_bar.text(DATA_BITS / 2, i, f'16b\n(original)',
                    ha='center', va='center',
                    fontsize=8.5, color='dimgray', fontweight='bold')
        # Label: overhead
        if overhead > 0:
            ax_bar.text(DATA_BITS + overhead / 2, i,
                        f'+{overhead}b\noverhead',
                        ha='center', va='center',
                        fontsize=8.5, color='white', fontweight='bold')
        # Label: total at right end
        overhead_pct = overhead / DATA_BITS * 100
        ax_bar.text(total + 0.5, i,
                    f'{total}b  (+{overhead_pct:.0f}%)',
                    ha='left', va='center',
                    fontsize=10, color='black', fontweight='bold')

    # Baseline reference line at 16 bits
    ax_bar.axvline(x=DATA_BITS, color='dimgray', linestyle='-', alpha=0.7,
                   linewidth=2, zorder=4)
    ax_bar.text(DATA_BITS, n - 0.05, '  16b\n  baseline',
                ha='left', va='top', fontsize=9, color='dimgray',
                style='italic')

    # Y-axis: algorithm names
    ax_bar.set_yticks(y_pos)
    ax_bar.set_yticklabels([a['name'] for a in ALGORITHMS], fontsize=12)
    ax_bar.set_xlabel('Codeword Length (bits)', fontsize=12)
    ax_bar.set_title(
        'Storage Overhead Comparison\n(vs. raw 16-bit storage, no ECC)',
        fontsize=13, fontweight='bold', pad=12
    )
    ax_bar.set_xlim(0, 78)
    ax_bar.grid(True, axis='x', linestyle='--', alpha=0.3, zorder=0)
    ax_bar.set_axisbelow(True)

    # Legend
    patch_base    = mpatches.Patch(facecolor='lightgray', alpha=0.9,
                                   edgecolor='gray', label='Original 16-bit data')
    patch_overhead = mpatches.Patch(facecolor='steelblue', alpha=0.85,
                                    label='ECC overhead (extra bits)')
    ax_bar.legend(handles=[patch_base, patch_overhead],
                  fontsize=10, loc='lower right')

    # ── Right: Storage efficiency bar chart ──────────────────────────────────
    efficiencies = [a['data_bits'] / a['total_bits'] * 100 for a in ALGORITHMS]
    colors       = [a['color'] for a in ALGORITHMS]

    bars = ax_eff.barh(y_pos, efficiencies, height=bar_height,
                       color=colors, alpha=0.85, zorder=3)

    for i, (eff, algo) in enumerate(zip(efficiencies, ALGORITHMS)):
        ax_eff.text(eff + 0.5, i, f'{eff:.1f}%',
                    ha='left', va='center',
                    fontsize=10, color='black', fontweight='bold')

    ax_eff.set_yticks(y_pos)
    ax_eff.set_yticklabels([])  # Already shown in left chart
    ax_eff.set_xlabel('Storage Efficiency (%)', fontsize=12)
    ax_eff.set_title('Storage\nEfficiency', fontsize=13, fontweight='bold', pad=12)
    ax_eff.set_xlim(0, 55)
    ax_eff.grid(True, axis='x', linestyle='--', alpha=0.3, zorder=0)
    ax_eff.set_axisbelow(True)

    # Add efficiency formula annotation
    ax_eff.text(0.5, -0.12,
                'Efficiency = Data bits / Total codeword bits',
                transform=ax_eff.transAxes,
                ha='center', va='top', fontsize=8, color='gray',
                style='italic')

    plt.tight_layout(pad=2.0)

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


def print_summary():
    """Print a summary table to terminal."""
    print("\n" + "=" * 70)
    print("Storage Efficiency Summary — 16-bit Data (0~65535)")
    print("=" * 70)
    print(f"  {'Algorithm':<14} {'Data':>6} {'Redund':>8} {'Total':>7} "
          f"{'Efficiency':>12} {'Error Corr.':>18}")
    print("  " + "-" * 68)
    for algo in ALGORITHMS:
        data_b = algo['data_bits']
        total  = algo['total_bits']
        redund = total - data_b
        eff    = data_b / total * 100
        print(f"  {algo['name']:<14} {data_b:>6}b {redund:>7}b {total:>6}b "
              f"{eff:>11.1f}% {algo['error_corr']:>18}")
    print("=" * 70)
    print()
    print("  Best storage efficiency: 2NRM-RRNS (39.0%)")
    print("  Best error correction:   C-RRNS / 3NRM-RRNS (t=3)")
    print("  RS(12,4) and 3NRM-RRNS have same codeword length (48 bits)")
    print()


def main():
    print("=" * 60)
    print("Storage Efficiency Comparison Plotter")
    print(f"Output: {OUTPUT_FILE}")
    print("=" * 60)

    print_summary()
    plot_storage_efficiency()
    print("[DONE] Chart generated and opened.")


if __name__ == '__main__':
    main()
