"""
plot_cluster_length_impact.py
FPGA Fault-Tolerant Test System - Cluster Length Impact Plotter

Description:
  For each algorithm, generates one plot showing how Cluster Burst Length
  affects the Decode Success Rate vs Actual BER curve.
  Each line in the plot represents a different cluster length.

  This is the "transpose" of compare_ber_curves.py:
    compare_ber_curves.py  : same length, different algorithms on one plot
    plot_cluster_length_impact.py : same algorithm, different lengths on one plot

  Data source: CSV files in src/PCpython/result/sum_result/fpga/
  Only Cluster (Burst) mode files are used (L=1 Random is excluded).

  Algorithms and lengths to plot:
    2NRM-RRNS          : L = 5, 8, 9, 10, 12, 15
    2NRM-RRNS-Serial   : L = 5, 6, 7, 8, 12, 15
    3NRM-RRNS          : L = 5, 8, 10, 11, 12, 15
    RS                 : L = 5, 8, 12, 13, 14, 15

  Output: one PNG per algorithm, saved to sum_result/ directory.

Usage:
  python plot_cluster_length_impact.py
"""

import csv
import os
import sys
import subprocess
import glob
from collections import defaultdict
from datetime import datetime

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from scipy.signal import savgol_filter

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR     = os.path.dirname(os.path.abspath(__file__))
SUM_RESULT_DIR = os.path.join(SCRIPT_DIR, 'result', 'sum_result')
FPGA_DIR       = os.path.join(SUM_RESULT_DIR, 'fpga')

# Algorithms to plot and which lengths to include
ALGO_LENGTHS = {
    '2NRM-RRNS':        [7, 8, 9, 10, 12, 15],
    '2NRM-RRNS-Serial': [5, 6, 7, 8, 12, 15],
    '3NRM-RRNS':        [5, 8, 10, 11, 12, 15],
    'C-RRNS-MLD':       [5, 8, 12, 13, 14, 15],
    'RS':               [5, 8, 12, 13, 14, 15],
}

# Algorithm display names (for plot title)
ALGO_DISPLAY = {
    '2NRM-RRNS':        '2NRM-RRNS-Parallel',
    '2NRM-RRNS-Serial': '2NRM-RRNS-Serial',
    '3NRM-RRNS':        '3NRM-RRNS',
    'C-RRNS-MLD':       'C-RRNS-MLD',
    'RS':               'RS(12,4)',
}

# Color palette for different cluster lengths (up to 8 lengths)
# Using a colormap for automatic color assignment
LENGTH_COLORS = [
    '#1f77b4',  # blue
    '#ff7f0e',  # orange
    '#2ca02c',  # green
    '#d62728',  # red
    '#9467bd',  # purple
    '#8c564b',  # brown
    '#e377c2',  # pink
    '#7f7f7f',  # gray
]

# Savitzky-Golay filter parameters
SAVGOL_WINDOW    = 11
SAVGOL_POLYORDER = 3


# ─────────────────────────────────────────────────────────────────────────────
# CSV Parsing
# ─────────────────────────────────────────────────────────────────────────────

def parse_csv(filepath):
    """Parse a test result CSV. Returns (metadata dict, data_rows list)."""
    metadata  = {}
    data_rows = []

    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows   = list(reader)

    for row in rows[1:7]:
        if len(row) >= 2 and row[0].strip():
            metadata[row[0].strip()] = row[1].strip()

    header_row_idx = None
    for i, row in enumerate(rows):
        if row and 'BER_Index' in row[0]:
            header_row_idx = i
            break

    if header_row_idx is None:
        return metadata, data_rows

    headers = [h.strip() for h in rows[header_row_idx]]

    for row in rows[header_row_idx + 1:]:
        if not row or not row[0].strip():
            continue
        try:
            row_dict = {headers[i]: row[i].strip()
                        for i in range(min(len(headers), len(row)))}
            data_rows.append(row_dict)
        except Exception:
            continue

    return metadata, data_rows


# ─────────────────────────────────────────────────────────────────────────────
# Data Loading
# ─────────────────────────────────────────────────────────────────────────────

def load_all_data(data_dir):
    """
    Scan data_dir for all CSV files.
    Returns: dict[algo_name → dict[burst_len → (filename, ber_list, sr_list)]]
    For duplicate (algo, burst_len), keep the latest file.
    """
    result = defaultdict(dict)

    if not os.path.isdir(data_dir):
        print(f"[WARNING] Directory not found: {data_dir}")
        return result

    csv_files = sorted([f for f in os.listdir(data_dir) if f.lower().endswith('.csv')])
    print(f"[INFO] Found {len(csv_files)} CSV file(s) in: {data_dir}")

    for fname in csv_files:
        fpath = os.path.join(data_dir, fname)
        try:
            metadata, data_rows = parse_csv(fpath)
        except Exception as e:
            print(f"[WARNING] Failed to parse {fname}: {e}")
            continue

        algo  = metadata.get('Algorithm', '').strip()
        mode  = metadata.get('Error Mode', '').strip()
        burst_str = metadata.get('Burst_Length', '0').strip()

        if not algo:
            continue

        # Only include Cluster (Burst) mode, skip Random Single Bit
        if 'Random' in mode or 'random' in mode:
            continue
        if 'Cluster' not in mode and 'cluster' not in mode:
            continue

        try:
            burst = int(burst_str)
        except ValueError:
            continue

        if burst <= 1:
            continue

        # Extract BER and SR data
        ber_list = []
        sr_list  = []
        for row in data_rows:
            try:
                ber = float(row.get('BER_Value_Act', 0))
                sr  = float(row.get('Success_Rate',  0))
                ber_list.append(ber)
                sr_list.append(sr)
            except (ValueError, KeyError):
                continue

        if not ber_list:
            continue

        # Keep latest file for each (algo, burst) pair
        existing = result[algo].get(burst)
        if existing is None or fname > existing[0]:
            result[algo][burst] = (fname, ber_list, sr_list)
            print(f"[INFO]  Algo={algo:20s}  L={burst:2d}  Points={len(ber_list):3d}  File={fname}")

    return result


# ─────────────────────────────────────────────────────────────────────────────
# Plotting
# ─────────────────────────────────────────────────────────────────────────────

def smooth(y_arr, window=SAVGOL_WINDOW, polyorder=SAVGOL_POLYORDER):
    """Apply Savitzky-Golay filter. Returns raw array if too short."""
    n = len(y_arr)
    w = min(window, n if n % 2 == 1 else n - 1)
    w = max(w, polyorder + 2)
    if w % 2 == 0:
        w -= 1
    if w < polyorder + 2 or n < w:
        return np.array(y_arr)
    return savgol_filter(y_arr, window_length=w, polyorder=polyorder)


def delete_old_plots(output_dir, base_name):
    """Delete existing PNG files matching the base name pattern."""
    pattern   = os.path.join(output_dir, f"{base_name}*.png")
    old_files = glob.glob(pattern)
    for f in old_files:
        try:
            os.remove(f)
            print(f"[INFO] Deleted old plot: {os.path.basename(f)}")
        except Exception:
            pass


def plot_algo(algo_name, length_data, output_dir, timestamp):
    """
    Generate one plot for a single algorithm showing all cluster lengths.

    length_data: dict[burst_len → (filename, ber_list, sr_list)]
    """
    display_name = ALGO_DISPLAY.get(algo_name, algo_name)
    base_name    = f"cluster_length_impact_{algo_name.replace('-', '_').replace(' ', '_')}"
    delete_old_plots(output_dir, base_name)

    out_filename = f"{base_name}_{timestamp}.png"
    out_path     = os.path.join(output_dir, out_filename)

    fig, ax = plt.subplots(figsize=(11, 7))

    all_ber_max = 0.0
    all_sr_min  = 1.0

    # Get the lengths to plot for this algorithm (in order)
    target_lengths = ALGO_LENGTHS.get(algo_name, [])
    available_lengths = sorted([L for L in target_lengths if L in length_data])

    if not available_lengths:
        print(f"[WARNING] No data found for {algo_name}, skipping.")
        plt.close()
        return None

    for idx, burst_len in enumerate(available_lengths):
        _, ber_list, sr_list = length_data[burst_len]
        color = LENGTH_COLORS[idx % len(LENGTH_COLORS)]

        ber_arr  = np.array(ber_list)
        sr_arr   = np.array(sr_list)
        sort_idx = np.argsort(ber_arr)
        ber_arr  = ber_arr[sort_idx]
        sr_arr   = sr_arr[sort_idx]

        all_ber_max = max(all_ber_max, ber_arr.max())
        all_sr_min  = min(all_sr_min,  sr_arr.min())

        sr_smooth = smooth(sr_arr)

        # Scatter (raw data, semi-transparent)
        ax.scatter(ber_arr, sr_arr,
                   color=color, marker='o',
                   s=15, alpha=0.30, zorder=2)

        # Smooth fit line
        ax.plot(ber_arr, sr_smooth,
                color=color, linewidth=2.0,
                label=f'Cluster L={burst_len}', zorder=3)

    # ── Axis formatting ──────────────────────────────────────────────────────
    ax.set_xlabel('Actual BER', fontsize=13)
    ax.set_ylabel('Decode Success Rate', fontsize=13)
    ax.set_title(
        f'{display_name} — Decode Success Rate vs Actual BER\n'
        f'Effect of Cluster Burst Length on Error Correction Performance',
        fontsize=13, fontweight='bold', pad=14
    )

    # X-axis
    ax.xaxis.set_major_formatter(ticker.FuncFormatter(
        lambda x, _: f'{x * 100:.4g}%'
    ))
    x_max = all_ber_max if all_ber_max > 0 else 0.1
    if x_max <= 0.02:
        tick_step = 0.002
    elif x_max <= 0.05:
        tick_step = 0.005
    else:
        tick_step = 0.01
    ax.xaxis.set_major_locator(ticker.MultipleLocator(tick_step))
    ax.set_xlim(left=0, right=x_max * 1.05)

    # Y-axis: auto-adapt lower limit
    y_margin = 0.05
    y_min = max(0.0, all_sr_min - y_margin)
    y_min = max(0.0, np.floor(y_min / 0.05) * 0.05)
    ax.set_ylim(y_min, 1.02)
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(
        lambda y, _: f'{y:.0%}'
    ))
    ax.yaxis.set_major_locator(ticker.MultipleLocator(0.05))

    # Grid
    ax.grid(True, linestyle='--', alpha=0.45)
    ax.set_axisbelow(True)

    # Legend: lower left (curves drop from top-right)
    ax.legend(fontsize=11, loc='lower left',
              framealpha=0.85, edgecolor='gray',
              title=f'Cluster Burst Length\n(shorter = easier to correct)',
              title_fontsize=9)

    plt.tight_layout()
    plt.savefig(out_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"[OK] Saved: {out_path}")
    return out_path


def open_image(path):
    """Open an image file with the system default viewer (non-blocking)."""
    try:
        if sys.platform.startswith('win'):
            os.startfile(path)
        elif sys.platform.startswith('darwin'):
            subprocess.Popen(['open', path])
        else:
            subprocess.Popen(['xdg-open', path])
    except Exception as e:
        print(f"[WARNING] Could not open image: {e}")


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("=" * 65)
    print("Cluster Length Impact Plotter")
    print(f"Data directory: {FPGA_DIR}")
    print(f"Output dir    : {SUM_RESULT_DIR}")
    print("=" * 65)
    print()

    # Load all data
    all_data = load_all_data(FPGA_DIR)

    if not all_data:
        print("[ERROR] No valid CSV data found.")
        sys.exit(1)

    print()
    run_timestamp   = datetime.now().strftime('%Y%m%d_%H%M%S')
    generated_files = []

    for algo_name in ALGO_LENGTHS.keys():
        if algo_name not in all_data:
            print(f"[INFO] No data found for {algo_name}, skipping.")
            continue

        length_data = all_data[algo_name]
        target      = ALGO_LENGTHS[algo_name]
        available   = sorted([L for L in target if L in length_data])
        missing     = [L for L in target if L not in length_data]

        print(f"[INFO] Plotting {algo_name}:")
        print(f"       Available lengths: {available}")
        if missing:
            print(f"       Missing lengths:   {missing}")

        out_path = plot_algo(algo_name, length_data, SUM_RESULT_DIR, run_timestamp)
        if out_path:
            generated_files.append(out_path)

    print()
    if generated_files:
        print(f"[OK] Generated {len(generated_files)} plot(s):")
        for p in generated_files:
            print(f"     {p}")
        print()
        for p in generated_files:
            open_image(p)
    else:
        print("[WARNING] No plots were generated.")


if __name__ == '__main__':
    main()
