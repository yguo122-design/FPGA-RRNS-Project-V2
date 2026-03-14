// =============================================================================
// File: encoder_wrapper.v
// Description: Unified Wrapper for Multi-Algorithm Encoder Support
//              Based on Interim Report Parameters (Yuqi Guo, 230184273)
//              Supports: 2NRM (41b), 3NRM (48b), C-RRNS (61b), RS (48b)
// Version: v1.1 (Updated with exact codeword lengths from Report Table 3)
// =============================================================================

`timescale 1ns / 1ps

module encoder_wrapper (
    input  wire       clk,
    input  wire       rst_n,
    
    // Control
    input  wire       start,
    input  wire [1:0] algo_sel,   // 0: 2NRM, 1: 3NRM, 2: C-RRNS, 3: RS
    
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
    // 1. Algorithm Selection Parameters
    // =========================================================================
    localparam ALGO_2NRM  = 2'd0;
    localparam ALGO_3NRM  = 2'd1;
    localparam ALGO_CRRNS = 2'd2;
    localparam ALGO_RS    = 2'd3;

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
    // 3. Sub-module Instantiations
    // =========================================================================
    
    // --- 2NRM Instance ---
    encoder_2nrm u_enc_2nrm (
        .clk(clk), .rst_n(rst_n), .start(start),
        .data_in_A(data_in_A), .data_in_B(data_in_B),
        .residues_out_A(out_2nrm_A), .residues_out_B(out_2nrm_B),
        .done(done_2nrm)
    );
    
    // --- 3NRM Instance (Placeholder) ---
    // encoder_3nrm u_enc_3nrm (...);
    assign out_3nrm_A = 64'd0; assign out_3nrm_B = 64'd0; assign done_3nrm = 1'b0;

    // --- C-RRNS Instance (Placeholder) ---
    // encoder_crrns u_enc_crrns (...);
    assign out_crrns_A = 128'd0; assign out_crrns_B = 128'd0; assign done_crrns = 1'b0;

    // --- RS Instance (Placeholder) ---
    // encoder_rs u_enc_rs (...);
    assign out_rs_A = 64'd0; assign out_rs_B = 64'd0; assign done_rs = 1'b0;

    // =========================================================================
    // 4. Output Multiplexing & Metadata Generation (Report-Aligned)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            codeword_A <= 256'd0; codeword_B <= 256'd0;
            cw_len_A   <= 8'd0;   cw_len_B   <= 8'd0;
        end else if (start) begin
            case (algo_sel)
                ALGO_2NRM: begin
                    // Report: 41 bits. We use 64-bit container.
                    codeword_A <= {192'd0, out_2nrm_A[63:0]};
                    codeword_B <= {192'd0, out_2nrm_B[63:0]};
                    cw_len_A   <= 8'd41; // Exact valid bits
                    cw_len_B   <= 8'd41;
                end
                
                ALGO_3NRM: begin
                    // Report: 48 bits.
                    codeword_A <= {192'd0, out_3nrm_A[63:0]};
                    codeword_B <= {192'd0, out_3nrm_B[63:0]};
                    cw_len_A   <= 8'd48; 
                    cw_len_B   <= 8'd48;
                end
                
                ALGO_CRRNS: begin
                    // Report: 61 bits.
                    codeword_A <= {128'd0, out_crrns_A[127:0]};
                    codeword_B <= {128'd0, out_crrns_B[127:0]};
                    cw_len_A   <= 8'd61; 
                    cw_len_B   <= 8'd61;
                end
                
                ALGO_RS: begin
                    // Report: 48 bits (n=12, k=4, m=4).
                    codeword_A <= {192'd0, out_rs_A[63:0]};
                    codeword_B <= {192'd0, out_rs_B[63:0]};
                    cw_len_A   <= 8'd48; 
                    cw_len_B   <= 8'd48;
                end
                
                default: begin
                    codeword_A <= 256'd0; codeword_B <= 256'd0;
                    cw_len_A   <= 8'd0;   cw_len_B   <= 8'd0;
                end
            endcase
        end
    end

endmodule