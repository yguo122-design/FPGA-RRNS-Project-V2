"""
Analyze DSP48E1 port connections in u_dsp_1c and u_dsp_1e instantiations.
Identifies missing ports that cause [Synth 8-7023] warning.
"""
import re

# Extract u_dsp_1c port list from the source file
with open(r"d:\FPGAproject\FPGA-RRNS-Project-V2\src\algo_wrapper\decoder_2nrm.v", "r", encoding="utf-8") as f:
    content = f.read()

# Find u_dsp_1c instantiation block
dsp1c_match = re.search(r'\) u_dsp_1c \((.*?)\);', content, re.DOTALL)
dsp1e_match = re.search(r'\) u_dsp_1e \((.*?)\);', content, re.DOTALL)

def extract_ports(block):
    return re.findall(r'\.([A-Z][A-Z0-9_]*)\s*\(', block)

dsp1c_ports = extract_ports(dsp1c_match.group(1)) if dsp1c_match else []
dsp1e_ports = extract_ports(dsp1e_match.group(1)) if dsp1e_match else []

# Complete DSP48E1 port list (Xilinx UG953, 7-series)
# Inputs: 37 ports
dsp48e1_inputs = [
    'CLK',
    # Data inputs
    'A', 'B', 'C', 'D', 'CARRYIN',
    # Cascade inputs
    'ACIN', 'BCIN', 'PCIN', 'CARRYCASCIN', 'MULTSIGNIN',
    # Control inputs
    'OPMODE', 'ALUMODE', 'INMODE', 'CARRYINSEL',
    # Clock enables (11 ports)
    'CEA1', 'CEA2', 'CEB1', 'CEB2', 'CEC', 'CED', 'CEM', 'CEP',
    'CECTRL', 'CEINMODE', 'CEAD',
    # Synchronous resets (10 ports)
    'RSTA', 'RSTB', 'RSTC', 'RSTD', 'RSTM', 'RSTP',
    'RSTALLCARRYIN', 'RSTALUMODE', 'RSTCTRL', 'RSTINMODE',
]
# Outputs: 12 ports
dsp48e1_outputs = [
    'P',
    'ACOUT', 'BCOUT', 'PCOUT', 'CARRYCASCOUT', 'MULTSIGNOUT',
    'CARRYOUT',
    'OVERFLOW', 'UNDERFLOW', 'PATTERNDETECT', 'PATTERNBDETECT',
]
all_dsp48e1_ports = dsp48e1_inputs + dsp48e1_outputs

print("=" * 60)
print("DSP48E1 Port Analysis")
print("=" * 60)
print(f"Total DSP48E1 ports (UG953): {len(all_dsp48e1_ports)}")
print(f"  Inputs:  {len(dsp48e1_inputs)}")
print(f"  Outputs: {len(dsp48e1_outputs)}")
print()

print(f"u_dsp_1c connected ports: {len(dsp1c_ports)}")
print(f"u_dsp_1e connected ports: {len(dsp1e_ports)}")
print()

missing_1c = [p for p in all_dsp48e1_ports if p not in dsp1c_ports]
missing_1e = [p for p in all_dsp48e1_ports if p not in dsp1e_ports]
extra_1c   = [p for p in dsp1c_ports if p not in all_dsp48e1_ports]
extra_1e   = [p for p in dsp1e_ports if p not in all_dsp48e1_ports]

print(f"Missing in u_dsp_1c ({len(missing_1c)} ports): {missing_1c}")
print(f"Missing in u_dsp_1e ({len(missing_1e)} ports): {missing_1e}")
print(f"Extra in u_dsp_1c (not in UG953 list): {extra_1c}")
print(f"Extra in u_dsp_1e (not in UG953 list): {extra_1e}")
print()

# Show ports in 1e but not in 1c (the ones causing the warning)
in_1e_not_1c = [p for p in dsp1e_ports if p not in dsp1c_ports]
in_1c_not_1e = [p for p in dsp1c_ports if p not in dsp1e_ports]
print(f"Ports in u_dsp_1e but NOT in u_dsp_1c: {in_1e_not_1c}")
print(f"Ports in u_dsp_1c but NOT in u_dsp_1e: {in_1c_not_1e}")
print()

# Determine if Vivado's DSP48E1 model has more ports than UG953 lists
# The warning says 49 declared, 47 given -> 2 missing
# If our UG953 list has 49 ports and we find 47 in u_dsp_1c, the missing 2 are:
print("=" * 60)
print("Conclusion:")
print(f"  Vivado DSP48E1 model: 49 ports (per warning message)")
print(f"  u_dsp_1c connections: 47 ports (per warning message)")
print(f"  Our UG953 port list:  {len(all_dsp48e1_ports)} ports")
print(f"  Ports found in u_dsp_1c code: {len(dsp1c_ports)}")
if len(all_dsp48e1_ports) == 49 and len(dsp1c_ports) == 47:
    print(f"  => Missing 2 ports confirmed: {missing_1c}")
elif len(all_dsp48e1_ports) != 49:
    print(f"  => Our UG953 list has {len(all_dsp48e1_ports)} ports, not 49.")
    print(f"     Vivado may include additional ports not in UG953.")
    print(f"     The 2 missing ports are likely: {missing_1c} + 2 Vivado-internal ports")
