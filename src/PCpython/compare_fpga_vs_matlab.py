"""
compare_fpga_vs_matlab.py
FPGA vs MATLAB BER Performance Comparison Plotter

Description:
  Reads CSV test result files from two separate directories:
    - fpga/   : FPGA hardware test results
    - matlab/ : MATLAB simulation results

  Both directories are located under:
    src/PCpython/result/sum_result/fpga/
    src/PCpython/result/sum_result/matlab/

  For each test scenario (Random Single Bit / Cluster L=5 / Cluster L=8),
  generates one comparison plot showing FPGA and MATLAB curves side by side.

  Visual encoding:
    - Same color per algorithm
    - Solid line  (─────) = FPGA hardware result
    - Dashed line (- - -) = MATLAB simulation result
    - Scatter dots: semi-transparent raw data points

  Output PNG files are saved to:
    src/PCpython/result/sum_result/
  and automatically opened with the system default image viewer.

Usage:
  python compare_fpga_vs_matlab.py
  (No arguments needed.)
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
MATLAB_DIR     = os.path.join(SUM_RESULT_DIR, 'matlab')

# Algorithm display order in legend (fixed)
ALGO_ORDER = [
    '2NRM-RRNS',
    '2NRM-RRNS-Serial',
    '3NRM-RRNS',
    'C-RRNS-MLD',
    'C-RRNS-MRC',
    'RS',
]

# Per-algorithm color and marker
ALGO_STYLE = {
    '2NRM-RRNS':        {'color': 'steelblue',   'marker': 'o', 'label': '2NRM-RRNS-Parallel'},
    '2NRM-RRNS-Serial': {'color': 'deepskyblue', 'marker': 'P', 'label': '2NRM-RRNS-Serial'},
    '3NRM-RRNS':        {'color': 'darkorange',  'marker': 's', 'label': '3NRM-RRNS'},
    'C-RRNS-MLD':       {'color': 'forestgreen', 'marker': '^', 'label': 'C-RRNS-MLD'},
    'C-RRNS-MRC':       {'color': 'crimson',     'marker': 'D', 'label': 'C-RRNS-MRC'},
    'C-RRNS-CRT':       {'color': 'mediumpurple','marker': 'v', 'label': 'C-RRNS-CRT'},
    'RS':               {'color': 'saddlebrown', 'marker': '*', 'label': 'RS'},
}

# Savitzky-Golay filter parameters
SAVGOL_WINDOW    = 11
SAVGOL_POLYORDER = 3

# Scene key → (output filename base, plot title)
SCENE_INFO = {
    'random':    ('fpga_vs_matlab_random_single_bit',
                  'FPGA vs MATLAB — Decode Success Rate vs Actual BER\nRandom Single Bit'),
    'cluster5':  ('fpga_vs_matlab_cluster_burst_len5',
                  'FPGA vs MATLAB — Decode Success Rate vs Actual BER\nCluster Burst (Length=5)'),
    'cluster8':  ('fpga_vs_matlab_cluster_burst_len8',
                  'FPGA vs MATLAB — Decode Success Rate vs Actual BER\nCluster Burst (Length=8)'),
    'cluster12': ('fpga_vs_matlab_cluster_burst_len12',
                  'FPGA vs MATLAB — Decode Success Rate vs Actual BER\nCluster Burst (Length=12)'),
    'cluster15': ('fpga_vs_matlab_cluster_burst_len15',
                  'FPGA vs MATLAB — Decode Success Rate vs Actual BER\nCluster Burst (Length=15)'),
}


# ─────────────────────────────────────────────────────────────────────────────
# CSV Parsing (identical format for both FPGA and MATLAB)
# ─────────────────────────────────────────────────────────────────────────────

def parse_csv(filepath: str):
    """
    Parse a test result CSV file (FPGA or MATLAB format — identical structure).
    Returns: (metadata dict, list of data-row dicts)
    """
    metadata  = {}
    data_rows = []

    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows   = list(reader)

    # Rows 1-6: metadata key-value pairs
    for row in rows[1:7]:
        if len(row) >= 2 and row[0].strip():
            metadata[row[0].strip()] = row[1].strip()

    # Find header row (contains 'BER_Index')
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


def classify_scene(metadata: dict):
    """
    Determine which scene a CSV file belongs to.
    Returns: 'random' | 'cluster5' | 'cluster8' | None
    """
    mode      = metadata.get('Error Mode', '').strip()
    burst_str = metadata.get('Burst_Length', '1').strip()
    try:
        burst = int(burst_str)
    except ValueError:
        burst = 1

    if burst == 1 or 'Random' in mode or 'random' in mode:
        return 'random'
    if burst == 5:
        return 'cluster5'
    if burst == 8:
        return 'cluster8'
    if burst == 12:
        return 'cluster12'
    if burst == 15:
        return 'cluster15'
    return None


# ─────────────────────────────────────────────────────────────────────────────
# Data Loading
# ─────────────────────────────────────────────────────────────────────────────

def load_data_from_dir(data_dir: str, source_label: str):
    """
    Scan data_dir for all .csv files, parse them, and group by scene.

    Returns:
        scenes: dict[scene_key → dict[algo_name → (filename, ber_list, sr_list)]]
        For duplicate algo in same scene, keep the one from the latest file.
    """
    scenes = defaultdict(dict)

    if not os.path.isdir(data_dir):
        print(f"[WARNING] Directory not found: {data_dir}")
        return scenes

    csv_files = sorted([
        f for f in os.listdir(data_dir) if f.lower().endswith('.csv')
    ])

    print(f"[INFO] [{source_label}] Found {len(csv_files)} CSV file(s) in: {data_dir}")

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
            print(f"[WARNING] Cannot classify scene for {fname}, skipping.")
            continue

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

        existing = scenes[scene].get(algo)
        if existing is None or fname > existing[0]:
            scenes[scene][algo] = (fname, ber_list, sr_list)
            print(f"[INFO]  [{source_label}] Scene={scene:9s}  Algo={algo:20s}  "
                  f"Points={len(ber_list):3d}  File={fname}")

    return scenes


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


def delete_old_plots(output_dir: str, base_name: str):
    """Delete existing PNG files matching the base name pattern."""
    pattern   = os.path.join(output_dir, f"{base_name}*.png")
    old_files = glob.glob(pattern)
    for f in old_files:
        try:
            os.remove(f)
            print(f"[INFO] Deleted old plot: {os.path.basename(f)}")
        except Exception as e:
            print(f"[WARNING] Could not delete {f}: {e}")


def plot_scene(scene_key: str,
               fpga_data: dict,
               matlab_data: dict,
               output_dir: str,
               timestamp: str):
    """
    Generate and save one FPGA vs MATLAB comparison plot for a single scene.

    fpga_data / matlab_data: dict[algo_name → (filename, ber_list, sr_list)]
    """
    base_name, title = SCENE_INFO[scene_key]
    delete_old_plots(output_dir, base_name)

    out_filename = f"{base_name}_{timestamp}.png"
    out_path     = os.path.join(output_dir, out_filename)

    fig, ax = plt.subplots(figsize=(12, 7))

    all_ber_max = 0.0
    all_sr_min  = 1.0

    # Collect all algorithms present in either source
    all_algos = set(fpga_data.keys()) | set(matlab_data.keys())

    # Plot in fixed order
    for algo in ALGO_ORDER:
        if algo not in all_algos:
            continue

        style = ALGO_STYLE.get(algo, {'color': 'gray', 'marker': 'o', 'label': algo})
        color  = style['color']
        marker = style['marker']
        label  = style['label']

        # ── FPGA curve (solid line) ──────────────────────────────────────────
        if algo in fpga_data:
            _, ber_list, sr_list = fpga_data[algo]
            ber_arr = np.array(ber_list)
            sr_arr  = np.array(sr_list)
            sort_idx = np.argsort(ber_arr)
            ber_arr  = ber_arr[sort_idx]
            sr_arr   = sr_arr[sort_idx]

            all_ber_max = max(all_ber_max, ber_arr.max())
            all_sr_min  = min(all_sr_min,  sr_arr.min())

            sr_smooth = smooth(sr_arr)

            # Scatter (raw, semi-transparent)
            ax.scatter(ber_arr, sr_arr,
                       color=color, marker=marker,
                       s=18, alpha=0.30, zorder=2)
            # Solid fit line
            ax.plot(ber_arr, sr_smooth,
                    color=color, linewidth=2.2, linestyle='-',
                    label=f'{label} (FPGA)', zorder=3)

        # ── MATLAB curve (dashed line) ───────────────────────────────────────
        if algo in matlab_data:
            _, ber_list, sr_list = matlab_data[algo]
            ber_arr = np.array(ber_list)
            sr_arr  = np.array(sr_list)
            sort_idx = np.argsort(ber_arr)
            ber_arr  = ber_arr[sort_idx]
            sr_arr   = sr_arr[sort_idx]

            all_ber_max = max(all_ber_max, ber_arr.max())
            all_sr_min  = min(all_sr_min,  sr_arr.min())

            sr_smooth = smooth(sr_arr)

            # Scatter (raw, semi-transparent, smaller)
            ax.scatter(ber_arr, sr_arr,
                       color=color, marker=marker,
                       s=12, alpha=0.20, zorder=2)
            # Dashed fit line
            ax.plot(ber_arr, sr_smooth,
                    color=color, linewidth=1.8, linestyle='--',
                    label=f'{label} (MATLAB)', zorder=3)

    # ── Axis formatting ──────────────────────────────────────────────────────
    ax.set_xlabel('Actual BER', fontsize=13)
    ax.set_ylabel('Decode Success Rate', fontsize=13)
    ax.set_title(title, fontsize=13, fontweight='bold', pad=14)

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
    ax.grid(True, linestyle='--', alpha=0.40)
    ax.set_axisbelow(True)

    # Legend: two columns (FPGA | MATLAB), placed at lower left
    ax.legend(fontsize=10, loc='lower left',
              framealpha=0.88, edgecolor='gray',
              ncol=2,
              title='─── FPGA   - - - MATLAB',
              title_fontsize=9)

    plt.tight_layout()
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
    print("=" * 65)
    print("FPGA vs MATLAB BER Comparison Plotter")
    print(f"FPGA   data: {FPGA_DIR}")
    print(f"MATLAB data: {MATLAB_DIR}")
    print(f"Output dir : {SUM_RESULT_DIR}")
    print("=" * 65)

    # Load FPGA data
    print("\n[FPGA data]")
    fpga_scenes = load_data_from_dir(FPGA_DIR, 'FPGA')

    # Load MATLAB data
    print("\n[MATLAB data]")
    matlab_scenes = load_data_from_dir(MATLAB_DIR, 'MATLAB')

    if not fpga_scenes and not matlab_scenes:
        print("[ERROR] No valid CSV data found in either directory.")
        sys.exit(1)

    # Collect all scene keys present in either source
    all_scene_keys = set(fpga_scenes.keys()) | set(matlab_scenes.keys())

    if not all_scene_keys:
        print("[ERROR] No valid scenes found. Nothing to plot.")
        sys.exit(1)

    print()
    generated_files = []
    run_timestamp   = datetime.now().strftime('%Y%m%d_%H%M%S')
    print(f"[INFO] Run timestamp: {run_timestamp}\n")

    for scene_key in ['random', 'cluster5', 'cluster8', 'cluster12', 'cluster15']:
        if scene_key not in all_scene_keys:
            print(f"[INFO] Scene '{scene_key}': no data in either source, skipping.")
            continue

        fpga_data   = fpga_scenes.get(scene_key, {})
        matlab_data = matlab_scenes.get(scene_key, {})

        fpga_algos   = [k for k in ALGO_ORDER if k in fpga_data]
        matlab_algos = [k for k in ALGO_ORDER if k in matlab_data]

        print(f"[INFO] Plotting scene '{scene_key}':")
        print(f"       FPGA   algorithms: {fpga_algos}")
        print(f"       MATLAB algorithms: {matlab_algos}")

        out_path = plot_scene(scene_key, fpga_data, matlab_data,
                              SUM_RESULT_DIR, run_timestamp)
        generated_files.append(out_path)

    print()
    if generated_files:
        print(f"[OK] Generated {len(generated_files)} comparison plot(s):")
        for p in generated_files:
            print(f"     {p}")
        print()
        for p in generated_files:
            open_image(p)
    else:
        print("[WARNING] No plots were generated.")


if __name__ == '__main__':
    main()
