// =============================================================================
// File: encoder_wrapper.v
// Description: Unified Wrapper for Multi-Algorithm Encoder Support
//              Based on Interim Report Parameters (Yuqi Guo, 230184273)
//              Supports: 2NRM (41b), 3NRM (48b), C-RRNS (61b), RS (48b)
// Version: v2.1 (Compile-macro controlled single-algorithm build)
//
// *** IMPORTANT: ONE ALGORITHM PER BUILD ***
//   Each implementation must contain ONLY ONE active encoder instance.
//   This ensures fair resource utilization comparison between algorithms.
//
// BUILD SWITCHING:
//   Edit ONLY src/interfaces/main_scan_fsm.vh
//   Uncomment ONE `define BUILD_ALGO_xxx line, comment out all others.
//   Then run full Implementation in Vivado.
//   See docs/algo_switch_guide.md for details.
// =============================================================================

`include "main_scan_fsm.vh"
`timescale 1ns / 1ps

module encoder_wrapper (
    input  wire       clk,
    input  wire       rst_n,
    
    // Control
    input  wire       start,
    input  wire [2:0] algo_sel,   // 0:2NRM, 1:3NRM, 2:C-RRNS-MLD, 3:C-RRNS-MRC, 4:C-RRNS-CRT, 5:RS
    
    // Data Input (Standardized: Dual 16-bit symbols)
    input  wire [15:0] data_in_A,
    input  wire [15:0] data_in_B,
    
    // Data Output (Standardized: Max width 256-bit per channel)
    output reg  [255:0] codeword_A,
    output reg  [255:0] codeword_B,
    
    // Metadata: Effective bit-length of the codeword (for Error Injector masking)
    // Values based on Report Table 3: 2NRM=41, 3NRM=48, RS=48, C-RRNS=61
    output reg  [7:0]   cw_len_A,
    output reg  [7:0]   cw_len_B,
    
    // Status
    output wire       done
);

    // =========================================================================
    // 1. Algorithm Selection Parameters (3-bit, matches algo_id in decoder_wrapper.vh)
    // =========================================================================
    localparam ALGO_2NRM      = 3'd0;
    localparam ALGO_3NRM      = 3'd1;
    localparam ALGO_CRRNS_MLD = 3'd2;  // C-RRNS-MLD (encoder_crrns shared)
    localparam ALGO_CRRNS_MRC = 3'd3;  // C-RRNS-MRC (encoder_crrns shared)
    localparam ALGO_CRRNS_CRT = 3'd4;  // C-RRNS-CRT (encoder_crrns shared)
    localparam ALGO_RS        = 3'd5;
    // Backward compatibility alias
    localparam ALGO_CRRNS     = 3'd2;

    // =========================================================================
    // 2. Internal Signals for Sub-modules
    // =========================================================================
    // Widths adjusted to match Report Table 3 exactly
    
    // 2NRM: 41 bits -> fit in 64
    wire [63:0] out_2nrm_A, out_2nrm_B;
    wire        done_2nrm;
    
    // 3NRM: 48 bits -> fit in 64
    wire [63:0] out_3nrm_A, out_3nrm_B; 
    wire        done_3nrm;
    
    // C-RRNS: 61 bits -> fit in 64 (barely), use 128 to be safe
    wire [127:0] out_crrns_A, out_crrns_B;
    wire         done_crrns;
    
    // RS: 48 bits -> fit in 64
    wire [63:0] out_rs_A, out_rs_B;
    wire        done_rs;

    // Combined Done
    assign done = done_2nrm | done_3nrm | done_crrns | done_rs;

    // =========================================================================
    // 3. Sub-module Instantiations (controlled by BUILD_ALGO_xxx macros)
    //    Only ONE encoder is instantiated per build.
    //    All others are wire-tied to zero via `else branches.
    // =========================================================================

    // --- 2NRM Encoder ---
`ifdef BUILD_ALGO_2NRM
    encoder_2nrm u_enc_2nrm (
        .clk(clk), .rst_n(rst_n), .start(start),
        .data_in_A(data_in_A), .data_in_B(data_in_B),
        .residues_out_A(out_2nrm_A), .residues_out_B(out_2nrm_B),
        .done(done_2nrm)
    );
`else
    assign out_2nrm_A = 64'd0;
    assign out_2nrm_B = 64'd0;
    assign done_2nrm  = 1'b0;
`endif

    // --- 3NRM Encoder ---
`ifdef BUILD_ALGO_3NRM
    encoder_3nrm u_enc_3nrm (
        .clk(clk), .rst_n(rst_n), .start(start),
        .data_in_A(data_in_A), .data_in_B(data_in_B),
        .residues_out_A(out_3nrm_A), .residues_out_B(out_3nrm_B),
        .done(done_3nrm)
    );
`else
    assign out_3nrm_A = 64'd0;
    assign out_3nrm_B = 64'd0;
    assign done_3nrm  = 1'b0;
`endif

    // --- C-RRNS Encoder (shared by MLD/MRC/CRT) ---
`ifdef BUILD_ALGO_CRRNS_MLD
    `define BUILD_ALGO_CRRNS_ACTIVE
`elsif BUILD_ALGO_CRRNS_MRC
    `define BUILD_ALGO_CRRNS_ACTIVE
`elsif BUILD_ALGO_CRRNS_CRT
    `define BUILD_ALGO_CRRNS_ACTIVE
`endif

`ifdef BUILD_ALGO_CRRNS_ACTIVE
    wire [63:0] out_crrns_A_64;
    wire [63:0] out_crrns_B_64;
    wire        done_crrns_enc;
    encoder_crrns u_enc_crrns (
        .clk(clk), .rst_n(rst_n), .start(start),
        .data_in_A(data_in_A), .data_in_B(data_in_B),
        .residues_out_A(out_crrns_A_64), .residues_out_B(out_crrns_B_64),
        .done(done_crrns_enc)
    );
    assign out_crrns_A = {64'd0, out_crrns_A_64};
    assign out_crrns_B = {64'd0, out_crrns_B_64};
    assign done_crrns  = done_crrns_enc;
`else
    assign out_crrns_A = 128'd0;
    assign out_crrns_B = 128'd0;
    assign done_crrns  = 1'b0;
`endif

    // --- RS Encoder ---
`ifdef BUILD_ALGO_RS
    encoder_rs u_enc_rs (
        .clk(clk), .rst_n(rst_n), .start(start),
        .data_in_A(data_in_A), .data_in_B(data_in_B),
        .residues_out_A(out_rs_A), .residues_out_B(out_rs_B),
        .done(done_rs)
    );
`else
    assign out_rs_A = 64'd0;
    assign out_rs_B = 64'd0;
    assign done_rs  = 1'b0;
`endif

    // =========================================================================
    // 4. Output Multiplexing & Metadata Generation (Report-Aligned)
    // =========================================================================
    // BUG FIX (v1.2): Latch codeword on done=1, NOT on start=1.
    //
    // ROOT CAUSE OF ALL-FAIL RESULTS:
    //   encoder_2nrm uses a registered output (NBA assignment):
    //     always @(posedge clk) if (start) residues_out_A <= packed_a;
    //   At the clock edge when start=1 (cycle T):
    //     - encoder_2nrm.residues_out_A still holds the PREVIOUS result
    //       (the NBA from this cycle takes effect at T+1)
    //     - encoder_wrapper was latching out_2nrm_A at start=1 (cycle T)
    //       → captured the STALE previous result, not the current encoding
    //   At cycle T+1:
    //     - encoder_2nrm.residues_out_A = new correct result (NBA effective)
    //     - encoder_2nrm.done = 1
    //     - out_2nrm_A (wire) = residues_out_A = new correct result ✅
    //   FIX: Latch codeword_A/B when done=1 (cycle T+1), at which point
    //   out_2nrm_A/B (wires) already reflect the new residues_out_A value.
    //
    // DOWNSTREAM ALIGNMENT (auto_scan_engine.v ENC_WAIT state):
    //   auto_scan_engine detects enc_done=1 at cycle T+1 and latches
    //   codeword_a_raw. However, codeword_A (NBA in this block) only becomes
    //   valid at T+2. To resolve this one-cycle gap, auto_scan_engine.v
    //   ENC_WAIT state is modified to wait one extra cycle after enc_done=1
    //   before latching codeword_a_raw (see auto_scan_engine.v ENC_WAIT fix).
    //
    // TIMING SUMMARY:
    //   T+0: start=1, encoder_2nrm begins encoding
    //   T+1: encoder_2nrm.done=1, residues_out_A=new value (NBA effective)
    //        encoder_wrapper latches codeword_A (NBA, effective at T+2)
    //   T+2: encoder_wrapper.codeword_A = new value ✅
    //        auto_scan_engine latches enc_out_a_latch (after 1-cycle wait)

    // Register algo_sel on start so it is stable when done arrives
    reg [2:0] algo_sel_latch;  // 3-bit to match algo_sel port
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) algo_sel_latch <= 3'd0;
        else if (start) algo_sel_latch <= algo_sel;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            codeword_A <= 256'd0;
            codeword_B <= 256'd0;
            cw_len_A   <= 8'd0;
            cw_len_B   <= 8'd0;
        end else if (done) begin
            case (algo_sel_latch)
                ALGO_2NRM: begin
                    codeword_A <= {192'd0, out_2nrm_A[63:0]};
                    codeword_B <= 256'd0;
                    cw_len_A   <= 8'd41;
                    cw_len_B   <= 8'd0;
                end
                ALGO_3NRM: begin
                    codeword_A <= {192'd0, out_3nrm_A[63:0]};
                    codeword_B <= 256'd0;
                    cw_len_A   <= 8'd48;
                    cw_len_B   <= 8'd0;
                end
                ALGO_CRRNS_MLD,
                ALGO_CRRNS_MRC,
                ALGO_CRRNS_CRT: begin
                    // All C-RRNS variants share encoder_crrns (61-bit codeword)
                    codeword_A <= {128'd0, out_crrns_A[127:0]};
                    codeword_B <= 256'd0;
                    cw_len_A   <= 8'd61;
                    cw_len_B   <= 8'd0;
                end
                ALGO_RS: begin
                    codeword_A <= {192'd0, out_rs_A[63:0]};
                    codeword_B <= 256'd0;
                    cw_len_A   <= 8'd48;
                    cw_len_B   <= 8'd0;
                end
                default: begin
                    codeword_A <= 256'd0;
                    codeword_B <= 256'd0;
                    cw_len_A   <= 8'd0;
                    cw_len_B   <= 8'd0;
                end
            endcase
        end
    end

endmodule