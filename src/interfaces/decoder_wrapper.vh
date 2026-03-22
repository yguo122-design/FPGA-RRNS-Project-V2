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

`define DEC_ALGO_BITS         3   // Extended to 3-bit to support 8 algorithms
`define DEC_DATA_WIDTH        16
`define DEC_INPUT_BUS_WIDTH   64  // Max width to support all algos

// Algorithm IDs (3-bit, supports up to 8 algorithms)
`define DEC_ALGO_2NRM         3'd0   // 2NRM-RRNS
`define DEC_ALGO_3NRM         3'd1   // 3NRM-RRNS
`define DEC_ALGO_C_RRNS       3'd2   // C-RRNS-MLD (alias for backward compatibility)
`define DEC_ALGO_CRRNS_MLD    3'd2   // C-RRNS with Maximum Likelihood Decoding
`define DEC_ALGO_CRRNS_MRC    3'd3   // C-RRNS with Mixed Radix Conversion (reserved)
`define DEC_ALGO_CRRNS_CRT    3'd4   // C-RRNS with Chinese Remainder Theorem (reserved)
`define DEC_ALGO_RS           3'd5   // Reed-Solomon (reserved)

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