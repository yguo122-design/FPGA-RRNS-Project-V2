// =============================================================================
// File: decoder_wrapper.v
// Description: Top-Level Decoder Wrapper with Algorithm Routing
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.3.3
// Version: v1.0
//
// ─────────────────────────────────────────────────────────────────────────────
// ARCHITECTURE OVERVIEW:
//   This module provides a unified 64-bit input interface for all decoding
//   algorithms. The algo_id input selects which decoder is active. All
//   decoders run in parallel (inputs are broadcast), but only the selected
//   decoder's outputs are forwarded to the output registers.
//
// ALGORITHM ROUTING:
//   algo_id = 0 (DEC_ALGO_2NRM):   decoder_2nrm  [IMPLEMENTED]
//   algo_id = 1 (DEC_ALGO_3NRM):   decoder_3nrm  [RESERVED - future]
//   algo_id = 2 (DEC_ALGO_C_RRNS): decoder_crrns [RESERVED - future]
//   algo_id = 3 (DEC_ALGO_RS):     decoder_rs    [RESERVED - future]
//
// INPUT BUS MAPPING:
//   residues_in[63:0] is a generic 64-bit bus.
//   For 2NRM: only bits [40:0] are used (41-bit packed residues).
//   For future algorithms: bit ranges will be defined in their respective .vh.
//
// PIPELINE LATENCY:
//   Matches the instantiated decoder's latency.
//   decoder_2nrm: 2 clock cycles (start → valid)
// =============================================================================

`include "decoder_wrapper.vh"
`include "decoder_2nrm.vh"
`timescale 1ns / 1ps

module decoder_wrapper (
    // -------------------------------------------------------------------------
    // Global Clock & Reset
    // -------------------------------------------------------------------------
    input  wire                           clk,
    input  wire                           rst_n,

    // -------------------------------------------------------------------------
    // Control
    // -------------------------------------------------------------------------
    input  wire                           start,
    // start: Single-cycle pulse to begin decoding.
    // All instantiated decoders receive this signal simultaneously.

    input  wire [`DEC_ALGO_BITS-1:0]      algo_id,
    // algo_id: Selects which decoder's output is forwarded.
    //   0 = 2NRM, 1 = 3NRM (reserved), 2 = C-RRNS (reserved), 3 = RS (reserved)

    // -------------------------------------------------------------------------
    // Data Input (Generic 64-bit Bus)
    // -------------------------------------------------------------------------
    input  wire [`DEC_INPUT_BUS_WIDTH-1:0] residues_in,
    // residues_in: Packed residue vector from error injector.
    //   For 2NRM: [40:32]=r257, [31:24]=r256, [23:18]=r61,
    //             [17:12]=r59, [11:6]=r55, [5:0]=r53
    //   Bits [63:41] are unused for 2NRM (zero-padded by encoder).

    // -------------------------------------------------------------------------
    // Data Output
    // -------------------------------------------------------------------------
    output reg  [`DEC_DATA_WIDTH-1:0]     data_out,
    // Decoded 16-bit data. Valid when valid=1.

    output reg                            valid,
    // Asserted HIGH for one cycle when data_out is valid.
    // Reflects the selected algorithm's valid signal.

    output reg                            uncorrectable
    // Asserted HIGH when the selected decoder cannot correct the errors.
    // Meaningful only when valid=1.
);

    // =========================================================================
    // 1. decoder_2nrm Instantiation (algo_id = 0)
    // =========================================================================
    // Input adaptation: 2NRM uses 41-bit packed residues (right-aligned in bus)
    // residues_in[40:0] is passed directly; decoder_2nrm internally unpacks it.

    wire [`DEC_DATA_WIDTH-1:0] dec_2nrm_data;
    wire                       dec_2nrm_valid;
    wire                       dec_2nrm_uncorr;

    decoder_2nrm u_dec_2nrm (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        // Pass full 64-bit bus; decoder_2nrm uses [40:0] internally
        .residues_in  (residues_in),
        .data_out     (dec_2nrm_data),
        .valid        (dec_2nrm_valid),
        .uncorrectable(dec_2nrm_uncorr)
    );

    // =========================================================================
    // 2. Reserved Decoder Placeholders (Future Algorithms)
    // =========================================================================
    // These wires are tied to safe defaults until the respective decoders
    // are implemented. The structure is ready for drop-in instantiation.

    // --- algo_id = 1: 3NRM Decoder (RESERVED) ---
    // TODO: Instantiate decoder_3nrm here when implemented.
    // Expected interface:
    //   decoder_3nrm u_dec_3nrm (
    //       .clk(clk), .rst_n(rst_n), .start(start),
    //       .residues_in(residues_in[47:0]),  // 3NRM uses 48-bit
    //       .data_out(dec_3nrm_data),
    //       .valid(dec_3nrm_valid),
    //       .uncorrectable(dec_3nrm_uncorr)
    //   );
    wire [`DEC_DATA_WIDTH-1:0] dec_3nrm_data  = {`DEC_DATA_WIDTH{1'b0}};
    wire                       dec_3nrm_valid  = 1'b0;
    wire                       dec_3nrm_uncorr = 1'b0;

    // --- algo_id = 2: C-RRNS Decoder (RESERVED) ---
    // TODO: Instantiate decoder_crrns here when implemented.
    // Expected interface:
    //   decoder_crrns u_dec_crrns (
    //       .clk(clk), .rst_n(rst_n), .start(start),
    //       .residues_in(residues_in[60:0]),  // C-RRNS uses 61-bit
    //       .data_out(dec_crrns_data),
    //       .valid(dec_crrns_valid),
    //       .uncorrectable(dec_crrns_uncorr)
    //   );
    wire [`DEC_DATA_WIDTH-1:0] dec_crrns_data  = {`DEC_DATA_WIDTH{1'b0}};
    wire                       dec_crrns_valid  = 1'b0;
    wire                       dec_crrns_uncorr = 1'b0;

    // --- algo_id = 3: RS Decoder (RESERVED) ---
    // TODO: Instantiate decoder_rs here when implemented.
    // Expected interface:
    //   decoder_rs u_dec_rs (
    //       .clk(clk), .rst_n(rst_n), .start(start),
    //       .residues_in(residues_in[47:0]),  // RS uses 48-bit
    //       .data_out(dec_rs_data),
    //       .valid(dec_rs_valid),
    //       .uncorrectable(dec_rs_uncorr)
    //   );
    wire [`DEC_DATA_WIDTH-1:0] dec_rs_data  = {`DEC_DATA_WIDTH{1'b0}};
    wire                       dec_rs_valid  = 1'b0;
    wire                       dec_rs_uncorr = 1'b0;

    // =========================================================================
    // 3. Output Mux: Route Selected Algorithm's Outputs
    // =========================================================================
    // Combinational mux selects the active decoder's outputs based on algo_id.
    // All decoders run in parallel; only the selected one drives the outputs.

    reg [`DEC_DATA_WIDTH-1:0] mux_data;
    reg                       mux_valid;
    reg                       mux_uncorr;

    always @(*) begin
        case (algo_id)
            `DEC_ALGO_2NRM: begin
                mux_data   = dec_2nrm_data;
                mux_valid  = dec_2nrm_valid;
                mux_uncorr = dec_2nrm_uncorr;
            end
            `DEC_ALGO_3NRM: begin
                // 3NRM not yet implemented — output safe defaults
                mux_data   = dec_3nrm_data;
                mux_valid  = dec_3nrm_valid;
                mux_uncorr = dec_3nrm_uncorr;
            end
            `DEC_ALGO_C_RRNS: begin
                // C-RRNS not yet implemented — output safe defaults
                mux_data   = dec_crrns_data;
                mux_valid  = dec_crrns_valid;
                mux_uncorr = dec_crrns_uncorr;
            end
            `DEC_ALGO_RS: begin
                // RS not yet implemented — output safe defaults
                mux_data   = dec_rs_data;
                mux_valid  = dec_rs_valid;
                mux_uncorr = dec_rs_uncorr;
            end
            default: begin
                mux_data   = {`DEC_DATA_WIDTH{1'b0}};
                mux_valid  = 1'b0;
                mux_uncorr = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // 4. Output Registers with Async Reset
    // =========================================================================
    // Register the mux outputs to provide stable, glitch-free outputs to
    // the downstream comparator and statistics modules.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out      <= {`DEC_DATA_WIDTH{1'b0}};
            valid         <= 1'b0;
            uncorrectable <= 1'b0;
        end else begin
            // Forward selected decoder's outputs
            valid         <= mux_valid;
            uncorrectable <= mux_uncorr;

            // Update data_out when the selected decoder produces valid output
            if (mux_valid) begin
                data_out <= mux_data;
            end
            // else: hold previous data_out (don't care when valid=0)
        end
    end

endmodule
