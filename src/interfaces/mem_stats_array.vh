// =============================================================================
// File: mem_stats_array.vh
// Description: Header for Memory Statistics Array Module
//              Complies with Design Doc v1.7 Section 2.1.3.2 & 2.3.3.5
//
// REFACTOR NOTE (v3.0):
//   v1.0: 64-bit Circular Buffer (1024 entries) — Single-Event Logger
//   v2.0: 176-bit Statistical Aggregator (101 entries, 22 Bytes/point)
//         Added: 64-bit Clk_Count, 32-bit Success/Fail/Flip counters
//   v3.0: 240-bit Statistical Aggregator (101 entries, 30 Bytes/point)
//         Added: 32-bit Enc_Clk_Count (encoder clock cycles per BER point)
//                32-bit Dec_Clk_Count (decoder clock cycles per BER point)
//         PC-side: Avg_Enc_Clk = Enc_Clk_Count / Total_Trials
//                  Avg_Dec_Clk = Dec_Clk_Count / Total_Trials
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

// Data Width per Entry: 240 bits = 30 Bytes
// Breakdown (Big-Endian field order, MSB first):
//   [239:232] BER_Index          (8-bit,  Uint8,  value = ber_cnt 0~100)
//   [231:200] Success_Count      (32-bit, Uint32, cumulative pass count)
//   [199:168] Fail_Count         (32-bit, Uint32, cumulative fail count)
//   [167:136] Actual_Flip_Count  (32-bit, Uint32, total bits flipped this point)
//   [135:72]  Clk_Count          (64-bit, Uint64, total clock cycles this point)
//   [71:40]   Enc_Clk_Count      (32-bit, Uint32, total encoder clock cycles this point)
//   [39:8]    Dec_Clk_Count      (32-bit, Uint32, total decoder clock cycles this point)
//   [7:0]     Reserved           (8-bit,  0x00,   padding for BRAM alignment)
//
// PC-side calculation:
//   Avg_Enc_Clk_Per_Trial = Enc_Clk_Count / Total_Trials
//   Avg_Dec_Clk_Per_Trial = Dec_Clk_Count / Total_Trials
`define STATS_DATA_WIDTH      240

// Bit Field Positions (for FSM packing convenience)
`define STATS_BP_BER_IDX_HI   239
`define STATS_BP_BER_IDX_LO   232
`define STATS_BP_SUCCESS_HI   231
`define STATS_BP_SUCCESS_LO   200
`define STATS_BP_FAIL_HI      199
`define STATS_BP_FAIL_LO      168
`define STATS_BP_FLIP_HI      167
`define STATS_BP_FLIP_LO      136
`define STATS_BP_CLK_HI       135
`define STATS_BP_CLK_LO       72
`define STATS_BP_ENC_CLK_HI   71
`define STATS_BP_ENC_CLK_LO   40
`define STATS_BP_DEC_CLK_HI   39
`define STATS_BP_DEC_CLK_LO   8
`define STATS_BP_RESERVED_HI  7
`define STATS_BP_RESERVED_LO  0

// -----------------------------------------------------------------------------
// 2. BRAM Mapping Note
// -----------------------------------------------------------------------------
// 101 entries × 240 bits = 24,240 bits ≈ 23.7 Kbits
// Xilinx Artix-7 RAMB36E1: 36 Kbits per tile
// → Fits in 1 × RAMB36E1
// → Vivado will infer as Block RAM with (* ram_style = "block" *) attribute
//
// Address space: 0~100 valid, 101~127 unused (writes to unused addresses
// are harmless; reads return undefined data but FSM never reads beyond 100).

`endif // MEM_STATS_ARRAY_VH
