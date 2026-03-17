// =============================================================================
// File: encoder_2nrm.v
// Description: 2NRM Encoder supporting Dual-Channel Parallel Processing
//              Algorithm: Residue Number System (RNS) with Moduli Set:
//              {257, 256, 61, 59, 55, 53}
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Corresponds to Section 2.3.3.3 of Top-Level Design Document
// Version: v2.0 (Upgraded for 32-bit PRBS Interface: 2x16-bit symbols)
// =============================================================================

`timescale 1ns / 1ps

module encoder_2nrm (
    input  wire       clk,
    input  wire       rst_n,
    
    // Control: Start encoding for BOTH channels simultaneously
    input  wire       start,
    
    // Inputs: Two independent 16-bit symbols from PRBS Generator
    // Symbol A: data_in[31:16] from PRBS
    // Symbol B: data_in[15:0]  from PRBS
    input  wire [15:0] data_in_A,
    input  wire [15:0] data_in_B,
    
    // Outputs: Two independent 64-bit residue vectors
    // Each vector contains 6 residues packed into 64 bits
    output reg  [63:0] residues_out_A,
    output reg  [63:0] residues_out_B,
    
    // Status: High for one cycle when results are valid
    output reg        done
);

    // =========================================================================
    // 1. Parameters & Constants
    // =========================================================================
    // Moduli Set
    localparam M1 = 32'd257;
    localparam M2 = 32'd256;
    localparam M3 = 32'd61;
    localparam M4 = 32'd59;
    localparam M5 = 32'd55;
    localparam M6 = 32'd53;

    // Residue Bit Widths
    localparam W1 = 9; // ceil(log2(257))
    localparam W2 = 8; // log2(256)
    localparam W3 = 6; // ceil(log2(61))
    localparam W4 = 6; // ceil(log2(59))
    localparam W5 = 6; // ceil(log2(55))
    localparam W6 = 6; // ceil(log2(53))
    
    // Total Used Bits: 9+8+6+6+6+6 = 41 bits. 
    // We pack into 64 bits for alignment. 
    // Layout: {Reserved(23), R1(9), R2(8), R3(6), R4(6), R5(6), R6(6)}


    // =========================================================================
    // 3. Combinational Logic: Residue Calculation (Channel A)
    // =========================================================================
    wire [31:0] r1_a, r2_a, r3_a, r4_a, r5_a, r6_a;
    
    assign r1_a = data_in_A % M1;
    assign r2_a = data_in_A % M2;
    assign r3_a = data_in_A % M3;
    assign r4_a = data_in_A % M4;
    assign r5_a = data_in_A % M5;
    assign r6_a = data_in_A % M6;

    // Packing Channel A
    wire [63:0] packed_a;
    assign packed_a = {
        23'd0,          // Reserved / Padding to align to 64-bit
        r1_a[W1-1:0],   // 9 bits
        r2_a[W2-1:0],   // 8 bits
        r3_a[W3-1:0],   // 6 bits
        r4_a[W4-1:0],   // 6 bits
        r5_a[W5-1:0],   // 6 bits
        r6_a[W6-1:0]    // 6 bits
    };

    // =========================================================================
    // 4. Combinational Logic: Residue Calculation (Channel B)
    // =========================================================================
    wire [31:0] r1_b, r2_b, r3_b, r4_b, r5_b, r6_b;
    
    assign r1_b = data_in_B % M1;
    assign r2_b = data_in_B % M2;
    assign r3_b = data_in_B % M3;
    assign r4_b = data_in_B % M4;
    assign r5_b = data_in_B % M5;
    assign r6_b = data_in_B % M6;

    // Packing Channel B
    wire [63:0] packed_b;
    assign packed_b = {
        23'd0,          // Reserved / Padding
        r1_b[W1-1:0],
        r2_b[W2-1:0],
        r3_b[W3-1:0],
        r4_b[W4-1:0],
        r5_b[W5-1:0],
        r6_b[W6-1:0]
    };

    // =========================================================================
    // 5. Sequential Output Register
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            residues_out_A <= 64'd0;
            residues_out_B <= 64'd0;
            done           <= 1'b0;
        end else begin
            done <= 1'b0; // Default deassert
            
            if (start) begin
                // Capture both channels simultaneously
                residues_out_A <= packed_a;
                residues_out_B <= packed_b;
                done           <= 1'b1; // Pulse high for one cycle
            end
            // Else: Hold previous values (optional, depending on downstream needs)
        end
    end

endmodule