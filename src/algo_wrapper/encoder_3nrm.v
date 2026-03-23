// =============================================================================
// File: encoder_3nrm.v
// Description: 3NRM-RRNS Encoder
//              Algorithm: Residue Number System with Moduli Set:
//              Non-redundant: {64, 63, 65}
//              Redundant:     {31, 29, 23, 19, 17, 11}
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
// Version: v1.0
//
// CODEWORD FORMAT (48 bits valid, right-aligned in 64-bit bus):
//   [63:48] = 16'b0  (padding, unused)
//   [47:42] = r1 = data_in % 64   (6 bits)
//   [41:36] = r2 = data_in % 63   (6 bits)
//   [35:29] = r3 = data_in % 65   (7 bits)
//   [28:24] = r4 = data_in % 31   (5 bits)
//   [23:19] = r5 = data_in % 29   (5 bits)
//   [18:14] = r6 = data_in % 23   (5 bits)
//   [13:9]  = r7 = data_in % 19   (5 bits)
//   [8:4]   = r8 = data_in % 17   (5 bits)
//   [3:0]   = r9 = data_in % 11   (4 bits)
//   Total valid bits: 6+6+7+5+5+5+5+5+4 = 48 bits
//
// PIPELINE STRUCTURE (4 stages, 4-cycle latency):
//   Stage E0: Input register (data_in_A latched)
//   Stage E1: Compute r1(% 64), r2(% 63), r3(% 65)
//   Stage E2: Compute r4(% 31), r5(% 29), r6(% 23)
//   Stage E3: Compute r7(% 19), r8(% 17), r9(% 11), pack and output
//
// TIMING NOTES:
//   % 64  = data_in[5:0]  (direct bit-select, zero delay)
//   % 63  = 6-bit result, uses 2-step: sum of 6-bit groups
//   % 65  = 7-bit result, uses alternating-sign sum of 6-bit groups
//   % 31  = 5-bit result, uses sum of 5-bit groups
//   % 29, % 23, % 19, % 17, % 11 = small moduli, direct % on 16-bit input
//   All modulo operations on 16-bit input are synthesizable and meet 100MHz.
//
// INTERFACE: Matches encoder_2nrm.v for drop-in compatibility with
//            encoder_wrapper.v (single-channel mode, Channel B = 0).
// =============================================================================

`timescale 1ns / 1ps

module encoder_3nrm (
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
        if (!rst_n) begin
            data_e0  <= 16'd0;
            start_e0 <= 1'b0;
        end else begin
            data_e0  <= data_in_A;
            start_e0 <= start;
        end
    end

    // =========================================================================
    // Stage E1: Compute r1(% 64), r2(% 63), r3(% 65)
    //
    // % 64  : direct bit-select, data_e0[5:0]
    // % 63  : Use identity: x = 64*x_hi + x_lo => x % 63 = (x_hi + x_lo) % 63
    //         since 64 ≡ 1 (mod 63).
    //         For 16-bit input: x_hi = x[15:6] (10 bits), x_lo = x[5:0] (6 bits)
    //         sum = x_hi + x_lo, max = 1023 + 63 = 1086 (11 bits)
    //         Then sum % 63 (11-bit input, small modulo, fast)
    // % 65  : Use identity: 64 ≡ -1 (mod 65), so x = 64*x_hi + x_lo
    //         x % 65 = (-x_hi + x_lo) % 65 = (x_lo - x_hi + 65*k) % 65
    //         For 16-bit: x_hi = x[15:6], x_lo = x[5:0]
    //         diff = x_lo - x_hi + 65*16 = x_lo - x_hi + 1040 (always positive)
    //         Then diff % 65 (11-bit input)
    // =========================================================================

    // r1: % 64 = direct bit-select (combinational, no delay)
    wire [5:0] r1_e1_comb = data_e0[5:0];

    // r2: % 63 using 2-step decomposition
    // Step 1: sum = x[15:6] + x[5:0] (10-bit + 6-bit = 11-bit max)
    wire [10:0] r2_step1 = {1'b0, data_e0[15:6]} + {5'b0, data_e0[5:0]};
    // Step 2: sum % 63 (11-bit input, max 1086)
    // 1086 / 63 = 17.2, so at most 17 subtractions. Use direct % (synthesizable on 11-bit)
    wire [5:0] r2_e1_comb = r2_step1 % 6'd63;

    // r3: % 65 using alternating-sign decomposition
    // 64 ≡ -1 (mod 65), so x % 65 = (x_lo - x_hi + 65*ceil) % 65
    // x_hi = x[15:6] (10 bits, max 1023), x_lo = x[5:0] (6 bits, max 63)
    // To keep positive: add 65*16=1040 (since x_hi max=1023 < 1040)
    // diff = x_lo + 1040 - x_hi, range: [1040-1023, 63+1040] = [17, 1103]
    wire [10:0] r3_step1 = {5'b0, data_e0[5:0]} + 11'd1040 - {1'b0, data_e0[15:6]};
    wire [6:0] r3_e1_comb = r3_step1 % 7'd65;

    // Pipeline registers for Stage E1
    (* dont_touch = "true" *) reg [5:0]  r1_e1;
    (* dont_touch = "true" *) reg [5:0]  r2_e1;
    (* dont_touch = "true" *) reg [6:0]  r3_e1;
    (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_e1;
    (* dont_touch = "true" *) reg start_e1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1_e1    <= 6'd0;
            r2_e1    <= 6'd0;
            r3_e1    <= 7'd0;
            data_e1  <= 16'd0;
            start_e1 <= 1'b0;
        end else begin
            r1_e1    <= r1_e1_comb;
            r2_e1    <= r2_e1_comb;
            r3_e1    <= r3_e1_comb;
            data_e1  <= data_e0;
            start_e1 <= start_e0;
        end
    end

    // =========================================================================
    // Stage E2: Compute r4(% 31), r5(% 29), r6(% 23)
    //
    // For 16-bit input (max 65535):
    // % 31: Use 5-bit group sum. 32 ≡ 1 (mod 31), so x = 32*x_hi + x_lo
    //       x % 31 = (x_hi + x_lo) % 31
    //       x_hi = x[15:5] (11 bits), x_lo = x[4:0] (5 bits)
    //       sum = x_hi + x_lo, max = 2047 + 31 = 2078 (12 bits)
    //       Then sum % 31 (12-bit input, synthesizable)
    // % 29: Direct % on 16-bit input (synthesizable, ~8 LUT levels)
    // % 23: Direct % on 16-bit input (synthesizable, ~8 LUT levels)
    // =========================================================================

    // r4: % 31 using 2-step decomposition
    wire [11:0] r4_step1 = {1'b0, data_e1[15:5]} + {7'b0, data_e1[4:0]};
    wire [4:0] r4_e2_comb = r4_step1 % 5'd31;

    // r5: % 29 direct (16-bit input)
    wire [4:0] r5_e2_comb = data_e1 % 5'd29;

    // r6: % 23 direct (16-bit input)
    wire [4:0] r6_e2_comb = data_e1 % 5'd23;

    // Pipeline registers for Stage E2
    (* dont_touch = "true" *) reg [5:0]  r1_e2;
    (* dont_touch = "true" *) reg [5:0]  r2_e2;
    (* dont_touch = "true" *) reg [6:0]  r3_e2;
    (* dont_touch = "true" *) reg [4:0]  r4_e2;
    (* dont_touch = "true" *) reg [4:0]  r5_e2;
    (* dont_touch = "true" *) reg [4:0]  r6_e2;
    (* dont_touch = "true", max_fanout = 8 *) reg [15:0] data_e2;
    (* dont_touch = "true" *) reg start_e2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1_e2    <= 6'd0;
            r2_e2    <= 6'd0;
            r3_e2    <= 7'd0;
            r4_e2    <= 5'd0;
            r5_e2    <= 5'd0;
            r6_e2    <= 5'd0;
            data_e2  <= 16'd0;
            start_e2 <= 1'b0;
        end else begin
            r1_e2    <= r1_e1;
            r2_e2    <= r2_e1;
            r3_e2    <= r3_e1;
            r4_e2    <= r4_e2_comb;
            r5_e2    <= r5_e2_comb;
            r6_e2    <= r6_e2_comb;
            data_e2  <= data_e1;
            start_e2 <= start_e1;
        end
    end

    // =========================================================================
    // Stage E3: Compute r7(% 19), r8(% 17), r9(% 11), pack and output
    //
    // % 19: Direct % on 16-bit input (synthesizable)
    // % 17: Use 4-bit alternating-sign sum. 16 ≡ -1 (mod 17)
    //       x = 16*x_hi + x_lo => x % 17 = (-x_hi + x_lo) % 17
    //       x_hi = x[15:4] (12 bits), x_lo = x[3:0] (4 bits)
    //       diff = x_lo - x_hi + 17*k (keep positive)
    //       x_hi max = 4095, 17*241 = 4097 > 4095, so add 17*241=4097
    //       diff = x_lo + 4097 - x_hi, range [4097-4095, 15+4097] = [2, 4112]
    //       Then diff % 17 (13-bit input, synthesizable)
    // % 11: Direct % on 16-bit input (synthesizable)
    // =========================================================================

    // r7: % 19 direct (16-bit input)
    wire [4:0] r7_e3_comb = data_e2 % 5'd19;

    // r8: % 17 using alternating-sign decomposition
    // 16 ≡ -1 (mod 17), x % 17 = (x_lo - x_hi + 17*241) % 17
    wire [12:0] r8_step1 = {9'b0, data_e2[3:0]} + 13'd4097 - {1'b0, data_e2[15:4]};
    wire [4:0] r8_e3_comb = r8_step1 % 5'd17;

    // r9: % 11 direct (16-bit input)
    wire [3:0] r9_e3_comb = data_e2 % 4'd11;

    // Pack 48-bit codeword (right-aligned in 64-bit bus)
    wire [63:0] packed_a = {
        16'd0,          // [63:48] padding
        r1_e2,          // [47:42] r1 = % 64 (6 bits)
        r2_e2,          // [41:36] r2 = % 63 (6 bits)
        r3_e2,          // [35:29] r3 = % 65 (7 bits)
        r4_e2,          // [28:24] r4 = % 31 (5 bits)
        r5_e2,          // [23:19] r5 = % 29 (5 bits)
        r6_e2,          // [18:14] r6 = % 23 (5 bits)
        r7_e3_comb,     // [13:9]  r7 = % 19 (5 bits)
        r8_e3_comb,     // [8:4]   r8 = % 17 (5 bits)
        r9_e3_comb      // [3:0]   r9 = % 11 (4 bits)
    };

    // Output register (Stage E3)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            residues_out_A <= 64'd0;
            residues_out_B <= 64'd0;
            done           <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start_e2) begin
                residues_out_A <= packed_a;
                residues_out_B <= 64'd0;  // Single-channel: Channel B disabled
                done           <= 1'b1;
            end
        end
    end

endmodule
