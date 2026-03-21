// =============================================================================
// File: encoder_2nrm.v
// Description: 2NRM Encoder - Single-Channel Mode (Channel A only)
//              Algorithm: Residue Number System (RNS) with Moduli Set:
//              {257, 256, 61, 59, 55, 53}
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Corresponds to Section 2.3.3.3 of Top-Level Design Document
// Version: v2.4 (Single-Channel Simplification: Channel B disabled)
//
// SINGLE-CHANNEL MODE (v2.4):
//   Channel B pipeline is fully commented out to simplify debugging.
//   data_in_B port is retained for interface compatibility but ignored internally.
//   residues_out_B is driven to 64'd0.
//   All _b pipeline registers and computations are commented out.
//
// TIMING FIX (Bug #53):
//   timing10.csv showed logic delay 5.26-5.35ns on encoder Stage E2/E3 paths.
//   FIX: Apply 2-step decomposition with register isolation to all 4 moduli
//   that have logic depth > 5ns (% 61, % 59, % 55, % 53).
//   Final encoder pipeline (v2.3):
//     Stage E0:  Register data_in_A (max_fanout=8)
//     Stage E1:  % 257, % 256 → register
//     Stage E2a: step1_61 = x_hi*12+x_lo, step1_59 = x_hi*20+x_lo → register
//     Stage E2b: step1_61 % 61, step1_59 % 59 → register
//     Stage E3a: step1_55 = x_hi*36+x_lo, step1_53 = x_hi*44+x_lo → register
//     Stage E3b: step1_55 % 55, step1_53 % 53 → register, merge all results
//   Total encoder latency: 6 cycles
// =============================================================================

`timescale 1ns / 1ps

module encoder_2nrm (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [15:0] data_in_A,
    input  wire [15:0] data_in_B,   // Retained for interface compatibility; unused in single-channel mode
    output reg  [63:0] residues_out_A,
    output reg  [63:0] residues_out_B,  // Always 64'd0 in single-channel mode
    output reg        done
);

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam M1 = 32'd257;
    localparam M2 = 32'd256;
    localparam M3 = 32'd61;
    localparam M4 = 32'd59;
    localparam M5 = 32'd55;
    localparam M6 = 32'd53;

    localparam W1 = 9;  // ceil(log2(257))
    localparam W2 = 8;  // log2(256)
    localparam W3 = 6;  // ceil(log2(61))
    localparam W4 = 6;  // ceil(log2(59))
    localparam W5 = 6;  // ceil(log2(55))
    localparam W6 = 6;  // ceil(log2(53))

    // =========================================================================
    // Stage E0: Input Register (Channel A only)
    // =========================================================================
    (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_in_A_e0;
    // (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_in_B_e0;  // SINGLE-CHANNEL: disabled
    (* dont_touch = "true" *) reg start_e0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_in_A_e0 <= 16'd0;
            // data_in_B_e0 <= 16'd0;  // SINGLE-CHANNEL: disabled
            start_e0 <= 1'b0;
        end else begin
            data_in_A_e0 <= data_in_A;
            // data_in_B_e0 <= data_in_B;  // SINGLE-CHANNEL: disabled
            start_e0 <= start;
        end
    end

    // =========================================================================
    // Stage E1: Compute % 257, % 256 (Channel A only)
    // =========================================================================
    wire [8:0] r1_a_comb = data_in_A_e0 % M1;  // % 257
    wire [7:0] r2_a_comb = data_in_A_e0 % M2;  // % 256
    // wire [8:0] r1_b_comb = data_in_B_e0 % M1;  // SINGLE-CHANNEL: disabled
    // wire [7:0] r2_b_comb = data_in_B_e0 % M2;  // SINGLE-CHANNEL: disabled

    (* dont_touch = "true" *) reg [8:0] r1_a_e1;
    (* dont_touch = "true" *) reg [7:0] r2_a_e1;
    // (* dont_touch = "true" *) reg [8:0] r1_b_e1;  // SINGLE-CHANNEL: disabled
    // (* dont_touch = "true" *) reg [7:0] r2_b_e1;  // SINGLE-CHANNEL: disabled
    (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_in_A_e1;
    // (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_in_B_e1;  // SINGLE-CHANNEL: disabled
    (* dont_touch = "true" *) reg start_e1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1_a_e1 <= 9'd0; r2_a_e1 <= 8'd0;
            // r1_b_e1 <= 9'd0; r2_b_e1 <= 8'd0;  // SINGLE-CHANNEL: disabled
            data_in_A_e1 <= 16'd0;
            // data_in_B_e1 <= 16'd0;  // SINGLE-CHANNEL: disabled
            start_e1 <= 1'b0;
        end else begin
            r1_a_e1 <= r1_a_comb; r2_a_e1 <= r2_a_comb;
            // r1_b_e1 <= r1_b_comb; r2_b_e1 <= r2_b_comb;  // SINGLE-CHANNEL: disabled
            data_in_A_e1 <= data_in_A_e0;
            // data_in_B_e1 <= data_in_B_e0;  // SINGLE-CHANNEL: disabled
            start_e1 <= start_e0;
        end
    end

    // =========================================================================
    // Stage E2a: Compute step1 for % 61 and % 59 (Channel A only)
    // =========================================================================
    wire [11:0] step1_61_a_comb = ({4'd0, data_in_A_e1[15:8]} * 12'd12) + {4'd0, data_in_A_e1[7:0]};
    wire [12:0] step1_59_a_comb = ({5'd0, data_in_A_e1[15:8]} * 13'd20) + {5'd0, data_in_A_e1[7:0]};
    // wire [11:0] step1_61_b_comb = ({4'd0, data_in_B_e1[15:8]} * 12'd12) + {4'd0, data_in_B_e1[7:0]};  // SINGLE-CHANNEL: disabled
    // wire [12:0] step1_59_b_comb = ({5'd0, data_in_B_e1[15:8]} * 13'd20) + {5'd0, data_in_B_e1[7:0]};  // SINGLE-CHANNEL: disabled

    (* dont_touch = "true" *) reg [8:0]  r1_a_e2a;
    (* dont_touch = "true" *) reg [7:0]  r2_a_e2a;
    // (* dont_touch = "true" *) reg [8:0]  r1_b_e2a;  // SINGLE-CHANNEL: disabled
    // (* dont_touch = "true" *) reg [7:0]  r2_b_e2a;  // SINGLE-CHANNEL: disabled
    (* dont_touch = "true" *) reg [11:0] step1_61_a_reg;
    (* dont_touch = "true" *) reg [12:0] step1_59_a_reg;
    // (* dont_touch = "true" *) reg [11:0] step1_61_b_reg;  // SINGLE-CHANNEL: disabled
    // (* dont_touch = "true" *) reg [12:0] step1_59_b_reg;  // SINGLE-CHANNEL: disabled
    (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_in_A_e2a;
    // (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_in_B_e2a;  // SINGLE-CHANNEL: disabled
    (* dont_touch = "true" *) reg start_e2a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1_a_e2a <= 9'd0; r2_a_e2a <= 8'd0;
            // r1_b_e2a <= 9'd0; r2_b_e2a <= 8'd0;  // SINGLE-CHANNEL: disabled
            step1_61_a_reg <= 12'd0; step1_59_a_reg <= 13'd0;
            // step1_61_b_reg <= 12'd0; step1_59_b_reg <= 13'd0;  // SINGLE-CHANNEL: disabled
            data_in_A_e2a <= 16'd0;
            // data_in_B_e2a <= 16'd0;  // SINGLE-CHANNEL: disabled
            start_e2a <= 1'b0;
        end else begin
            r1_a_e2a <= r1_a_e1; r2_a_e2a <= r2_a_e1;
            // r1_b_e2a <= r1_b_e1; r2_b_e2a <= r2_b_e1;  // SINGLE-CHANNEL: disabled
            step1_61_a_reg <= step1_61_a_comb;
            step1_59_a_reg <= step1_59_a_comb;
            // step1_61_b_reg <= step1_61_b_comb;  // SINGLE-CHANNEL: disabled
            // step1_59_b_reg <= step1_59_b_comb;  // SINGLE-CHANNEL: disabled
            data_in_A_e2a <= data_in_A_e1;
            // data_in_B_e2a <= data_in_B_e1;  // SINGLE-CHANNEL: disabled
            start_e2a <= start_e1;
        end
    end

    // =========================================================================
    // Stage E2b: Compute step1 % 61 and step1 % 59 (Channel A only)
    // =========================================================================
    wire [5:0] r3_a_comb = step1_61_a_reg % M3;  // % 61 (12-bit input)
    wire [5:0] r4_a_comb = step1_59_a_reg % M4;  // % 59 (13-bit input)
    // wire [5:0] r3_b_comb = step1_61_b_reg % M3;  // SINGLE-CHANNEL: disabled
    // wire [5:0] r4_b_comb = step1_59_b_reg % M4;  // SINGLE-CHANNEL: disabled

    (* dont_touch = "true" *) reg [8:0] r1_a_e2b;
    (* dont_touch = "true" *) reg [7:0] r2_a_e2b;
    (* dont_touch = "true" *) reg [5:0] r3_a_e2b;
    (* dont_touch = "true" *) reg [5:0] r4_a_e2b;
    // (* dont_touch = "true" *) reg [8:0] r1_b_e2b;  // SINGLE-CHANNEL: disabled
    // (* dont_touch = "true" *) reg [7:0] r2_b_e2b;  // SINGLE-CHANNEL: disabled
    // (* dont_touch = "true" *) reg [5:0] r3_b_e2b;  // SINGLE-CHANNEL: disabled
    // (* dont_touch = "true" *) reg [5:0] r4_b_e2b;  // SINGLE-CHANNEL: disabled
    (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_in_A_e2b;
    // (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_in_B_e2b;  // SINGLE-CHANNEL: disabled
    (* dont_touch = "true" *) reg start_e2b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1_a_e2b <= 9'd0; r2_a_e2b <= 8'd0;
            r3_a_e2b <= 6'd0; r4_a_e2b <= 6'd0;
            // r1_b_e2b <= 9'd0; r2_b_e2b <= 8'd0;  // SINGLE-CHANNEL: disabled
            // r3_b_e2b <= 6'd0; r4_b_e2b <= 6'd0;  // SINGLE-CHANNEL: disabled
            data_in_A_e2b <= 16'd0;
            // data_in_B_e2b <= 16'd0;  // SINGLE-CHANNEL: disabled
            start_e2b <= 1'b0;
        end else begin
            r1_a_e2b <= r1_a_e2a; r2_a_e2b <= r2_a_e2a;
            r3_a_e2b <= r3_a_comb; r4_a_e2b <= r4_a_comb;
            // r1_b_e2b <= r1_b_e2a; r2_b_e2b <= r2_b_e2a;  // SINGLE-CHANNEL: disabled
            // r3_b_e2b <= r3_b_comb; r4_b_e2b <= r4_b_comb;  // SINGLE-CHANNEL: disabled
            data_in_A_e2b <= data_in_A_e2a;
            // data_in_B_e2b <= data_in_B_e2a;  // SINGLE-CHANNEL: disabled
            start_e2b <= start_e2a;
        end
    end

    // =========================================================================
    // Stage E3a: Compute step1 for % 55 and % 53 (Channel A only)
    // =========================================================================
    wire [13:0] step1_55_a_comb = ({6'd0, data_in_A_e2b[15:8]} * 14'd36) + {6'd0, data_in_A_e2b[7:0]};
    wire [13:0] step1_53_a_comb = ({6'd0, data_in_A_e2b[15:8]} * 14'd44) + {6'd0, data_in_A_e2b[7:0]};
    // wire [13:0] step1_55_b_comb = ({6'd0, data_in_B_e2b[15:8]} * 14'd36) + {6'd0, data_in_B_e2b[7:0]};  // SINGLE-CHANNEL: disabled
    // wire [13:0] step1_53_b_comb = ({6'd0, data_in_B_e2b[15:8]} * 14'd44) + {6'd0, data_in_B_e2b[7:0]};  // SINGLE-CHANNEL: disabled

    (* dont_touch = "true" *) reg [8:0]  r1_a_e3a;
    (* dont_touch = "true" *) reg [7:0]  r2_a_e3a;
    (* dont_touch = "true" *) reg [5:0]  r3_a_e3a;
    (* dont_touch = "true" *) reg [5:0]  r4_a_e3a;
    // (* dont_touch = "true" *) reg [8:0]  r1_b_e3a;  // SINGLE-CHANNEL: disabled
    // (* dont_touch = "true" *) reg [7:0]  r2_b_e3a;  // SINGLE-CHANNEL: disabled
    // (* dont_touch = "true" *) reg [5:0]  r3_b_e3a;  // SINGLE-CHANNEL: disabled
    // (* dont_touch = "true" *) reg [5:0]  r4_b_e3a;  // SINGLE-CHANNEL: disabled
    (* dont_touch = "true" *) reg [13:0] step1_55_a_reg;
    (* dont_touch = "true" *) reg [13:0] step1_53_a_reg;
    // (* dont_touch = "true" *) reg [13:0] step1_55_b_reg;  // SINGLE-CHANNEL: disabled
    // (* dont_touch = "true" *) reg [13:0] step1_53_b_reg;  // SINGLE-CHANNEL: disabled
    (* dont_touch = "true" *) reg start_e3a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1_a_e3a <= 9'd0; r2_a_e3a <= 8'd0;
            r3_a_e3a <= 6'd0; r4_a_e3a <= 6'd0;
            // r1_b_e3a <= 9'd0; r2_b_e3a <= 8'd0;  // SINGLE-CHANNEL: disabled
            // r3_b_e3a <= 6'd0; r4_b_e3a <= 6'd0;  // SINGLE-CHANNEL: disabled
            step1_55_a_reg <= 14'd0; step1_53_a_reg <= 14'd0;
            // step1_55_b_reg <= 14'd0; step1_53_b_reg <= 14'd0;  // SINGLE-CHANNEL: disabled
            start_e3a <= 1'b0;
        end else begin
            r1_a_e3a <= r1_a_e2b; r2_a_e3a <= r2_a_e2b;
            r3_a_e3a <= r3_a_e2b; r4_a_e3a <= r4_a_e2b;
            // r1_b_e3a <= r1_b_e2b; r2_b_e3a <= r2_b_e2b;  // SINGLE-CHANNEL: disabled
            // r3_b_e3a <= r3_b_e2b; r4_b_e3a <= r4_b_e2b;  // SINGLE-CHANNEL: disabled
            step1_55_a_reg <= step1_55_a_comb;
            step1_53_a_reg <= step1_53_a_comb;
            // step1_55_b_reg <= step1_55_b_comb;  // SINGLE-CHANNEL: disabled
            // step1_53_b_reg <= step1_53_b_comb;  // SINGLE-CHANNEL: disabled
            start_e3a <= start_e2b;
        end
    end

    // =========================================================================
    // Stage E3b: Compute step1 % 55 and step1 % 53, merge all results
    //   Channel A only. residues_out_B is driven to 64'd0.
    // =========================================================================
    wire [5:0] r5_a_comb = step1_55_a_reg % M5;  // % 55 (14-bit input)
    wire [5:0] r6_a_comb = step1_53_a_reg % M6;  // % 53 (14-bit input)
    // wire [5:0] r5_b_comb = step1_55_b_reg % M5;  // SINGLE-CHANNEL: disabled
    // wire [5:0] r6_b_comb = step1_53_b_reg % M6;  // SINGLE-CHANNEL: disabled

    // Pack all residues for Channel A: {Reserved(23), R1(9), R2(8), R3(6), R4(6), R5(6), R6(6)}
    wire [63:0] packed_a = {
        23'd0,
        r1_a_e3a[W1-1:0],  // % 257 (9 bits)
        r2_a_e3a[W2-1:0],  // % 256 (8 bits)
        r3_a_e3a[W3-1:0],  // % 61  (6 bits)
        r4_a_e3a[W4-1:0],  // % 59  (6 bits)
        r5_a_comb[W5-1:0], // % 55  (6 bits)
        r6_a_comb[W6-1:0]  // % 53  (6 bits)
    };

    // Channel B output disabled (single-channel mode)
    // wire [63:0] packed_b = { 23'd0, r1_b_e3a[W1-1:0], r2_b_e3a[W2-1:0],
    //     r3_b_e3a[W3-1:0], r4_b_e3a[W4-1:0], r5_b_comb[W5-1:0], r6_b_comb[W6-1:0] };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            residues_out_A <= 64'd0;
            residues_out_B <= 64'd0;  // Always 0 in single-channel mode
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start_e3a) begin
                residues_out_A <= packed_a;
                residues_out_B <= 64'd0;  // SINGLE-CHANNEL: Channel B output disabled
                done           <= 1'b1;
            end
        end
    end

endmodule
