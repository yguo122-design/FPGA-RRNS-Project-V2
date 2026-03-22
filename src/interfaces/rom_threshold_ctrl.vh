// =============================================================================
// File: rom_threshold_ctrl.vh
// Description: Header for BER Threshold ROM Controller
//              Complies with Design Doc v1.61 Section 2.3.2.4 & 2.3.2.5
//
// Address Mapping Logic (Derived from gen_rom.py & Doc 2.3.2.4):
//   Addr = (algo_id * 91 * 15) + (ber_idx * 15) + (burst_len - 1)
//   Constants:
//     - BER_POINTS = 91 (Indices 0~90)
//     - BURST_STEPS = 15 (Lengths 1~15 mapped to 0~14)
//     - ALGO_COUNT = 4
//   Total Logical Depth = 4 * 91 * 15 = 5460 entries.
//   Physical Address Width = 13 bits (2^13 = 8192 > 5460).
// =============================================================================

`ifndef ROM_THRESHOLD_CTRL_VH
`define ROM_THRESHOLD_CTRL_VH

// -----------------------------------------------------------------------------
// 1. ROM Configuration Parameters (Section 2.3.2.4)
// -----------------------------------------------------------------------------

// Data Width: 32 bits (Threshold Integer for LFSR comparison)
`define THRESH_ROM_DATA_WIDTH   32

// Address Calculation Constants
`define THRESH_BER_POINTS       101     // BER Indices: 0 ~ 100 (BER 0.000~0.100)
`define THRESH_BER_BITS         7       // ceil(log2(101)) = 7 bits (2^7=128 > 101)
`define THRESH_LEN_STEPS        15      // Burst Length Steps: 1 ~ 15
`define THRESH_LEN_BITS         4       // ceil(log2(15)) = 4 bits
`define THRESH_ALGO_COUNT       4       // 4 Algorithms (2NRM, 3NRM, C-RRNS, RS)
`define THRESH_ALGO_BITS        3       // 3 bits (Bug #78 fix: was 2, truncated id=4 to 0)

// ROM Depth Calculation
// Logical Max Address = (3 * 91 * 15) + (90 * 15) + 14 = 5459
// Total Entries = 5460
`define THRESH_ROM_LOGICAL_DEPTH 5460

// Physical Address Width: Need 13 bits to cover 5460 entries (2^12=4096 is too small)
`define THRESH_ROM_ADDR_WIDTH   13

// COE File Path (relative to Vivado project simulation working directory,
// OR absolute path for robustness).
// gen_rom.py outputs to: src/ROM/threshold_table.coe
// For $readmemh in simulation: path is relative to the simulation run directory.
// For Vivado synthesis with $readmemh in initial block: use absolute path or
// add src/ROM to Vivado's "include path" / "data file" settings.
// FIX ROM-PATH: Changed from bare filename to src/ROM/ relative path.
`define THRESH_ROM_COE_FILE     "../../../../src/ROM/threshold_table.coe"
// Note: "../../../../" navigates from FPGAProjectV2/<run_dir>/ up to project root.
// Adjust depth if your Vivado project structure differs.

// -----------------------------------------------------------------------------
// 2. Module Interface Macros
// -----------------------------------------------------------------------------

/*
Usage Example:
  wire [1:0] algo_id;
  wire [6:0] ber_idx;      // 0 ~ 90
  wire [3:0] burst_len;    // 1 ~ 15
  wire [31:0] threshold_val;
  wire thresh_valid;
  
  rom_threshold_ctrl u_thresh (
    .clk(clk),
    .rst_n(rst_n),
    .req(req),             // Lookup request
    .algo_id(algo_id),
    .ber_idx(ber_idx),
    .burst_len(burst_len),
    .threshold_val(threshold_val),
    .valid(thresh_valid)
  );
*/

`endif // ROM_THRESHOLD_CTRL_VH