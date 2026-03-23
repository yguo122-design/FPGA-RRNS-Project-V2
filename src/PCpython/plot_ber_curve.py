"""
plot_ber_curve.py
FPGA Fault-Tolerant Test System - BER Performance Curve Plotter

Usage:
  python plot_ber_curve.py <csv_file>
  python plot_ber_curve.py test_results_20260321_135225.csv
  python plot_ber_curve.py test_results_20260321_135225.csv --save

Description:
  Reads a test result CSV file (v2.1 format from py_controller_main.py) and
  plots the BER performance curve:
    X-axis: BER_Value_Act (actual injected BER, computed from Flip_Count)
    Y-axis: Success_Rate  (decoding success rate = Success / Total)
    Title:  Algorithm + Mode (+ Burst Length if Cluster mode)

CSV Format Expected (v2.1):
  Row 1: "Test Report ..."
  Row 2: Timestamp
  Row 3: Algorithm name
  Row 4: Error Mode
  Row 5: Total Points
  Row 6: (empty)
  Row 7: Column headers
  Row 8+: Data rows
"""

import csv
import sys
import os
import argparse
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker


def parse_csv(filepath: str):
    """
    Parse the v2.1 test result CSV file.
    Returns: (metadata dict, list of data rows as dicts)
    """
    metadata = {}
    data_rows = []

    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    # Parse metadata from header rows
    # Row 0: "Test Report ..."
    # Row 1: ["Timestamp", value]
    # Row 2: ["Algorithm", value]
    # Row 3: ["Error Mode", value]
    # Row 4: ["Total Points", value]
    # Row 5: (empty)
    # Row 6: column headers
    # Row 7+: data

    for row in rows[1:6]:
        if len(row) >= 2 and row[0].strip():
            metadata[row[0].strip()] = row[1].strip()

    # Find the header row (contains "BER_Index")
    header_row_idx = None
    for i, row in enumerate(rows):
        if row and 'BER_Index' in row[0]:
            header_row_idx = i
            break

    if header_row_idx is None:
        raise ValueError("Could not find column header row with 'BER_Index'")

    headers = [h.strip() for h in rows[header_row_idx]]

    # Parse data rows
    for row in rows[header_row_idx + 1:]:
        if not row or not row[0].strip():
            continue
        try:
            row_dict = {}
            for i, h in enumerate(headers):
                if i < len(row):
                    row_dict[h] = row[i].strip()
            data_rows.append(row_dict)
        except Exception:
            continue

    return metadata, data_rows


def build_title(metadata: dict) -> str:
    """
    Build the plot title from metadata.
    Format: "<Algorithm> | <Mode>" or "<Algorithm> | Cluster (Burst) | Length=<N>"
    """
    algo = metadata.get('Algorithm', 'Unknown Algorithm')
    mode = metadata.get('Error Mode', 'Unknown Mode')

    # Try to extract burst length from mode string or metadata
    # Mode string examples: "Random Single Bit", "Cluster (Burst)"
    if 'Cluster' in mode or 'Burst' in mode or 'cluster' in mode:
        # Try to find burst length in metadata
        burst_len = metadata.get('Burst_Length', metadata.get('Burst Length', None))
        if burst_len:
            title = f"{algo}  |  {mode}  |  Burst Length = {burst_len}"
        else:
            title = f"{algo}  |  {mode}"
    else:
        title = f"{algo}  |  {mode}"

    return title


def plot_ber_curve(filepath: str, save: bool = False):
    """
    Main plotting function.
    """
    print(f"[INFO] Reading: {filepath}")

    # Parse CSV
    metadata, data_rows = parse_csv(filepath)

    if not data_rows:
        print("[ERROR] No data rows found in CSV file.")
        return

    print(f"[INFO] Algorithm: {metadata.get('Algorithm', 'N/A')}")
    print(f"[INFO] Error Mode: {metadata.get('Error Mode', 'N/A')}")
    print(f"[INFO] Data points: {len(data_rows)}")

    # Extract X and Y data
    ber_act_list    = []
    success_rate_list = []

    for row in data_rows:
        try:
            ber_act      = float(row.get('BER_Value_Act', 0))
            success_rate = float(row.get('Success_Rate', 0))
            ber_act_list.append(ber_act)
            success_rate_list.append(success_rate)
        except (ValueError, KeyError):
            continue

    if not ber_act_list:
        print("[ERROR] Could not extract BER_Value_Act or Success_Rate columns.")
        print(f"[INFO] Available columns: {list(data_rows[0].keys()) if data_rows else 'none'}")
        return

    # Build title
    title = build_title(metadata)

    # ─────────────────────────────────────────────────────────────────────────
    # Plot
    # ─────────────────────────────────────────────────────────────────────────
    fig, ax = plt.subplots(figsize=(10, 6))

    # Main curve
    ax.plot(ber_act_list, success_rate_list,
            marker='o', markersize=4, linewidth=1.5,
            color='steelblue', label='Success Rate')

    # Axis labels
    ax.set_xlabel('Actual BER (%)', fontsize=12)
    ax.set_ylabel('Success Rate', fontsize=12)

    # Title
    ax.set_title(title, fontsize=13, fontweight='bold', pad=12)

    # X-axis: display as percentage, auto-select tick interval based on data range
    ax.xaxis.set_major_formatter(ticker.FuncFormatter(
        lambda x, _: f'{x * 100:.4g}%'   # e.g. 0.005→0.5%, 0.01→1%, 0.1→10%
    ))
    x_max = max(ber_act_list) if ber_act_list else 0.1
    # Choose tick interval: aim for ~5-10 ticks across the range
    if x_max <= 0.02:
        tick_step = 0.005   # 0.5% steps for range ≤ 2%
    elif x_max <= 0.05:
        tick_step = 0.01    # 1% steps for range ≤ 5%
    else:
        tick_step = 0.01    # 1% steps for range > 5%
    ax.xaxis.set_major_locator(ticker.MultipleLocator(tick_step))
    ax.set_xlim(left=0, right=x_max * 1.05)  # X-axis starts from 0, right margin 5%

    # Y-axis: 0 to 1, show as percentage
    ax.set_ylim(-0.02, 1.05)
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(
        lambda y, _: f'{y:.1%}'
    ))

    # Grid
    ax.grid(True, linestyle='--', alpha=0.5)
    ax.set_axisbelow(True)

    # Legend
    ax.legend(fontsize=10)

    # Timestamp annotation (bottom right) — temporarily disabled
    # timestamp = metadata.get('Timestamp', '')
    # if timestamp:
    #     ax.annotate(f'Test: {timestamp}',
    #                 xy=(0.99, 0.02), xycoords='axes fraction',
    #                 ha='right', va='bottom', fontsize=8, color='gray')

    plt.tight_layout()

    # Save or show
    if save:
        base = os.path.splitext(filepath)[0]
        out_path = f"{base}_curve.png"
        plt.savefig(out_path, dpi=150, bbox_inches='tight')
        print(f"[OK] Plot saved to: {out_path}")
    else:
        plt.show()

    plt.close()


def main():
    parser = argparse.ArgumentParser(
        description='Plot BER performance curve from test result CSV (v2.1 format)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python plot_ber_curve.py test_results_20260321_135225.csv\n"
            "  python plot_ber_curve.py test_results_20260321_135225.csv --save\n"
        )
    )
    parser.add_argument(
        'csv_file',
        type=str,
        help='Path to the test result CSV file (v2.1 format)'
    )
    parser.add_argument(
        '--save',
        action='store_true',
        default=False,
        help='Save the plot as PNG instead of displaying it'
    )
    args = parser.parse_args()

    if not os.path.isfile(args.csv_file):
        print(f"[ERROR] File not found: {args.csv_file}")
        sys.exit(1)

    plot_ber_curve(args.csv_file, save=args.save)


if __name__ == '__main__':
    main()
