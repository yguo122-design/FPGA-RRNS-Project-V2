// =============================================================================
// File: auto_scan_engine.vh
// Description: Header for Auto Scan Engine Module
//              Complies with Design Doc v1.61 Section 2.3.3.5 (Green Block)
//
// Features:
//   - Encapsulates the full single-test flow: Gen -> Enc -> Inj -> Dec -> Comp.
//   - Provides a simple Start/Busy/Done interface to the top-level FSM.
//   - Outputs test results (Pass/Fail, Latency) upon completion.
// =============================================================================

`ifndef AUTO_SCAN_ENGINE_VH
`define AUTO_SCAN_ENGINE_VH

// -----------------------------------------------------------------------------
// 1. Engine States (Internal FSM)
// -----------------------------------------------------------------------------
`define ENG_STATE_IDLE      3'd0
`define ENG_STATE_CONFIG    3'd1  // Latch params, reset sub-modules
`define ENG_STATE_GEN_WAIT  3'd2  // Wait for Data Gen ready (if needed)
`define ENG_STATE_ENC_WAIT  3'd3  // Wait for Encoder to finish
`define ENG_STATE_INJ_WAIT  3'd4  // Wait for Error Injection to settle
`define ENG_STATE_DEC_WAIT  3'd5  // Wait for Decoder to finish
`define ENG_STATE_COMP_WAIT 3'd6  // Wait for Comparator result
`define ENG_STATE_DONE      3'd7  // Pulse done, output results

// -----------------------------------------------------------------------------
// 2. Test Result Flags
// -----------------------------------------------------------------------------
`define TEST_PASS           1'b1
`define TEST_FAIL           1'b0

// -----------------------------------------------------------------------------
// 3. Interface Macros
// -----------------------------------------------------------------------------
/*
Usage Example:
  wire clk, rst_n;
  wire engine_start;
  wire [1:0] algo_id;
  wire [3:0] ber_idx;
  
  wire engine_busy;
  wire engine_done;
  wire test_result_pass;
  wire [7:0] test_latency;
  
  auto_scan_engine u_engine (
    .clk(clk),
    .rst_n(rst_n),
    .start(engine_start),
    .algo_id(algo_id),
    .ber_idx(ber_idx),
    .threshold_val(threshold_from_rom),
    .busy(engine_busy),
    .done(engine_done),
    .result_pass(test_result_pass),
    .latency_cycles(test_latency)
  );
*/

`endif // AUTO_SCAN_ENGINE_VH