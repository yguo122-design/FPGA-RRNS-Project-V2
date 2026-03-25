// =============================================================================
// File: main_scan_fsm.vh
// Description: Header for Main Scan FSM (Top-Level Controller)
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.1.3.2 & 2.3.3.5
//
// Strategy:
//   - Single Algorithm per Build: Use `ifdef to select Encoder/Decoder logic.
//   - BER Sweep Only: FSM iterates ONLY through BER points (0.01 ~ 0.10).
//   - Unified Upload: Wait for ALL 101 points to complete, then upload once.
// =============================================================================

`ifndef MAIN_SCAN_FSM_VH
`define MAIN_SCAN_FSM_VH

// -----------------------------------------------------------------------------
// 1. Configuration Parameters
// -----------------------------------------------------------------------------

// =============================================================================
// [IMPORTANT] Compile-time Algorithm Selection via Build Macro
// =============================================================================
// To switch algorithm:
//   1. Comment out the current `define BUILD_ALGO_xxx line below
//   2. Uncomment the desired `define BUILD_ALGO_xxx line
//   3. Run Implementation in Vivado (full re-synthesis required)
//
// Only ONE macro should be defined at a time!
//
// *** CURRENT BUILD: RS (algo_id=5) ***
// -----------------------------------------------------------------
// `define BUILD_ALGO_2NRM        // algo_id=0: 2NRM-RRNS,        41b, t=2, ~27 cycles  (parallel MLD)
// `define BUILD_ALGO_3NRM        // algo_id=1: 3NRM-RRNS,        48b, t=3, ~842 cycles
// `define BUILD_ALGO_CRRNS_MLD   // algo_id=2: C-RRNS-MLD,       61b, t=3, ~924 cycles
// `define BUILD_ALGO_CRRNS_MRC   // algo_id=3: C-RRNS-MRC,       61b, none, ~8 cycles
// `define BUILD_ALGO_CRRNS_CRT   // algo_id=4: C-RRNS-CRT,       61b, none, ~5 cycles
// `define BUILD_ALGO_RS          // algo_id=5: RS(12,4),          48b, t=4, ~60 cycles
 `define BUILD_ALGO_2NRM_SERIAL // algo_id=6: 2NRM-RRNS-Serial, 41b, t=2, ~150 cycles (sequential FSM MLD)
// -----------------------------------------------------------------

// Derive CURRENT_ALGO_ID from the build macro (do not edit below)
`ifdef BUILD_ALGO_2NRM
    `define CURRENT_ALGO_ID  0
`elsif BUILD_ALGO_3NRM
    `define CURRENT_ALGO_ID  1
`elsif BUILD_ALGO_CRRNS_MLD
    `define CURRENT_ALGO_ID  2
`elsif BUILD_ALGO_CRRNS_MRC
    `define CURRENT_ALGO_ID  3
`elsif BUILD_ALGO_CRRNS_CRT
    `define CURRENT_ALGO_ID  4
`elsif BUILD_ALGO_RS
    `define CURRENT_ALGO_ID  5
`elsif BUILD_ALGO_2NRM_SERIAL
    `define CURRENT_ALGO_ID  6
`else
    `define CURRENT_ALGO_ID  5  // default: RS
`endif

// Number of BER points: 0.000 to 0.100, step 0.001
// Calculation: (0.100 - 0.000) / 0.001 + 1 = 101 points
// BER_Index 0 → BER=0.000 (baseline, no injection), 100 → BER=0.100
`define NUM_BER_POINTS      101

// Total Test Entries = Just the BER points (since Algo is fixed per build)
// Total = 101 entries.
`define TOTAL_TEST_ENTRIES  `NUM_BER_POINTS

// Memory Depth: Must accommodate ALL 101 test results.
// Each entry is 22 bytes. Total size = 101 * 22 = 2222 Bytes.
// Fits easily in a single small BRAM.
`define MEM_DEPTH           `TOTAL_TEST_ENTRIES

// -----------------------------------------------------------------------------
// 2. Main FSM States
// -----------------------------------------------------------------------------
`define MAIN_STATE_IDLE         4'd0  // Wait for global start command
`define MAIN_STATE_INIT_CFG     4'd1  // Load threshold for current BER index
`define MAIN_STATE_RUN_TEST     4'd2  // Trigger auto_scan_engine, wait for done
`define MAIN_STATE_SAVE_RES     4'd3  // Write result to mem_stats_array
`define MAIN_STATE_NEXT_ITER    4'd4  // Increment BER index, check loop termination
`define MAIN_STATE_PREP_UPLOAD  4'd5  // All 91 tests done. Prepare tx_packet_assembler
`define MAIN_STATE_DO_UPLOAD    4'd6  // Start tx_packet_assembler, wait for completion
`define MAIN_STATE_FINISH       4'd7  // Assert global_done, return to IDLE

// -----------------------------------------------------------------------------
// 3. Global Status Flags
// -----------------------------------------------------------------------------
`define SYS_STATUS_IDLE         2'd0
`define SYS_STATUS_TESTING      2'd1  // Busy running BER sweep
`define SYS_STATUS_UPLOADING    2'd2  // Busy uploading full results
`define SYS_STATUS_DONE         2'd3  // Completed

// -----------------------------------------------------------------------------
// 4. Result Entry Format (64-bit / 8 Bytes)
//    Stored in mem_stats_array
//
//    PACKING v1.1 (Single Algo Mode, with BUG FIX P3 - uncorr_cnt):
//    [63:56] : BER_Idx (8 bits) -- Supports 0-255 (covers 0-90)
//    [55:54] : Algo_ID (2 bits) -- Fixed constant `CURRENT_ALGO_ID
//    [53:48] : Reserved (6 bits)
//    [47:40] : Flip_Count_A (8 bits)
//    [39:32] : Flip_Count_B (8 bits)
//    [31:24] : Latency_Cycles (8 bits)
//    [23:10] : Reserved (14 bits)  ← was 16 bits, reduced by 2 for Uncorr_Cnt
//    [09:08] : Uncorr_Cnt (2 bits) ← NEW (FIX P3)
//              [09] = Channel B uncorrectable (dec_uncorr_b)
//              [08] = Channel A uncorrectable (dec_uncorr_a)
//    [07:00] : Status Flags
//              [07] : Was_Injected (1 bit)
//              [06] : Pass/Fail (1 bit, 1=Pass)
//              [05:00]: Reserved
//
// DIAGNOSTIC MATRIX (for PC-side analysis):
//   Pass=1, Uncorr=2'b00 → Clean PASS
//   Pass=0, Uncorr=2'b00 → BER_FAIL (wrong data, decoder claimed correctable)
//   Pass=0, Uncorr≠2'b00 → UNCORR_FAIL (ECC hard failure)
//   Pass=1, Uncorr≠2'b00 → IMPOSSIBLE (debug flag)
// -----------------------------------------------------------------------------

// Bit Field Definitions for Result Packing (v1.1)
`define RES_BP_BER_IDX        63:56  // 8 bits
`define RES_BP_ALGO_ID        55:54  // 2 bits
`define RES_BP_FLIP_CNT_A     47:40  // 8 bits
`define RES_BP_FLIP_CNT_B     39:32  // 8 bits
`define RES_BP_LATENCY        31:24  // 8 bits
`define RES_BP_UNCORR_CNT     9:8    // 2 bits (NEW - FIX P3)
`define RES_BP_UNCORR_B       9      // 1 bit: Channel B uncorrectable
`define RES_BP_UNCORR_A       8      // 1 bit: Channel A uncorrectable
`define RES_BP_INJECTED       7      // 1 bit
`define RES_BP_PASS_FAIL      6      // 1 bit

// -----------------------------------------------------------------------------
// 5. Interface Macro
// -----------------------------------------------------------------------------
/*
Usage:
  main_scan_fsm u_top (
    .clk          (clk),
    .rst_n        (rst_n),
    .sys_start    (uart_cmd_start), 
    .sys_abort    (uart_cmd_abort), 
    .busy         (sys_busy),
    .done         (sys_done),       
    .status       (sys_status),     
    .tx_valid     (tx_valid),
    .tx_data      (tx_data),
    .tx_ready     (tx_fifo_ready)   
  );
*/

`endif // MAIN_SCAN_FSM_VH