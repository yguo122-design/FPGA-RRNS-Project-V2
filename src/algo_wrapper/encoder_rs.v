// =============================================================================
// File: encoder_rs.v
// Description: RS(12,4) Encoder over GF(2^4)
//              Primitive polynomial: x^4 + x + 1 (0x13)
//              Generator polynomial roots: alpha^1 .. alpha^8 (t=4)
//              g(x) = x^8 + 9x^7 + 4x^6 + 3x^5 + 4x^4 + 13x^3 + 6x^2 + 14x + 12
//
// CODEWORD FORMAT (48 bits valid, right-aligned in 64-bit bus):
//   Each symbol is 4 bits (GF(2^4) element)
//   [63:48] = 16'b0  (padding)
//   [47:44] = sym[0]  = data nibble 3 (MSN of data)
//   [43:40] = sym[1]  = data nibble 2
//   [39:36] = sym[2]  = data nibble 1
//   [35:32] = sym[3]  = data nibble 0 (LSN of data)
//   [31:28] = sym[4]  = parity 0
//   [27:24] = sym[5]  = parity 1
//   [23:20] = sym[6]  = parity 2
//   [19:16] = sym[7]  = parity 3
//   [15:12] = sym[8]  = parity 4
//   [11:8]  = sym[9]  = parity 5
//   [7:4]   = sym[10] = parity 6
//   [3:0]   = sym[11] = parity 7
//
// DATA MAPPING:
//   data_in_A[15:12] -> sym[0] (MSN)
//   data_in_A[11:8]  -> sym[1]
//   data_in_A[7:4]   -> sym[2]
//   data_in_A[3:0]   -> sym[3] (LSN)
//
// PIPELINE: 3 stages, 3-cycle latency
//   Stage E0: Input register, extract 4 nibbles
//   Stage E1: Systematic encoding (polynomial division)
//   Stage E2: Pack and output
//
// INTERFACE: Identical to encoder_crrns.v for drop-in compatibility.
// =============================================================================

`timescale 1ns / 1ps

module encoder_rs (
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
    // GF(2^4) Multiplication Function
    // Primitive polynomial: x^4 + x + 1 = 0x13
    // Implemented as combinational logic using log/antilog tables
    // =========================================================================

    // ALOG table: ALOG[i] = alpha^i for i=0..14, ALOG[15]=0 (sentinel)
    // alpha = 2 (primitive element)
    // ALOG: [1,2,4,8,3,6,12,11,5,10,7,14,15,13,9]
    function [3:0] gf_alog;
        input [3:0] exp;
        case (exp)
            4'd0:  gf_alog = 4'd1;
            4'd1:  gf_alog = 4'd2;
            4'd2:  gf_alog = 4'd4;
            4'd3:  gf_alog = 4'd8;
            4'd4:  gf_alog = 4'd3;
            4'd5:  gf_alog = 4'd6;
            4'd6:  gf_alog = 4'd12;
            4'd7:  gf_alog = 4'd11;
            4'd8:  gf_alog = 4'd5;
            4'd9:  gf_alog = 4'd10;
            4'd10: gf_alog = 4'd7;
            4'd11: gf_alog = 4'd14;
            4'd12: gf_alog = 4'd15;
            4'd13: gf_alog = 4'd13;
            4'd14: gf_alog = 4'd9;
            default: gf_alog = 4'd0;
        endcase
    endfunction

    // LOG table: LOG[i] = log_alpha(i) for i=1..15, LOG[0]=-1 (undefined)
    function [3:0] gf_log;
        input [3:0] val;
        case (val)
            4'd1:  gf_log = 4'd0;
            4'd2:  gf_log = 4'd1;
            4'd3:  gf_log = 4'd4;
            4'd4:  gf_log = 4'd2;
            4'd5:  gf_log = 4'd8;
            4'd6:  gf_log = 4'd5;
            4'd7:  gf_log = 4'd10;
            4'd8:  gf_log = 4'd3;
            4'd9:  gf_log = 4'd14;
            4'd10: gf_log = 4'd9;
            4'd11: gf_log = 4'd7;
            4'd12: gf_log = 4'd6;
            4'd13: gf_log = 4'd13;
            4'd14: gf_log = 4'd11;
            4'd15: gf_log = 4'd12;
            default: gf_log = 4'd0;
        endcase
    endfunction

    // GF multiplication: a * b
    function [3:0] gf_mul;
        input [3:0] a, b;
        reg [4:0] sum_exp;
        begin
            if (a == 4'd0 || b == 4'd0)
                gf_mul = 4'd0;
            else begin
                sum_exp = {1'b0, gf_log(a)} + {1'b0, gf_log(b)};
                if (sum_exp >= 5'd15) sum_exp = sum_exp - 5'd15;
                gf_mul = gf_alog(sum_exp[3:0]);
            end
        end
    endfunction

    // =========================================================================
    // Generator polynomial coefficients g[1..8] (g[0]=1 implicit)
    // g(x) = x^8 + 9x^7 + 4x^6 + 3x^5 + 4x^4 + 13x^3 + 6x^2 + 14x + 12
    // g[0]=1, g[1]=9, g[2]=4, g[3]=3, g[4]=4, g[5]=13, g[6]=6, g[7]=14, g[8]=12
    // =========================================================================
    localparam [3:0] G1 = 4'd9;
    localparam [3:0] G2 = 4'd4;
    localparam [3:0] G3 = 4'd3;
    localparam [3:0] G4 = 4'd4;
    localparam [3:0] G5 = 4'd13;
    localparam [3:0] G6 = 4'd6;
    localparam [3:0] G7 = 4'd14;
    localparam [3:0] G8 = 4'd12;

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
    // Stage E1: Systematic RS Encoding
    // Compute 8 parity symbols using polynomial long division
    // msg = [d0, d1, d2, d3, 0, 0, 0, 0, 0, 0, 0, 0]
    // For each data symbol d[i], update parity registers:
    //   c = d[i] XOR parity[0]
    //   parity[j] = parity[j+1] XOR gf_mul(c, G[j+1]) for j=0..6
    //   parity[7] = gf_mul(c, G[8])
    //
    // Unrolled for 4 data symbols (combinational, single cycle)
    // =========================================================================
    wire [3:0] d0 = data_e0[15:12];  // MSN
    wire [3:0] d1 = data_e0[11:8];
    wire [3:0] d2 = data_e0[7:4];
    wire [3:0] d3 = data_e0[3:0];    // LSN

    // After processing d0:
    wire [3:0] c0 = d0;  // parity starts at 0, so c0 = d0 ^ 0 = d0
    wire [3:0] p0_0 = gf_mul(c0, G1);
    wire [3:0] p0_1 = gf_mul(c0, G2);
    wire [3:0] p0_2 = gf_mul(c0, G3);
    wire [3:0] p0_3 = gf_mul(c0, G4);
    wire [3:0] p0_4 = gf_mul(c0, G5);
    wire [3:0] p0_5 = gf_mul(c0, G6);
    wire [3:0] p0_6 = gf_mul(c0, G7);
    wire [3:0] p0_7 = gf_mul(c0, G8);

    // After processing d1:
    wire [3:0] c1 = d1 ^ p0_0;
    wire [3:0] p1_0 = p0_1 ^ gf_mul(c1, G1);
    wire [3:0] p1_1 = p0_2 ^ gf_mul(c1, G2);
    wire [3:0] p1_2 = p0_3 ^ gf_mul(c1, G3);
    wire [3:0] p1_3 = p0_4 ^ gf_mul(c1, G4);
    wire [3:0] p1_4 = p0_5 ^ gf_mul(c1, G5);
    wire [3:0] p1_5 = p0_6 ^ gf_mul(c1, G6);
    wire [3:0] p1_6 = p0_7 ^ gf_mul(c1, G7);
    wire [3:0] p1_7 =         gf_mul(c1, G8);

    // After processing d2:
    wire [3:0] c2 = d2 ^ p1_0;
    wire [3:0] p2_0 = p1_1 ^ gf_mul(c2, G1);
    wire [3:0] p2_1 = p1_2 ^ gf_mul(c2, G2);
    wire [3:0] p2_2 = p1_3 ^ gf_mul(c2, G3);
    wire [3:0] p2_3 = p1_4 ^ gf_mul(c2, G4);
    wire [3:0] p2_4 = p1_5 ^ gf_mul(c2, G5);
    wire [3:0] p2_5 = p1_6 ^ gf_mul(c2, G6);
    wire [3:0] p2_6 = p1_7 ^ gf_mul(c2, G7);
    wire [3:0] p2_7 =         gf_mul(c2, G8);

    // After processing d3:
    wire [3:0] c3 = d3 ^ p2_0;
    wire [3:0] par0 = p2_1 ^ gf_mul(c3, G1);
    wire [3:0] par1 = p2_2 ^ gf_mul(c3, G2);
    wire [3:0] par2 = p2_3 ^ gf_mul(c3, G3);
    wire [3:0] par3 = p2_4 ^ gf_mul(c3, G4);
    wire [3:0] par4 = p2_5 ^ gf_mul(c3, G5);
    wire [3:0] par5 = p2_6 ^ gf_mul(c3, G6);
    wire [3:0] par6 = p2_7 ^ gf_mul(c3, G7);
    wire [3:0] par7 =         gf_mul(c3, G8);

    // Register E1 outputs
    (* dont_touch = "true" *) reg [3:0] d0_e1, d1_e1, d2_e1, d3_e1;
    (* dont_touch = "true" *) reg [3:0] par0_e1, par1_e1, par2_e1, par3_e1;
    (* dont_touch = "true" *) reg [3:0] par4_e1, par5_e1, par6_e1, par7_e1;
    (* dont_touch = "true" *) reg start_e1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d0_e1 <= 4'd0; d1_e1 <= 4'd0; d2_e1 <= 4'd0; d3_e1 <= 4'd0;
            par0_e1 <= 4'd0; par1_e1 <= 4'd0; par2_e1 <= 4'd0; par3_e1 <= 4'd0;
            par4_e1 <= 4'd0; par5_e1 <= 4'd0; par6_e1 <= 4'd0; par7_e1 <= 4'd0;
            start_e1 <= 1'b0;
        end else begin
            d0_e1 <= d0; d1_e1 <= d1; d2_e1 <= d2; d3_e1 <= d3;
            par0_e1 <= par0; par1_e1 <= par1; par2_e1 <= par2; par3_e1 <= par3;
            par4_e1 <= par4; par5_e1 <= par5; par6_e1 <= par6; par7_e1 <= par7;
            start_e1 <= start_e0;
        end
    end

    // =========================================================================
    // Stage E2: Pack and Output
    // Codeword: [d0, d1, d2, d3, par0, par1, par2, par3, par4, par5, par6, par7]
    // Each symbol is 4 bits, total 48 bits, right-aligned in 64-bit bus
    // =========================================================================
    wire [63:0] packed_a = {
        16'd0,      // [63:48] padding
        d0_e1,      // [47:44] sym[0]
        d1_e1,      // [43:40] sym[1]
        d2_e1,      // [39:36] sym[2]
        d3_e1,      // [35:32] sym[3]
        par0_e1,    // [31:28] sym[4]
        par1_e1,    // [27:24] sym[5]
        par2_e1,    // [23:20] sym[6]
        par3_e1,    // [19:16] sym[7]
        par4_e1,    // [15:12] sym[8]
        par5_e1,    // [11:8]  sym[9]
        par6_e1,    // [7:4]   sym[10]
        par7_e1     // [3:0]   sym[11]
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            residues_out_A <= 64'd0;
            residues_out_B <= 64'd0;
            done           <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start_e1) begin
                residues_out_A <= packed_a;
                residues_out_B <= 64'd0;
                done           <= 1'b1;
            end
        end
    end

endmodule
