// =============================================================================
// File: main_scan_fsm.vh
// Description: Header for Main Scan FSM (Top-Level Controller)
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.1.3.2 & 2.3.3.5
//
// Strategy:
//   - Single Algorithm per Build: Use `ifdef to select Encoder/Decoder logic.
//   - BER Sweep Only: FSM iterates ONLY through BER points (0.01 ~ 0.10).
//   - Unified Upload: Wait for ALL 91 points to complete, then upload once.
// =============================================================================

`ifndef MAIN_SCAN_FSM_VH
`define MAIN_SCAN_FSM_VH

// -----------------------------------------------------------------------------
// 1. Configuration Parameters
// -----------------------------------------------------------------------------

// [IMPORTANT] Compile-time Algorithm Selection
// The hardware implementation (Encoder/Decoder) is selected via `ifdef in RTL.
// This ID is stored in the result header so the host knows which algo was tested.
// Options: 0=2NRM, 1=3NRM, 2=C-RRNS, 3=RS
// Default to 0 if not defined externally.
`ifndef CURRENT_ALGO_ID
    `define CURRENT_ALGO_ID     0
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