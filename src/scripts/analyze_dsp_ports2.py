"""
Analyze CEALUMODE and CECARRYIN functional usage in DSP48E1 unisim.
"""
with open(r'D:\Xilinx\Vivado\2023.2\data\verilog\src\unisims\DSP48E1.v', 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

lines = content.split('\n')

print("=== All lines referencing CEALUMODE or CECARRYIN ===")
print("(excluding $setuphold timing checks)")
print()
for i, line in enumerate(lines):
    lo = line.lower()
    if ('cealumode' in lo or 'cecarryin' in lo) and 'setuphold' not in lo:
        start = max(0, i - 1)
        end = min(len(lines), i + 2)
        for j in range(start, end):
            print(f"Line {j+1}: {lines[j].rstrip()}")
        print("---")

print()
print("=== Default value when port is unconnected (Verilog default) ===")
print("In Verilog, unconnected input ports default to 'z' (high-impedance).")
print("For synthesis, Vivado treats unconnected CE inputs as 1'b1 (always enabled).")
print("For simulation, 'z' propagates as 'x' through the CE logic.")
print()

# Also check what RSTALUMODE does (we connect it, CEALUMODE we don't)
print("=== Checking RSTALUMODE vs CEALUMODE relationship ===")
for i, line in enumerate(lines):
    if 'rstalumode' in line.lower() and 'setuphold' not in line.lower():
        print(f"Line {i+1}: {line.rstrip()}")
