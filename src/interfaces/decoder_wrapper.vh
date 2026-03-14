// =============================================================================
// File: decoder_wrapper.vh
// Description: Header for Top-Level Decoder Wrapper
//              Complies with Design Doc v1.61 Section 2.3.3.3
//
// Features:
//   - Unified interface for multiple algorithms (2NRM, 3NRM, C-RRNS, RS)
//   - Algorithm selection via algo_id [1:0]
//   - Generic input bus (64-bit) to accommodate largest algorithm
// =============================================================================

`ifndef DECODER_WRAPPER_VH
`define DECODER_WRAPPER_VH

// -----------------------------------------------------------------------------
// 1. Configuration Parameters
// -----------------------------------------------------------------------------

`define DEC_ALGO_BITS         2
`define DEC_DATA_WIDTH        16
`define DEC_INPUT_BUS_WIDTH   64  // Max width to support all algos

// Algorithm IDs
`define DEC_ALGO_2NRM         2'd0
`define DEC_ALGO_3NRM         2'd1
`define DEC_ALGO_C_RRNS       2'd2
`define DEC_ALGO_RS           2'd3

// -----------------------------------------------------------------------------
// 2. Module Interface Macros
// -----------------------------------------------------------------------------

/*
Usage Example:
  wire [1:0] algo_sel;
  wire [63:0] res_bus;
  wire [15:0] decoded_data;
  
  decoder_wrapper u_top_dec (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .algo_id(algo_sel),
    .residues_in(res_bus),
    .data_out(decoded_data),
    .valid(dec_valid),
    .uncorrectable(dec_err)
  );
*/

`endif // DECODER_WRAPPER_VH