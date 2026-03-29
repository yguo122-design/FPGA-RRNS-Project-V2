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
# IDs must match the Verilog 'algo_id' input encoding (3-bit, 0~7)
# C-RRNS-MRC and C-RRNS-CRT share the same encoder (W_valid=61) as C-RRNS-MLD
ALGORITHMS = {
    '2NRM':           {'w_valid': 41, 'id': 0},
    '3NRM':           {'w_valid': 48, 'id': 1},
    'C-RRNS-MLD':     {'w_valid': 61, 'id': 2},  # C-RRNS with MLD decoding
    'C-RRNS-MRC':     {'w_valid': 61, 'id': 3},  # C-RRNS with MRC decoding (same encoder)
    'C-RRNS-CRT':     {'w_valid': 61, 'id': 4},  # C-RRNS with CRT decoding (same encoder)
    'RS':             {'w_valid': 48, 'id': 5},
    '2NRM-Serial':    {'w_valid': 41, 'id': 6},  # 2NRM sequential FSM MLD (same encoder/W_valid as 2NRM)
}

# BER Test Points: 101 points, from 0% (0.000) to 10% (0.100), step 0.001
# BER_Index 0 → BER=0.000 (baseline, no injection), 1 → 0.001, ..., 100 → 0.100
BER_POINTS = 101
BER_START = 0.0
BER_STEP = 0.001

# Burst Length Range: 1 ~ 15 (Strictly enforced per Doc v1.61)
# Python range(1, 16) generates [1, 2, ..., 15]
BURST_LENGTHS = list(range(1, 16)) 
MAX_BURST_LEN = 15
NUM_BURST_STEPS = MAX_BURST_LEN  # Should be 15

# ================= Utility Functions =================
def calculate_threshold(target_ber: float, burst_len: int, w_valid: int) -> int:
    """
    Calculate LFSR Threshold Integer.

    Two injection models are used depending on burst_len:

    --- burst_len == 1 (Random Single Bit, Bit-Scan Bernoulli model) ---
    The FPGA auto_scan_engine uses a bit-scan loop: for each bit position
    0..(w_valid-1), it compares inj_lfsr directly against threshold_val.
    The per-bit flip probability is:
        P(flip) = threshold_val / (2^32 - 1) = BER_target

    Therefore: threshold_val = round(BER_target * (2^32 - 1))

    No offset-range compensation is needed because the bit-scan model does
    not use the error_lut ROM at all — it directly flips individual bits.
    This allows actual BER to reach up to 100% without saturation.

    --- burst_len > 1 (Cluster Burst, ROM single-injection model) ---
    BUG FIX (2026-03-21, Bug #62):
    The original formula did NOT account for the fact that the 6-bit random
    offset from the LFSR covers [0, 63], but only [0, w_valid - burst_len]
    are valid. Invalid offsets cause the error_lut ROM to return 0 (no
    injection), so the actual injection probability is:
        P_actual = P_trigger * (w_valid - burst_len + 1) / 64

    FIX: Multiply P_trigger by the compensation factor 64 / num_valid_offsets:
        P_trigger_corrected = (BER_target * W_valid / L) * (64 / num_valid_offsets)

    Formula: Threshold_Int = round( P_trigger_corrected * (2^32 - 1) )
    """
    if burst_len <= 0:
        return 0

    if burst_len == 1:
        # Bit-scan Bernoulli model: threshold = BER_target * (2^32 - 1)
        # FPGA uses: if (inj_lfsr < threshold_val) → flip this bit
        # P(flip) = threshold_val / (2^32 - 1) = BER_target  ✓
        # No ×64 compensation needed — bit-scan does not use error_lut ROM.
        threshold = round(target_ber * (2**32 - 1))
        return max(0, min(threshold, 0xFFFFFFFF))

    # burst_len > 1: ROM-based single burst injection (original formula with Bug #62 fix)
    num_valid_offsets = w_valid - burst_len + 1
    if num_valid_offsets <= 0:
        # burst_len > w_valid: impossible to inject, return 0
        return 0

    # OFFSET_RANGE = 64 (6-bit LFSR offset field)
    OFFSET_RANGE = 64

    # Base trigger probability (without compensation)
    p_trigger_base = (target_ber * w_valid) / burst_len

    # Compensation factor: scale up to account for invalid offsets returning 0
    compensation = OFFSET_RANGE / num_valid_offsets
    p_trigger_corrected = p_trigger_base * compensation

    # Map probability to 32-bit integer space
    threshold = round(p_trigger_corrected * (2**32 - 1))

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
    
    # Bug #77 fix: expanded from 12-bit to 13-bit address to support 8 algo_ids.
    # New: {algo_id[2:0], len_idx[3:0], offset[5:0]} = 13-bit = 8192 depth
    ERROR_ROM_DEPTH = 8192  # 2^13 (was 4096=2^12)
    OFFSET_BITS = 6
    OFFSET_RANGE = 1 << OFFSET_BITS # 64
    LEN_IDX_BITS = 4
    ALGO_ID_BITS = 3  # 3-bit algo_id (was 2-bit)
    
    error_data = [0] * ERROR_ROM_DEPTH
    
    print(f"\n[2/2] Generating Error Pattern Table...")
    print(f"      Total Depth: {ERROR_ROM_DEPTH} | Width: 64-bit")
    print(f"      Valid L Range: 1~15 (Indices 0~14)")
    print(f"      Illegal L Range: 16 (Index 15) -> Zeroing...")
    print(f"      Bug #77 fix: 13-bit address, all 6 algo_ids have correct W_valid")
    
    # All algorithms now have their own slot in the 13-bit address space.
    # algo_id[2:0] directly indexes the correct slot.
    ERROR_LUT_ALGOS = ALGORITHMS  # All algorithms (no id<=3 filter)
    
    for algo_name, params in ERROR_LUT_ALGOS.items():
        algo_id = params['id']
        w_valid = params['w_valid']
        
        # --- A. Fill Valid Data (L = 1 ~ 15) ---
        for length in BURST_LENGTHS:
            len_idx = length - 1  # 0 ~ 14
            
            # Max valid start position for this length
            max_offset = w_valid - length
            
            for offset in range(OFFSET_RANGE):
                if offset <= max_offset and max_offset >= 0:
                    pattern = generate_error_pattern(length, offset, w_valid)
                else:
                    pattern = 0
                
                # Address: {algo_id[1:0], len_idx, offset} (12-bit)
                addr = (algo_id << (LEN_IDX_BITS + OFFSET_BITS)) | \
                       (len_idx << OFFSET_BITS) | \
                       offset
                
                if addr >= ERROR_ROM_DEPTH:
                    raise RuntimeError(f"Address overflow in error_lut: {addr}")
                    
                error_data[addr] = pattern
        
        # --- B. Explicitly Zero Out Illegal Data (L = 16) ---
        illegal_len_idx = 15
        for offset in range(OFFSET_RANGE):
            addr = (algo_id << (LEN_IDX_BITS + OFFSET_BITS)) | \
                   (illegal_len_idx << OFFSET_BITS) | \
                   offset
            error_data[addr] = 0
            
        print(f"      - {algo_name} (id={algo_id}): Filled L=1~15, Zeroed L=16")
    
    print(f"      All 6 algo_ids now have correct W_valid in error_lut (Bug #77 fixed)")
    
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