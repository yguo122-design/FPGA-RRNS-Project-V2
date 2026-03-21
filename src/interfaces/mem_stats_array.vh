// =============================================================================
// File: mem_stats_array.vh
// Description: Header for Memory Statistics Array Module
//              Complies with Design Doc v1.7 Section 2.1.3.2 & 2.3.3.5
//
// REFACTOR NOTE (v2.0):
//   Previous version (v1.0) used a 64-bit Circular Buffer (1024 entries)
//   designed as a "Single-Event Logger". This was an architectural mismatch
//   against Spec v1.7 which requires a "BER Statistical Aggregator".
//
//   v2.0 changes:
//   - Data width: 64-bit → 176-bit (22 Bytes/point per Spec 2.1.3.2)
//   - Depth: 1024 → 91 (one entry per BER test point)
//   - Address: internal auto-increment → external wr_addr from FSM (= ber_idx)
//   - Removed: Circular/Stop-on-Fail/Once modes (not required by spec)
//   - Added: 64-bit Clk_Count, 32-bit Success/Fail/Flip counters
// =============================================================================

`ifndef MEM_STATS_ARRAY_VH
`define MEM_STATS_ARRAY_VH

// -----------------------------------------------------------------------------
// 1. Memory Configuration (Spec v1.7 Section 2.3.3.5)
// -----------------------------------------------------------------------------

// Total Entries: 101 (one per BER test point, index 0~100)
// BER_Index 0 → BER=0.000 (baseline), 100 → BER=0.100
`define STATS_MEM_DEPTH       101
`define STATS_MEM_ADDR_WIDTH  7    // ceil(log2(101)) = 7 bits (2^7=128 > 101)

// Data Width per Entry: 176 bits = 22 Bytes
// Breakdown (Big-Endian field order, MSB first):
//   [175:168] BER_Index          (8-bit,  Uint8,  value = ber_cnt 0~90)
//   [167:136] Success_Count      (32-bit, Uint32, cumulative pass count)
//   [135:104] Fail_Count         (32-bit, Uint32, cumulative fail count)
//   [103:72]  Actual_Flip_Count  (32-bit, Uint32, total bits flipped this point)
//   [71:8]    Clk_Count          (64-bit, Uint64, total clock cycles this point)
//   [7:0]     Reserved           (8-bit,  0x00,   padding for BRAM alignment)
`define STATS_DATA_WIDTH      176

// Bit Field Positions (for FSM packing convenience)
`define STATS_BP_BER_IDX_HI   175
`define STATS_BP_BER_IDX_LO   168
`define STATS_BP_SUCCESS_HI   167
`define STATS_BP_SUCCESS_LO   136
`define STATS_BP_FAIL_HI      135
`define STATS_BP_FAIL_LO      104
`define STATS_BP_FLIP_HI      103
`define STATS_BP_FLIP_LO      72
`define STATS_BP_CLK_HI       71
`define STATS_BP_CLK_LO       8
`define STATS_BP_RESERVED_HI  7
`define STATS_BP_RESERVED_LO  0

// -----------------------------------------------------------------------------
// 2. BRAM Mapping Note
// -----------------------------------------------------------------------------
// 91 entries × 176 bits = 16,016 bits ≈ 15.6 Kbits
// Xilinx Artix-7 RAMB18E1: 18 Kbits per tile
// → Fits in 1 × RAMB18E1 (with parity bits used for data extension)
// → Vivado will infer as Block RAM with (* ram_style = "block" *) attribute
//
// Address space: 0~90 valid, 91~127 unused (writes to unused addresses
// are harmless; reads return undefined data but FSM never reads beyond 90).

`endif // MEM_STATS_ARRAY_VH
