// =============================================================================
// File: result_comparator.vh
// Description: Header for Result Comparator Module
//              Complies with Design Doc v1.61 Section 2.3.3.4
//
// Features:
//   - Caches original data (D_orig) in a FIFO to align with decoder latency.
//   - Compares D_orig vs D_recov bit-by-bit.
//   - Safety Check: Forces Failure if D_orig != D_recov, even if Decoder claims success.
//   - Latency Measurement: Counts cycles from 'start' to 'valid'.
// =============================================================================

`ifndef RESULT_COMPARATOR_VH
`define RESULT_COMPARATOR_VH

// -----------------------------------------------------------------------------
// 1. Configuration Parameters
// -----------------------------------------------------------------------------

// FIFO Depth: Must be >= Max Decoder Latency + Safety Margin
// Current Max Latency: 842 cycles (3NRM FSM). Set to 16 for safety/future expansion.
// Note: Only 1 entry is ever in the FIFO at a time (single-channel mode),
// so depth=16 is more than sufficient.
`define COMP_FIFO_DEPTH       16
`define COMP_FIFO_ADDR_WIDTH  4   // $clog2(16)

// Data Widths
`define COMP_DATA_WIDTH       16
// LATENCY_WIDTH: Must cover max decoder latency.
// 3NRM FSM decoder: 842 cycles. Use 12-bit (max 4095 cycles).
// Note: auto_scan_engine.v latency_cycles port must match this width.
`define COMP_LATENCY_WIDTH    12  // Max measurable latency: 4095 cycles (covers 3NRM 842 cycles)

// -----------------------------------------------------------------------------
// 2. Status Codes
// -----------------------------------------------------------------------------

`define COMP_STATUS_IDLE      2'd0
`define COMP_STATUS_PASS      2'd1
`define COMP_STATUS_FAIL      2'd2
`define COMP_STATUS_PENDING   2'd3  // Waiting for decoder response

// -----------------------------------------------------------------------------
// 3. Module Interface Macros
// -----------------------------------------------------------------------------

/*
Usage Example:
  wire [15:0] original_data;
  wire [15:0] recovered_data;
  wire start_pulse, dec_valid;
  
  wire test_pass;
  wire [7:0] measured_latency;
  wire comparator_ready;

  result_comparator u_cmp (
    .clk(clk),
    .rst_n(rst_n),
    .start(start_pulse),          // Pushes original_data into FIFO
    .data_orig(original_data),    // Data to cache
    .valid_in(dec_valid),         // Decoder valid signal
    .data_recov(recovered_data),  // Decoder output
    .test_result(test_pass),      // 1: Pass, 0: Fail
    .current_latency(measured_latency),
    .ready(comparator_ready)      // Ready for next test case
  );
*/

`endif // RESULT_COMPARATOR_VH