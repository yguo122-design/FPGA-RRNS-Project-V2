// =============================================================================
// File: decoder_2nrm.vh
// Description: Header for 2NRM Decoder Module
//              Complies with Design Doc v1.61 Section 2.3.3.3
//
// Algorithm Specs (2NRM):
//   - Moduli Set: {257, 256, 61, 59, 55, 53} (6 Moduli)
//   - Data Width: 16 bits
//   - Redundancy: 4 (t=2 error correction capability)
//   - Input Packing: 41 bits total
//     [40:32] = r257 (9-bit)
//     [31:24] = r256 (8-bit)
//     [23:18] = r61  (6-bit)
//     [17:12] = r59  (6-bit)
//     [11:6]  = r55  (6-bit)
//     [5:0]   = r53  (6-bit)
// =============================================================================

`ifndef DECODER_2NRM_VH
`define DECODER_2NRM_VH

// -----------------------------------------------------------------------------
// 1. Algorithm Parameters
// -----------------------------------------------------------------------------

`define NRM_DATA_WIDTH        16
`define NRM_MODULI_COUNT      6
`define NRM_REDUNDANCY        4
`define NRM_MAX_ERRORS        2   // t=2

// Input Packed Width Calculation: 9 + 8 + 6*4 = 41 bits
`define NRM_INPUT_PACKED_WIDTH 41

// Channel Count for MLD: C(6, 2) = 15 parallel channels
`define NLM_CHANNEL_COUNT     15

// Max Hamming Distance possible (equal to redundancy)
`define NRM_MAX_DISTANCE      4

// -----------------------------------------------------------------------------
// 2. Module Interface Macros
// -----------------------------------------------------------------------------

/*
Usage Example:
  wire [40:0] residues;
  wire [15:0] data_out;
  wire dec_valid, dec_uncorr;

  decoder_2nrm u_dec (
    .clk(clk),
    .rst_n(rst_n),
    .start(start_pulse),
    .residues_in(residues),
    .data_out(data_out),
    .valid(dec_valid),
    .uncorrectable(dec_uncorr)
  );
*/

`endif // DECODER_2NRM_VH