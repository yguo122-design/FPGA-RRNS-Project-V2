import csv, os

def parse_csv(filepath):
    metadata = {}
    data_rows = []
    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)
    for row in rows[1:6]:
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
            row_dict = {headers[i]: row[i].strip() for i in range(min(len(headers), len(row)))}
            data_rows.append(row_dict)
        except:
            continue
    return metadata, data_rows

d = 'src/PCpython/result/sum_result'
files = sorted([f for f in os.listdir(d) if f.endswith('.csv')])

print("=== All 2NRM-RRNS-Serial files ===")
for f in files:
    meta, rows = parse_csv(os.path.join(d, f))
    algo = meta.get('Algorithm', '')
    burst = meta.get('Burst_Length', '')
    mode = meta.get('Error Mode', '')
    if '2NRM-RRNS-Serial' in algo:
        sr_at_10pct = rows[-1].get('Success_Rate', '?') if rows else '?'
        print(f"  {f}: Mode={mode}  Burst={burst}  SR@end={sr_at_10pct}")

print()
print("=== All 2NRM-RRNS (Parallel) files ===")
for f in files:
    meta, rows = parse_csv(os.path.join(d, f))
    algo = meta.get('Algorithm', '')
    burst = meta.get('Burst_Length', '')
    mode = meta.get('Error Mode', '')
    if algo == '2NRM-RRNS':
        sr_at_10pct = rows[-1].get('Success_Rate', '?') if rows else '?'
        print(f"  {f}: Mode={mode}  Burst={burst}  SR@end={sr_at_10pct}")

print()
print("=== Cluster8 comparison ===")
serial_sr = None
parallel_sr = None
for f in files:
    meta, rows = parse_csv(os.path.join(d, f))
    algo = meta.get('Algorithm', '')
    burst = meta.get('Burst_Length', '')
    if burst == '8' and '2NRM' in algo:
        sr_vals = [float(r.get('Success_Rate', 0)) for r in rows if r.get('Success_Rate')]
        ber_vals = [float(r.get('BER_Value_Act', 0)) for r in rows if r.get('BER_Value_Act')]
        print(f"  {algo}: {f}")
        print(f"    BER range: {min(ber_vals):.4f} ~ {max(ber_vals):.4f}")
        print(f"    SR range:  {min(sr_vals):.4f} ~ {max(sr_vals):.4f}")
        # Show SR at BER ~5% and ~10%
        mid = len(rows) // 2
        print(f"    SR at BER~5%:  {rows[mid].get('BER_Value_Act','?')} -> {rows[mid].get('Success_Rate','?')}")
        print(f"    SR at BER~10%: {rows[-1].get('BER_Value_Act','?')} -> {rows[-1].get('Success_Rate','?')}")
