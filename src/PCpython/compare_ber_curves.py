"""
compare_ber_curves.py
FPGA Fault-Tolerant Test System - Multi-Algorithm BER Performance Comparison Plotter

Description:
  Scans all CSV files in the 'sum_result/' subdirectory (relative to this script),
  groups them by test scenario (Error Mode + Burst Length), and generates one
  comparison plot per scenario showing all algorithms on the same axes.

  Each plot contains:
    - Scatter points: raw test data (semi-transparent)
    - Smooth fit line: Savitzky-Golay filtered curve (window=11, polyorder=3)
    - Legend: algorithm names
    - X-axis: Actual BER (%)
    - Y-axis: Decode Success Rate (%)

  Output PNG files are saved to the same 'sum_result/' directory and
  automatically opened with the system default image viewer.

Scenario detection (automatic, from CSV metadata):
  - Error Mode = "Random Single Bit"                    → Scene 1
  - Error Mode contains "Cluster" AND Burst_Length = 5  → Scene 2
  - Error Mode contains "Cluster" AND Burst_Length = 8  → Scene 3

Usage:
  python compare_ber_curves.py
  (No arguments needed. Reads from sum_result/ relative to this script.)
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

# Directory containing all CSV test result files
SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
SUM_RESULT_DIR = os.path.join(SCRIPT_DIR, 'result', 'sum_result')

# Algorithm display order in legend (fixed)
ALGO_ORDER = [
    '2NRM-RRNS',
    '2NRM-RRNS-Serial',
    '3NRM-RRNS',
    'C-RRNS-MLD',
    'C-RRNS-MRC',
    'C-RRNS-CRT',
    'RS',
]

# Per-algorithm visual style: (color, marker, label)
# '2NRM-RRNS' in CSV → displayed as '2NRM-RRNS-Parallel' in legend
ALGO_STYLE = {
    '2NRM-RRNS':        {'color': 'steelblue',     'marker': 'o', 'label': '2NRM-RRNS-Parallel'},
    '2NRM-RRNS-Serial': {'color': 'deepskyblue',   'marker': 'P', 'label': '2NRM-RRNS-Serial'},
    '3NRM-RRNS':        {'color': 'darkorange',    'marker': 's', 'label': '3NRM-RRNS'},
    'C-RRNS-MLD':       {'color': 'forestgreen',   'marker': '^', 'label': 'C-RRNS-MLD'},
    'C-RRNS-MRC':       {'color': 'crimson',       'marker': 'D', 'label': 'C-RRNS-MRC'},
    'C-RRNS-CRT':       {'color': 'mediumpurple',  'marker': 'v', 'label': 'C-RRNS-CRT'},
    'RS':               {'color': 'saddlebrown',   'marker': '*', 'label': 'RS'},
}

# Savitzky-Golay filter parameters
SAVGOL_WINDOW   = 11   # Must be odd, >= polyorder+2
SAVGOL_POLYORDER = 3

# Scene key → (output filename base (no timestamp, no ext), plot title)
# Actual filename = <base>_YYYYMMDD_HHMMSS.png
SCENE_INFO = {
    'random':    ('comparison_random_single_bit',
                  'Decode Success Rate vs Actual BER — Random Single Bit'),
    'cluster5':  ('comparison_cluster_burst_len5',
                  'Decode Success Rate vs Actual BER — Cluster Burst (Length=5)'),
    'cluster8':  ('comparison_cluster_burst_len8',
                  'Decode Success Rate vs Actual BER — Cluster Burst (Length=8)'),
}


# ─────────────────────────────────────────────────────────────────────────────
# CSV Parsing
# ─────────────────────────────────────────────────────────────────────────────

def parse_csv(filepath: str):
    """
    Parse a v3.0 test result CSV file.
    Returns: (metadata dict, list of data-row dicts)
    Metadata keys: 'Algorithm', 'Error Mode', 'Burst_Length', 'Timestamp', ...
    Data-row keys: 'BER_Value_Act', 'Success_Rate', ...
    """
    metadata  = {}
    data_rows = []

    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows   = list(reader)

    # Rows 1-5: metadata key-value pairs
    for row in rows[1:6]:
        if len(row) >= 2 and row[0].strip():
            metadata[row[0].strip()] = row[1].strip()

    # Find header row (contains 'BER_Index')
    header_row_idx = None
    for i, row in enumerate(rows):
        if row and 'BER_Index' in row[0]:
            header_row_idx = i
            break

    if header_row_idx is None:
        return metadata, data_rows   # No data found

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


def classify_scene(metadata: dict) -> str | None:
    """
    Determine which scene a CSV file belongs to.
    Returns: 'random' | 'cluster5' | 'cluster8' | None (unrecognised)

    Note: Burst_Length=1 is treated as the random single-bit scenario
    regardless of the Error Mode string, because a cluster burst of length 1
    is physically equivalent to a random single-bit injection. This handles
    the case where the operator accidentally selects 'Cluster' mode with
    Length=1 instead of 'Random Single Bit'.
    """
    mode       = metadata.get('Error Mode', '').strip()
    burst_str  = metadata.get('Burst_Length', '1').strip()
    try:
        burst = int(burst_str)
    except ValueError:
        burst = 1

    # Burst_Length=1 is always the random single-bit scenario
    if burst == 1:
        return 'random'
    if 'Random' in mode or 'random' in mode:
        return 'random'
    if burst == 5:
        return 'cluster5'
    if burst == 8:
        return 'cluster8'
    return None


# ─────────────────────────────────────────────────────────────────────────────
# Data Loading
# ─────────────────────────────────────────────────────────────────────────────

def load_all_data(data_dir: str):
    """
    Scan data_dir for all .csv files, parse them, and group by scene.

    Returns:
        scenes: dict[scene_key → dict[algo_name → (ber_act_list, success_rate_list)]]
        For duplicate algo in same scene, keep the one from the latest file
        (files are sorted by name, which encodes timestamp).
    """
    # scene_key → { algo_name → (filename, ber_list, sr_list) }
    scenes: dict = defaultdict(dict)

    csv_files = sorted([
        f for f in os.listdir(data_dir) if f.lower().endswith('.csv')
    ])

    print(f"[INFO] Found {len(csv_files)} CSV file(s) in: {data_dir}")

    for fname in csv_files:
        fpath = os.path.join(data_dir, fname)
        try:
            metadata, data_rows = parse_csv(fpath)
        except Exception as e:
            print(f"[WARNING] Failed to parse {fname}: {e}")
            continue

        algo  = metadata.get('Algorithm', '').strip()
        scene = classify_scene(metadata)

        if not algo:
            print(f"[WARNING] No Algorithm field in {fname}, skipping.")
            continue
        if scene is None:
            print(f"[WARNING] Cannot classify scene for {fname} "
                  f"(Mode='{metadata.get('Error Mode','')}', "
                  f"Burst={metadata.get('Burst_Length','')}), skipping.")
            continue

        # Extract X/Y
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
            print(f"[WARNING] No valid data rows in {fname}, skipping.")
            continue

        # Keep latest file for each (scene, algo) pair (files sorted by timestamp)
        existing = scenes[scene].get(algo)
        if existing is None or fname > existing[0]:
            scenes[scene][algo] = (fname, ber_list, sr_list)
            print(f"[INFO]  Scene={scene:9s}  Algo={algo:12s}  "
                  f"Points={len(ber_list):3d}  File={fname}")

    return scenes


# ─────────────────────────────────────────────────────────────────────────────
# Plotting
# ─────────────────────────────────────────────────────────────────────────────

def smooth(y_arr, window=SAVGOL_WINDOW, polyorder=SAVGOL_POLYORDER):
    """
    Apply Savitzky-Golay filter. If the array is too short, return as-is.
    window must be odd and > polyorder.
    """
    n = len(y_arr)
    # Ensure window is odd and does not exceed data length
    w = min(window, n if n % 2 == 1 else n - 1)
    w = max(w, polyorder + 2)
    if w % 2 == 0:
        w -= 1
    if w < polyorder + 2 or n < w:
        return np.array(y_arr)   # Not enough points, return raw
    return savgol_filter(y_arr, window_length=w, polyorder=polyorder)


def delete_old_plots(output_dir: str, base_name: str):
    """
    Delete all existing PNG files matching the base name pattern.
    Pattern: <base_name>*.png  (covers both old fixed names and timestamped names)
    """
    pattern = os.path.join(output_dir, f"{base_name}*.png")
    old_files = glob.glob(pattern)
    for f in old_files:
        try:
            os.remove(f)
            print(f"[INFO] Deleted old plot: {os.path.basename(f)}")
        except Exception as e:
            print(f"[WARNING] Could not delete {f}: {e}")


def plot_scene(scene_key: str, algo_data: dict, output_dir: str, timestamp: str):
    """
    Generate and save one comparison plot for a single scene.
    Output filename includes timestamp: <base>_YYYYMMDD_HHMMSS.png

    algo_data: dict[algo_name → (filename, ber_list, sr_list)]
    timestamp: string in format YYYYMMDD_HHMMSS
    """
    base_name, title = SCENE_INFO[scene_key]

    # Delete old plots with the same base name before generating new one
    delete_old_plots(output_dir, base_name)

    # New filename with timestamp
    out_filename = f"{base_name}_{timestamp}.png"
    out_path = os.path.join(output_dir, out_filename)

    fig, ax = plt.subplots(figsize=(11, 7))

    all_ber_max = 0.0

    # Plot in fixed algorithm order (skip missing ones)
    for algo in ALGO_ORDER:
        if algo not in algo_data:
            continue

        _, ber_list, sr_list = algo_data[algo]
        style = ALGO_STYLE.get(algo, {'color': 'gray', 'marker': 'o', 'label': algo})

        ber_arr = np.array(ber_list)
        sr_arr  = np.array(sr_list)

        # Sort by BER (should already be sorted, but be safe)
        sort_idx = np.argsort(ber_arr)
        ber_arr  = ber_arr[sort_idx]
        sr_arr   = sr_arr[sort_idx]

        all_ber_max = max(all_ber_max, ber_arr.max())

        # Smooth fit line
        sr_smooth = smooth(sr_arr)

        # Plot scatter (raw data, small, semi-transparent)
        ax.scatter(ber_arr, sr_arr,
                   color=style['color'], marker=style['marker'],
                   s=18, alpha=0.35, zorder=2)

        # Plot smooth fit line (solid, thicker)
        ax.plot(ber_arr, sr_smooth,
                color=style['color'], linewidth=2.0,
                label=style['label'], zorder=3)

    # ── Axis formatting ──────────────────────────────────────────────────────
    ax.set_xlabel('Actual BER', fontsize=13)
    ax.set_ylabel('Decode Success Rate', fontsize=13)
    ax.set_title(title, fontsize=14, fontweight='bold', pad=14)

    # X-axis: percentage format, auto tick step
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

    # Y-axis: percentage format, start from 40% to zoom in on effective data range
    ax.set_ylim(0.40, 1.02)
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(
        lambda y, _: f'{y:.0%}'
    ))
    ax.yaxis.set_major_locator(ticker.MultipleLocator(0.05))  # 5% steps for finer grid

    # Grid
    ax.grid(True, linestyle='--', alpha=0.45)
    ax.set_axisbelow(True)

    # Legend: bottom-left corner (curves drop from top-right, leaving bottom-left clear)
    ax.legend(fontsize=11, loc='lower left',
              framealpha=0.85, edgecolor='gray')

    plt.tight_layout()

    # Save
    plt.savefig(out_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"[OK] Saved: {out_path}")
    return out_path


def open_image(path: str):
    """Open an image file with the system default viewer (non-blocking)."""
    try:
        if sys.platform.startswith('win'):
            os.startfile(path)
        elif sys.platform.startswith('darwin'):
            subprocess.Popen(['open', path])
        else:
            subprocess.Popen(['xdg-open', path])
    except Exception as e:
        print(f"[WARNING] Could not open image automatically: {e}")
        print(f"          Please open manually: {path}")


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("Multi-Algorithm BER Comparison Plotter")
    print(f"Data directory: {SUM_RESULT_DIR}")
    print("=" * 60)

    if not os.path.isdir(SUM_RESULT_DIR):
        print(f"[ERROR] Directory not found: {SUM_RESULT_DIR}")
        print("        Please create it and place CSV test result files inside.")
        sys.exit(1)

    # Load and group all data
    scenes = load_all_data(SUM_RESULT_DIR)

    if not scenes:
        print("[ERROR] No valid CSV data found. Nothing to plot.")
        sys.exit(1)

    print()
    generated_files = []

    # Generate timestamp once for all plots in this run (consistent naming)
    run_timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    print(f"[INFO] Run timestamp: {run_timestamp}")
    print()

    # Generate one plot per scene
    for scene_key in ['random', 'cluster5', 'cluster8']:
        if scene_key not in scenes or not scenes[scene_key]:
            print(f"[INFO] Scene '{scene_key}': no data found, skipping.")
            continue

        algo_data = scenes[scene_key]
        print(f"[INFO] Plotting scene '{scene_key}' "
              f"({len(algo_data)} algorithm(s): "
              f"{', '.join(k for k in ALGO_ORDER if k in algo_data)}) ...")

        out_path = plot_scene(scene_key, algo_data, SUM_RESULT_DIR, run_timestamp)
        generated_files.append(out_path)

    print()
    if generated_files:
        print(f"[OK] Generated {len(generated_files)} plot(s).")
        for p in generated_files:
            print(f"     {p}")
        print()
        # Open all generated images
        for p in generated_files:
            open_image(p)
    else:
        print("[WARNING] No plots were generated.")


if __name__ == '__main__':
    main()
