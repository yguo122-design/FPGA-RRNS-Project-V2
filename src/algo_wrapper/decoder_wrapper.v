// =============================================================================
// File: decoder_wrapper.v
// Description: Top-Level Decoder Wrapper with Algorithm Routing
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.3.3
// Version: v2.1 (Compile-macro controlled single-algorithm build)
//
// *** IMPORTANT: ONE ALGORITHM PER BUILD ***
//   Each implementation must contain ONLY ONE active decoder instance.
//   This ensures fair resource utilization comparison between algorithms.
//
// BUILD SWITCHING:
//   Edit ONLY src/interfaces/main_scan_fsm.vh
//   Uncomment ONE `define BUILD_ALGO_xxx line, comment out all others.
//   Then run full Implementation in Vivado.
//   See docs/algo_switch_guide.md for details.
// =============================================================================

`include "decoder_wrapper.vh"
`include "decoder_2nrm.vh"
`include "main_scan_fsm.vh"
`timescale 1ns / 1ps
// Note: decoder_3nrm.v is included in the same project source set.
// No separate `include needed as it defines its own module.

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
    // Decoder Instantiations (controlled by BUILD_ALGO_xxx macros)
    //   Only ONE decoder is instantiated per build.
    //   All others are wire-tied to zero via `else branches.
    // =========================================================================

    // --- 2NRM Decoder ---
`ifdef BUILD_ALGO_2NRM
    wire [`DEC_DATA_WIDTH-1:0] dec_2nrm_data;
    wire                       dec_2nrm_valid;
    wire                       dec_2nrm_uncorr;
    decoder_2nrm u_dec_2nrm (
        .clk(clk), .rst_n(rst_n), .start(start),
        .residues_in(residues_in),
        .data_out(dec_2nrm_data), .valid(dec_2nrm_valid),
        .uncorrectable(dec_2nrm_uncorr)
    );
`else
    wire [`DEC_DATA_WIDTH-1:0] dec_2nrm_data  = {`DEC_DATA_WIDTH{1'b0}};
    wire                       dec_2nrm_valid  = 1'b0;
    wire                       dec_2nrm_uncorr = 1'b0;
`endif

    // --- 3NRM Decoder ---
`ifdef BUILD_ALGO_3NRM
    wire [`DEC_DATA_WIDTH-1:0] dec_3nrm_data;
    wire                       dec_3nrm_valid;
    wire                       dec_3nrm_uncorr;
    decoder_3nrm u_dec_3nrm (
        .clk(clk), .rst_n(rst_n), .start(start),
        .residues_in(residues_in),
        .data_out(dec_3nrm_data), .valid(dec_3nrm_valid),
        .uncorrectable(dec_3nrm_uncorr)
    );
`else
    wire [`DEC_DATA_WIDTH-1:0] dec_3nrm_data  = {`DEC_DATA_WIDTH{1'b0}};
    wire                       dec_3nrm_valid  = 1'b0;
    wire                       dec_3nrm_uncorr = 1'b0;
`endif

    // --- C-RRNS-MLD Decoder ---
`ifdef BUILD_ALGO_CRRNS_MLD
    wire [`DEC_DATA_WIDTH-1:0] dec_crrns_mld_data;
    wire                       dec_crrns_mld_valid;
    wire                       dec_crrns_mld_uncorr;
    decoder_crrns_mld u_dec_crrns_mld (
        .clk(clk), .rst_n(rst_n), .start(start),
        .residues_in(residues_in),
        .data_out(dec_crrns_mld_data), .valid(dec_crrns_mld_valid),
        .uncorrectable(dec_crrns_mld_uncorr)
    );
`else
    wire [`DEC_DATA_WIDTH-1:0] dec_crrns_mld_data  = {`DEC_DATA_WIDTH{1'b0}};
    wire                       dec_crrns_mld_valid  = 1'b0;
    wire                       dec_crrns_mld_uncorr = 1'b0;
`endif

    // --- C-RRNS-MRC Decoder ---
`ifdef BUILD_ALGO_CRRNS_MRC
    wire [`DEC_DATA_WIDTH-1:0] dec_crrns_mrc_data;
    wire                       dec_crrns_mrc_valid;
    wire                       dec_crrns_mrc_uncorr;
    decoder_crrns_mrc u_dec_crrns_mrc (
        .clk(clk), .rst_n(rst_n), .start(start),
        .residues_in(residues_in),
        .data_out(dec_crrns_mrc_data), .valid(dec_crrns_mrc_valid),
        .uncorrectable(dec_crrns_mrc_uncorr)
    );
`else
    wire [`DEC_DATA_WIDTH-1:0] dec_crrns_mrc_data  = {`DEC_DATA_WIDTH{1'b0}};
    wire                       dec_crrns_mrc_valid  = 1'b0;
    wire                       dec_crrns_mrc_uncorr = 1'b0;
`endif

    // --- C-RRNS-CRT Decoder ---
`ifdef BUILD_ALGO_CRRNS_CRT
    wire [`DEC_DATA_WIDTH-1:0] dec_crrns_crt_data;
    wire                       dec_crrns_crt_valid;
    wire                       dec_crrns_crt_uncorr;
    decoder_crrns_crt u_dec_crrns_crt (
        .clk(clk), .rst_n(rst_n), .start(start),
        .residues_in(residues_in),
        .data_out(dec_crrns_crt_data), .valid(dec_crrns_crt_valid),
        .uncorrectable(dec_crrns_crt_uncorr)
    );
`else
    wire [`DEC_DATA_WIDTH-1:0] dec_crrns_crt_data  = {`DEC_DATA_WIDTH{1'b0}};
    wire                       dec_crrns_crt_valid  = 1'b0;
    wire                       dec_crrns_crt_uncorr = 1'b0;
`endif

    // --- RS Decoder ---
`ifdef BUILD_ALGO_RS
    wire [`DEC_DATA_WIDTH-1:0] dec_rs_data;
    wire                       dec_rs_valid;
    wire                       dec_rs_uncorr;
    decoder_rs u_dec_rs (
        .clk(clk), .rst_n(rst_n), .start(start),
        .residues_in(residues_in),
        .data_out(dec_rs_data), .valid(dec_rs_valid),
        .uncorrectable(dec_rs_uncorr)
    );
`else
    wire [`DEC_DATA_WIDTH-1:0] dec_rs_data  = {`DEC_DATA_WIDTH{1'b0}};
    wire                       dec_rs_valid  = 1'b0;
    wire                       dec_rs_uncorr = 1'b0;
`endif

    // --- 2NRM Serial Decoder (Sequential FSM MLD, algo_id=6) ---
`ifdef BUILD_ALGO_2NRM_SERIAL
    wire [`DEC_DATA_WIDTH-1:0] dec_2nrm_serial_data;
    wire                       dec_2nrm_serial_valid;
    wire                       dec_2nrm_serial_uncorr;
    decoder_2nrm_serial u_dec_2nrm_serial (
        .clk(clk), .rst_n(rst_n), .start(start),
        .residues_in(residues_in),
        .data_out(dec_2nrm_serial_data), .valid(dec_2nrm_serial_valid),
        .uncorrectable(dec_2nrm_serial_uncorr)
    );
`else
    wire [`DEC_DATA_WIDTH-1:0] dec_2nrm_serial_data  = {`DEC_DATA_WIDTH{1'b0}};
    wire                       dec_2nrm_serial_valid  = 1'b0;
    wire                       dec_2nrm_serial_uncorr = 1'b0;
`endif

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
                // 3NRM-RRNS decoder (disabled in current build)
                mux_data   = dec_3nrm_data;
                mux_valid  = dec_3nrm_valid;
                mux_uncorr = dec_3nrm_uncorr;
            end
            `DEC_ALGO_CRRNS_MLD: begin
                // C-RRNS-MLD decoder [ACTIVE]
                mux_data   = dec_crrns_mld_data;
                mux_valid  = dec_crrns_mld_valid;
                mux_uncorr = dec_crrns_mld_uncorr;
            end
            `DEC_ALGO_CRRNS_MRC: begin
                // C-RRNS-MRC decoder (reserved)
                mux_data   = dec_crrns_mrc_data;
                mux_valid  = dec_crrns_mrc_valid;
                mux_uncorr = dec_crrns_mrc_uncorr;
            end
            `DEC_ALGO_CRRNS_CRT: begin
                // C-RRNS-CRT decoder (reserved)
                mux_data   = dec_crrns_crt_data;
                mux_valid  = dec_crrns_crt_valid;
                mux_uncorr = dec_crrns_crt_uncorr;
            end
            `DEC_ALGO_RS: begin
                // RS decoder (reserved)
                mux_data   = dec_rs_data;
                mux_valid  = dec_rs_valid;
                mux_uncorr = dec_rs_uncorr;
            end
            `DEC_ALGO_2NRM_SERIAL: begin
                // 2NRM-RRNS Serial FSM decoder (algo_id=6)
                mux_data   = dec_2nrm_serial_data;
                mux_valid  = dec_2nrm_serial_valid;
                mux_uncorr = dec_2nrm_serial_uncorr;
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
