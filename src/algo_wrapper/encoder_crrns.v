// =============================================================================
// File: encoder_crrns.v
// Description: C-RRNS (Traditional RRNS) Encoder
//              Algorithm: Residue Number System with Moduli Set:
//              Non-redundant: {64, 63, 65}
//              Redundant:     {67, 71, 73, 79, 83, 89}
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
// Version: v1.0
//
// CODEWORD FORMAT (61 bits valid, right-aligned in 64-bit bus):
//   [63:61] = 3'b0  (padding)
//   [60:55] = r0 = data_in % 64  (6 bits)
//   [54:49] = r1 = data_in % 63  (6 bits)
//   [48:42] = r2 = data_in % 65  (7 bits)
//   [41:35] = r3 = data_in % 67  (7 bits)
//   [34:28] = r4 = data_in % 71  (7 bits)
//   [27:21] = r5 = data_in % 73  (7 bits)
//   [20:14] = r6 = data_in % 79  (7 bits)
//   [13:7]  = r7 = data_in % 83  (7 bits)
//   [6:0]   = r8 = data_in % 89  (7 bits)
//   Total valid bits: 6+6+7+7+7+7+7+7+7 = 61 bits
//
// PIPELINE: 4 stages, 4-cycle latency
//   Stage E0: Input register
//   Stage E1: r0(% 64), r1(% 63), r2(% 65)
//   Stage E2: r3(% 67), r4(% 71), r5(% 73)
//   Stage E3: r6(% 79), r7(% 83), r8(% 89), pack and output
//
// INTERFACE: Identical to encoder_3nrm.v for drop-in compatibility.
// =============================================================================

`timescale 1ns / 1ps

module encoder_crrns (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [15:0] data_in_A,
    input  wire [15:0] data_in_B,   // Retained for interface compatibility; unused
    output reg  [63:0] residues_out_A,
    output reg  [63:0] residues_out_B,  // Always 64'd0 (single-channel mode)
    output reg         done
);

    // =========================================================================
    // Stage E0: Input Register
    // =========================================================================
    (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_e0;
    (* dont_touch = "true" *) reg start_e0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin data_e0 <= 16'd0; start_e0 <= 1'b0; end
        else begin data_e0 <= data_in_A; start_e0 <= start; end
    end

    // =========================================================================
    // Stage E1: r0(% 64), r1(% 63), r2(% 65)
    // % 64 = direct bit-select [5:0]
    // % 63: 64 ≡ 1 (mod 63), x = 64*x_hi + x_lo => x%63 = (x_hi+x_lo)%63
    // % 65: 64 ≡ -1 (mod 65), x%65 = (x_lo - x_hi + 65*16)%65
    // =========================================================================
    wire [5:0]  r0_e1_comb = data_e0[5:0];
    wire [10:0] r1_step1   = {1'b0, data_e0[15:6]} + {5'b0, data_e0[5:0]};
    wire [5:0]  r1_e1_comb = r1_step1 % 6'd63;
    wire [10:0] r2_step1   = {5'b0, data_e0[5:0]} + 11'd1040 - {1'b0, data_e0[15:6]};
    wire [6:0]  r2_e1_comb = r2_step1 % 7'd65;

    (* dont_touch = "true" *) reg [5:0]  r0_e1;
    (* dont_touch = "true" *) reg [5:0]  r1_e1;
    (* dont_touch = "true" *) reg [6:0]  r2_e1;
    (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_e1;
    (* dont_touch = "true" *) reg start_e1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin r0_e1<=6'd0; r1_e1<=6'd0; r2_e1<=7'd0; data_e1<=16'd0; start_e1<=1'b0; end
        else begin r0_e1<=r0_e1_comb; r1_e1<=r1_e1_comb; r2_e1<=r2_e1_comb; data_e1<=data_e0; start_e1<=start_e0; end
    end

    // =========================================================================
    // Stage E2: r3(% 67), r4(% 71), r5(% 73)
    // All direct % on 16-bit input (synthesizable, ~8 LUT levels)
    // =========================================================================
    wire [6:0] r3_e2_comb = data_e1 % 7'd67;
    wire [6:0] r4_e2_comb = data_e1 % 7'd71;
    wire [6:0] r5_e2_comb = data_e1 % 7'd73;

    (* dont_touch = "true" *) reg [5:0]  r0_e2;
    (* dont_touch = "true" *) reg [5:0]  r1_e2;
    (* dont_touch = "true" *) reg [6:0]  r2_e2;
    (* dont_touch = "true" *) reg [6:0]  r3_e2;
    (* dont_touch = "true" *) reg [6:0]  r4_e2;
    (* dont_touch = "true" *) reg [6:0]  r5_e2;
    (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_e2;
    (* dont_touch = "true" *) reg start_e2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r0_e2<=6'd0; r1_e2<=6'd0; r2_e2<=7'd0;
            r3_e2<=7'd0; r4_e2<=7'd0; r5_e2<=7'd0;
            data_e2<=16'd0; start_e2<=1'b0;
        end else begin
            r0_e2<=r0_e1; r1_e2<=r1_e1; r2_e2<=r2_e1;
            r3_e2<=r3_e2_comb; r4_e2<=r4_e2_comb; r5_e2<=r5_e2_comb;
            data_e2<=data_e1; start_e2<=start_e1;
        end
    end

    // =========================================================================
    // Stage E3: r6(% 79), r7(% 83), r8(% 89), pack and output
    // =========================================================================
    wire [6:0] r6_e3_comb = data_e2 % 7'd79;
    wire [6:0] r7_e3_comb = data_e2 % 7'd83;
    wire [6:0] r8_e3_comb = data_e2 % 7'd89;

    // Pack 61-bit codeword (right-aligned in 64-bit bus)
    wire [63:0] packed_a = {
        3'd0,           // [63:61] padding
        r0_e2,          // [60:55] r0 = % 64 (6 bits)
        r1_e2,          // [54:49] r1 = % 63 (6 bits)
        r2_e2,          // [48:42] r2 = % 65 (7 bits)
        r3_e2,          // [41:35] r3 = % 67 (7 bits)
        r4_e2,          // [34:28] r4 = % 71 (7 bits)
        r5_e2,          // [27:21] r5 = % 73 (7 bits)
        r6_e3_comb,     // [20:14] r6 = % 79 (7 bits)
        r7_e3_comb,     // [13:7]  r7 = % 83 (7 bits)
        r8_e3_comb      // [6:0]   r8 = % 89 (7 bits)
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin residues_out_A <= 64'd0; residues_out_B <= 64'd0; done <= 1'b0; end
        else begin
            done <= 1'b0;
            if (start_e2) begin
                residues_out_A <= packed_a;
                residues_out_B <= 64'd0;
                done           <= 1'b1;
            end
        end
    end

endmodule
