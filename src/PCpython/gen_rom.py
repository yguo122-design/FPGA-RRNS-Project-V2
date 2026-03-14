# gen_rom.py
# FPGA Multi-Algorithm Fault-Tolerant Test System - ROM Data Generator
# Generates threshold_table.coe and error_lut.coe
# 
# LOGIC CONSTRAINTS APPLIED:
# 1. Burst Length (L) is strictly constrained to 1 ~ 15.
# 2. L=16 is treated as ILLEGAL and explicitly zeroed in the ROM to prevent undefined behavior.
# 3. Address mapping aligns perfectly with Verilog {algo_id, len_idx, offset} logic.

import math
import os

# ================= Configuration Parameters =================
# Algorithm Definitions: ID, Valid Bit Width (W_valid)
# IDs must match the Verilog 'algo_id' input encoding
ALGORITHMS = {
    '2NRM':    {'w_valid': 41, 'id': 0},
    '3NRM':    {'w_valid': 48, 'id': 1},
    'C-RRNS':  {'w_valid': 61, 'id': 2},
    'RS':      {'w_valid': 48, 'id': 3}
}

# BER Test Points: 91 points, from 1% (0.01) to 10% (0.10), step 0.001
BER_POINTS = 91
BER_START = 0.01
BER_STEP = 0.001

# Burst Length Range: 1 ~ 15 (Strictly enforced per Doc v1.61)
# Python range(1, 16) generates [1, 2, ..., 15]
BURST_LENGTHS = list(range(1, 16)) 
MAX_BURST_LEN = 15
NUM_BURST_STEPS = MAX_BURST_LEN  # Should be 15

# ================= Utility Functions =================
def calculate_threshold(target_ber: float, burst_len: int, w_valid: int) -> int:
    """
    Calculate LFSR Threshold Integer
    Formula: Threshold_Int = round( (BER_target * W_valid / L) * (2^32 - 1) )
    """
    if burst_len <= 0:
        return 0
    
    # Probability of triggering an error event per burst window
    # Logic: We want 'burst_len' bits to have a total expected error count of target_ber * w_valid?
    # Or more commonly: P(bit error) = target_ber. 
    # The formula provided in prompt implies a specific trigger mechanism for the LFSR.
    # Sticking to the provided formula:
    p_trigger = (target_ber * w_valid) / burst_len
    
    # Map probability to 32-bit integer space
    threshold = round(p_trigger * (2**32 - 1))
    
    # Clamp to 32-bit range [0, 0xFFFFFFFF]
    return max(0, min(threshold, 0xFFFFFFFF))

def generate_error_pattern(length: int, start_pos: int, w_valid: int) -> int:
    """
    Generate a continuous error mask of 'length' bits starting at 'start_pos'.
    Ensures errors are strictly within the [0, w_valid-1] range.
    Returns 0 if the pattern exceeds valid bounds.
    """
    # Check if the entire burst fits within the valid data width
    if start_pos + length > w_valid:
        return 0
    
    mask = 0
    for i in range(length):
        pos = start_pos + i
        # Double check individual bit position
        if 0 <= pos < w_valid:
            mask |= (1 << pos)
        else:
            return 0 # Safety fallback
    return mask

# Output directory: src/ROM/ relative to this script's location
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROM_OUTPUT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "ROM"))

def write_coe_file(filename: str, data: list, radix: int = 16, width: int = 8):
    """
    Write data to .coe file compliant with Xilinx Vivado standards.
    Output path: src/ROM/<filename>
    """
    os.makedirs(ROM_OUTPUT_DIR, exist_ok=True)
    filepath = os.path.join(ROM_OUTPUT_DIR, filename)
    with open(filepath, "w") as f:
        f.write(f"memory_initialization_radix={radix};\n")
        f.write("memory_initialization_vector=\n")
        
        # Format string based on radix and bit-width
        if radix == 16:
            fmt = f"{{:0{width}X}}"
        elif radix == 2:
            fmt = f"{{:0{width}b}}"
        else:
            raise ValueError("Unsupported radix")
        
        total_items = len(data)
        for i, val in enumerate(data):
            hex_val = fmt.format(val)
            if i == total_items - 1:
                f.write(f"{hex_val};\n")
            else:
                f.write(f"{hex_val},\n")
    
    print(f"✓ Saved: {filepath} (Depth: {total_items})")

# ================= Main Program =================
def main():
    print("=" * 70)
    print("FPGA Multi-Algorithm Fault-Tolerant Test System - ROM Data Generator")
    print("Constraint: Burst Length (L) = 1 ~ 15. L=16 is reserved/zeroed.")
    print("=" * 70)
    
    # ========== 1. Generate BER Threshold Table (threshold_table.coe) ==========
    # Structure: [Algo_ID][BER_Index][Len_Index]
    # Len_Index maps 1~15 to 0~14.
    # Depth = 4 Algos * 91 BERs * 15 Lengths = 5460
    
    threshold_rom_depth = len(ALGORITHMS) * BER_POINTS * NUM_BURST_STEPS
    threshold_data = [0] * threshold_rom_depth
    
    print(f"\n[1/2] Generating BER Threshold Table...")
    print(f"      Depth: {threshold_rom_depth} | Width: 32-bit")
    
    for algo_name, params in ALGORITHMS.items():
        algo_id = params['id']
        w_valid = params['w_valid']
        
        for ber_idx in range(BER_POINTS):
            target_ber = BER_START + (ber_idx * BER_STEP)
            
            for length in BURST_LENGTHS:
                # 1. Calculate Threshold
                threshold = calculate_threshold(target_ber, length, w_valid)
                
                # 2. Calculate Address
                # Mapping: Addr = (Algo_ID * Block_Size) + (BER_Idx * Len_Steps) + (Len - 1)
                len_idx = length - 1  # 0 ~ 14
                
                addr = (algo_id * BER_POINTS * NUM_BURST_STEPS) + \
                       (ber_idx * NUM_BURST_STEPS) + \
                       len_idx
                
                # Boundary check (Sanity)
                if addr >= threshold_rom_depth:
                    raise RuntimeError(f"Address overflow in threshold_table: {addr}")
                    
                threshold_data[addr] = threshold
    
    write_coe_file("threshold_table.coe", threshold_data, radix=16, width=8)
    print(f"      Output dir: {ROM_OUTPUT_DIR}")
    
    # ========== 2. Generate Error Pattern Table (error_lut.coe) ==========
    # Structure: [Algo_ID (2-bit)][Len_Index (4-bit)][Offset (6-bit)]
    # Total Depth = 4 * 16 * 64 = 4096 (Fixed by Verilog address width)
    # Valid Data: L=1~15 (len_idx 0~14)
    # Illegal Data: L=16 (len_idx 15) -> Must be Zeroed
    
    ERROR_ROM_DEPTH = 4096  # 2^12
    OFFSET_BITS = 6
    OFFSET_RANGE = 1 << OFFSET_BITS # 64
    LEN_IDX_BITS = 4
    
    error_data = [0] * ERROR_ROM_DEPTH
    
    print(f"\n[2/2] Generating Error Pattern Table...")
    print(f"      Total Depth: {ERROR_ROM_DEPTH} | Width: 64-bit")
    print(f"      Valid L Range: 1~15 (Indices 0~14)")
    print(f"      Illegal L Range: 16 (Index 15) -> Zeroing...")
    
    for algo_name, params in ALGORITHMS.items():
        algo_id = params['id']
        w_valid = params['w_valid']
        
        # --- A. Fill Valid Data (L = 1 ~ 15) ---
        for length in BURST_LENGTHS:
            len_idx = length - 1  # 0 ~ 14
            
            # Max valid start position for this length
            # If length=3, w_valid=41, max_offset = 38 (indices 0..38 allow 3 bits)
            max_offset = w_valid - length
            
            for offset in range(OFFSET_RANGE):
                if offset <= max_offset and max_offset >= 0:
                    pattern = generate_error_pattern(length, offset, w_valid)
                else:
                    # Offset causes burst to exceed w_valid -> No error injected
                    pattern = 0
                
                # Address: {algo_id, len_idx, offset}
                addr = (algo_id << (LEN_IDX_BITS + OFFSET_BITS)) | \
                       (len_idx << OFFSET_BITS) | \
                       offset
                
                if addr >= ERROR_ROM_DEPTH:
                    raise RuntimeError(f"Address overflow in error_lut: {addr}")
                    
                error_data[addr] = pattern
        
        # --- B. Explicitly Zero Out Illegal Data (L = 16) ---
        # Even though design says L<=15, hardware address lines allow len_idx=15.
        # We explicitly fill these with 0 to ensure Fail-Safe behavior.
        illegal_len_idx = 15  # Corresponds to L=16
        for offset in range(OFFSET_RANGE):
            addr = (algo_id << (LEN_IDX_BITS + OFFSET_BITS)) | \
                   (illegal_len_idx << OFFSET_BITS) | \
                   offset
            error_data[addr] = 0
            
        print(f"      - {algo_name}: Filled L=1~15, Zeroed L=16")
    
    write_coe_file("error_lut.coe", error_data, radix=16, width=16)
    print(f"      Output dir: {ROM_OUTPUT_DIR}")
    
    # ========== Summary ==========
    print("\n" + "=" * 70)
    print("GENERATION COMPLETE")
    print("=" * 70)
    print(f"Algorithms: {len(ALGORITHMS)}")
    for name, p in ALGORITHMS.items():
        print(f"  - {name}: ID={p['id']}, W_valid={p['w_valid']}")
    
    print(f"\nThreshold Table:")
    print(f"  - BER Range: {BER_START:.2f} ~ {BER_START + (BER_POINTS-1)*BER_STEP:.2f}")
    print(f"  - Burst Len: {min(BURST_LENGTHS)} ~ {max(BURST_LENGTHS)}")
    print(f"  - File: threshold_table.coe")
    
    print(f"\nError Pattern Table:")
    print(f"  - Burst Len: {min(BURST_LENGTHS)} ~ {max(BURST_LENGTHS)} (L=16 Zeroed)")
    print(f"  - Offset: 0 ~ 63")
    print(f"  - File: error_lut.coe")
    
    print("\n[Next Step]")
    print("1. Copy .coe files to your Vivado project directory.")
    print("2. Ensure Verilog uses $readmemh or IP Initialization to load them.")
    print("3. Re-run Synthesis and Implementation to bake data into Block RAM.")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n rror occurred: {e}")
        import traceback
        traceback.print_exc()