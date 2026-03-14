// =============================================================================
// File: decoder_2nrm.v
// Description: 2NRM Decoder with MLD (Maximum Likelihood Decoding)
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.3.3
// Version: v1.0
//
// Algorithm: 2NRM-RRNS with Moduli Set {257, 256, 61, 59, 55, 53}
//   - 6 moduli: 2 information (257, 256) + 4 redundant (61, 59, 55, 53)
//   - Data width: 16 bits (0~65535)
//   - Error correction capability: t=2 (up to 2 erroneous residues)
//   - MLD: C(6,2)=15 parallel CRT channels, select minimum Hamming distance
//
// Input Packing (41 bits, right-aligned in 64-bit bus):
//   [40:32] = r257 (9-bit)
//   [31:24] = r256 (8-bit)
//   [23:18] = r61  (6-bit)
//   [17:12] = r59  (6-bit)
//   [11:6]  = r55  (6-bit)
//   [5:0]   = r53  (6-bit)
//
// Pipeline Latency: 2 clock cycles
//   Cycle 0: start=1, residues_in sampled
//   Cycle 1: All 15 channels compute CRT reconstruction (registered)
//   Cycle 2: MLD selects minimum distance, valid=1, data_out stable
//
// CRT Formula (per channel):
//   X = r_i + M_i * ((r_j - r_i) * Inv(M_i, M_j) mod M_j)
//   where Inv(M_i, M_j) is the modular inverse of M_i modulo M_j
//
// MLD Decision:
//   For each candidate X, compute residues modulo all 6 moduli.
//   Count mismatches with received residues → Hamming distance.
//   Select X with minimum distance. If min_dist > NRM_MAX_ERRORS(2) → uncorrectable.
// =============================================================================

`include "decoder_2nrm.vh"
`timescale 1ns / 1ps

// =============================================================================
// Sub-Module: decoder_channel_2nrm_param
// Description: Single CRT reconstruction channel for one pair of moduli (M1, M2)
//              Reconstructs candidate X using two received residues, then
//              computes Hamming distance against all 6 received residues.
// Parameters:
//   P_M1    - First modulus value
//   P_M2    - Second modulus value
//   P_INV   - Modular inverse of P_M1 modulo P_M2 (pre-computed constant)
// =============================================================================
module decoder_channel_2nrm_param #(
    parameter P_M1  = 257,  // First modulus
    parameter P_M2  = 256,  // Second modulus
    parameter P_INV = 1     // Inv(P_M1 mod P_M2, P_M2)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    // Received residues (9-bit zero-extended for uniform processing)
    input  wire [8:0]  r0,   // r257
    input  wire [8:0]  r1,   // r256
    input  wire [8:0]  r2,   // r61
    input  wire [8:0]  r3,   // r59
    input  wire [8:0]  r4,   // r55
    input  wire [8:0]  r5,   // r53

    // Which residues this channel uses (index 0~5)
    input  wire [2:0]  idx1, // Index of first modulus in the set
    input  wire [2:0]  idx2, // Index of second modulus in the set

    output reg  [15:0] x_out,
    output reg  [3:0]  distance,
    output reg         valid
);

    // All 6 moduli values for distance computation
    localparam [8:0] MODULI [0:5] = '{9'd257, 9'd256, 9'd61, 9'd59, 9'd55, 9'd53};

    // -------------------------------------------------------------------------
    // Combinational: CRT Reconstruction
    // X = r_i + M1 * ((r_j - r_i) * INV mod M2)
    // -------------------------------------------------------------------------
    // Select the two residues for this channel based on idx1, idx2
    reg [8:0] ri, rj;
    always @(*) begin
        case (idx1)
            3'd0: ri = r0;
            3'd1: ri = r1;
            3'd2: ri = r2;
            3'd3: ri = r3;
            3'd4: ri = r4;
            default: ri = r5;
        endcase
        case (idx2)
            3'd0: rj = r0;
            3'd1: rj = r1;
            3'd2: rj = r2;
            3'd3: rj = r3;
            3'd4: rj = r4;
            default: rj = r5;
        endcase
    end

    // CRT step: diff = (rj - ri + M2) mod M2  (avoid negative)
    wire [17:0] diff_raw;
    wire [17:0] diff_mod;
    assign diff_raw = {9'b0, rj} + P_M2 - {9'b0, ri};
    assign diff_mod = diff_raw % P_M2;

    // CRT step: coeff = (diff * INV) mod M2
    wire [35:0] coeff_raw;
    wire [17:0] coeff_mod;
    assign coeff_raw = diff_mod * P_INV;
    assign coeff_mod = coeff_raw % P_M2;

    // CRT step: X_candidate = ri + M1 * coeff_mod
    wire [31:0] x_cand;
    assign x_cand = {23'b0, ri} + (P_M1 * coeff_mod);

    // Clamp to 16-bit range (valid data is 0~65535)
    wire [15:0] x_cand_16;
    assign x_cand_16 = (x_cand > 32'd65535) ? 16'hFFFF : x_cand[15:0];

    // -------------------------------------------------------------------------
    // Combinational: Hamming Distance Computation
    // For candidate X, compute residues mod all 6 moduli, compare with received
    // -------------------------------------------------------------------------
    wire [8:0] cand_r [0:5];
    assign cand_r[0] = x_cand_16 % 9'd257;
    assign cand_r[1] = x_cand_16 % 9'd256;
    assign cand_r[2] = x_cand_16 % 9'd61;
    assign cand_r[3] = x_cand_16 % 9'd59;
    assign cand_r[4] = x_cand_16 % 9'd55;
    assign cand_r[5] = x_cand_16 % 9'd53;

    wire [8:0] recv_r [0:5];
    assign recv_r[0] = r0;
    assign recv_r[1] = r1;
    assign recv_r[2] = r2;
    assign recv_r[3] = r3;
    assign recv_r[4] = r4;
    assign recv_r[5] = r5;

    // Count mismatches (Hamming distance)
    wire [3:0] dist_comb;
    assign dist_comb = ((cand_r[0] != recv_r[0]) ? 4'd1 : 4'd0) +
                       ((cand_r[1] != recv_r[1]) ? 4'd1 : 4'd0) +
                       ((cand_r[2] != recv_r[2]) ? 4'd1 : 4'd0) +
                       ((cand_r[3] != recv_r[3]) ? 4'd1 : 4'd0) +
                       ((cand_r[4] != recv_r[4]) ? 4'd1 : 4'd0) +
                       ((cand_r[5] != recv_r[5]) ? 4'd1 : 4'd0);

    // -------------------------------------------------------------------------
    // Sequential: Register outputs (1-cycle latency)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_out    <= 16'd0;
            distance <= 4'd6; // Max distance (worst case) on reset
            valid    <= 1'b0;
        end else begin
            valid <= start;
            if (start) begin
                x_out    <= x_cand_16;
                distance <= dist_comb;
            end
        end
    end

endmodule


// =============================================================================
// Main Module: decoder_2nrm
// Description: Top-level 2NRM decoder with 15 parallel CRT channels and MLD
// =============================================================================
module decoder_2nrm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    // Input: 41-bit packed residues (right-aligned in 64-bit bus from encoder)
    // [40:32]=r257, [31:24]=r256, [23:18]=r61, [17:12]=r59, [11:6]=r55, [5:0]=r53
    input  wire [63:0] residues_in,

    // Output
    output reg  [15:0] data_out,
    output reg         valid,
    output reg         uncorrectable
);

    // =========================================================================
    // 1. Input Unpacking
    // =========================================================================
    // Extract residues from packed 41-bit format (zero-extend to 9-bit)
    wire [8:0] r0 = residues_in[40:32];        // r257 (9-bit, no extension needed)
    wire [8:0] r1 = {1'b0, residues_in[31:24]}; // r256 (8-bit → 9-bit)
    wire [8:0] r2 = {3'b0, residues_in[23:18]}; // r61  (6-bit → 9-bit)
    wire [8:0] r3 = {3'b0, residues_in[17:12]}; // r59  (6-bit → 9-bit)
    wire [8:0] r4 = {3'b0, residues_in[11:6]};  // r55  (6-bit → 9-bit)
    wire [8:0] r5 = {3'b0, residues_in[5:0]};   // r53  (6-bit → 9-bit)

    // =========================================================================
    // 2. 15 Parallel CRT Channels (C(6,2) = 15 pairs)
    // =========================================================================
    // Pair mapping: (idx1, idx2) for each of the 15 channels
    // Channel 0:(0,1), 1:(0,2), 2:(0,3), 3:(0,4), 4:(0,5)
    // Channel 5:(1,2), 6:(1,3), 7:(1,4), 8:(1,5)
    // Channel 9:(2,3), 10:(2,4), 11:(2,5)
    // Channel 12:(3,4), 13:(3,5)
    // Channel 14:(4,5)
    //
    // Moduli: M[0]=257, M[1]=256, M[2]=61, M[3]=59, M[4]=55, M[5]=53
    //
    // Pre-computed constants: Inv(M_i mod M_j, M_j) for each pair
    // Verified by: M_i * Inv ≡ 1 (mod M_j)
    //
    // Channel  Pair    M_i  M_j  M_i mod M_j  Inv   Verification
    //   0     (0,1)   257  256      1          1    1*1=1 ≡1(mod 256) ✓
    //   1     (0,2)   257   61     14         48   14*48=672=11*61+1 ✓
    //   2     (0,3)   257   59     21         45   21*45=945=16*59+1 ✓
    //   3     (0,4)   257   55     37          3   37*3=111=2*55+1 ✓
    //   4     (0,5)   257   53     45         33   45*33=1485=28*53+1 ✓
    //   5     (1,2)   256   61     12         56   12*56=672=11*61+1 ✓
    //   6     (1,3)   256   59     20          3   20*3=60=1*59+1 ✓
    //   7     (1,4)   256   55     36         26   36*26=936=17*55+1 ✓
    //   8     (1,5)   256   53     44         47   44*47=2068=39*53+1 ✓
    //   9     (2,3)    61   59      2         30   2*30=60=1*59+1 ✓
    //  10     (2,4)    61   55      6         46   6*46=276=5*55+1 ✓
    //  11     (2,5)    61   53      8         20   8*20=160=3*53+1 ✓
    //  12     (3,4)    59   55      4         14   4*14=56=1*55+1 ✓
    //  13     (3,5)    59   53      6          9   6*9=54=1*53+1 ✓
    //  14     (4,5)    55   53      2         27   2*27=54=1*53+1 ✓

    // Channel outputs
    wire [15:0] ch_x    [0:14];
    wire [3:0]  ch_dist [0:14];
    wire        ch_valid[0:14];

    // Channel 0: pair (0,1) M1=257, M2=256, Inv=1
    decoder_channel_2nrm_param #(.P_M1(257), .P_M2(256), .P_INV(1))
        ch0 (.clk(clk), .rst_n(rst_n), .start(start),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd0), .idx2(3'd1),
             .x_out(ch_x[0]), .distance(ch_dist[0]), .valid(ch_valid[0]));

    // Channel 1: pair (0,2) M1=257, M2=61, Inv=48
    decoder_channel_2nrm_param #(.P_M1(257), .P_M2(61), .P_INV(48))
        ch1 (.clk(clk), .rst_n(rst_n), .start(start),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd0), .idx2(3'd2),
             .x_out(ch_x[1]), .distance(ch_dist[1]), .valid(ch_valid[1]));

    // Channel 2: pair (0,3) M1=257, M2=59, Inv=45
    decoder_channel_2nrm_param #(.P_M1(257), .P_M2(59), .P_INV(45))
        ch2 (.clk(clk), .rst_n(rst_n), .start(start),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd0), .idx2(3'd3),
             .x_out(ch_x[2]), .distance(ch_dist[2]), .valid(ch_valid[2]));

    // Channel 3: pair (0,4) M1=257, M2=55, Inv=3
    decoder_channel_2nrm_param #(.P_M1(257), .P_M2(55), .P_INV(3))
        ch3 (.clk(clk), .rst_n(rst_n), .start(start),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd0), .idx2(3'd4),
             .x_out(ch_x[3]), .distance(ch_dist[3]), .valid(ch_valid[3]));

    // Channel 4: pair (0,5) M1=257, M2=53, Inv=33
    decoder_channel_2nrm_param #(.P_M1(257), .P_M2(53), .P_INV(33))
        ch4 (.clk(clk), .rst_n(rst_n), .start(start),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd0), .idx2(3'd5),
             .x_out(ch_x[4]), .distance(ch_dist[4]), .valid(ch_valid[4]));

    // Channel 5: pair (1,2) M1=256, M2=61, Inv=56
    decoder_channel_2nrm_param #(.P_M1(256), .P_M2(61), .P_INV(56))
        ch5 (.clk(clk), .rst_n(rst_n), .start(start),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd1), .idx2(3'd2),
             .x_out(ch_x[5]), .distance(ch_dist[5]), .valid(ch_valid[5]));

    // Channel 6: pair (1,3) M1=256, M2=59, Inv=3
    decoder_channel_2nrm_param #(.P_M1(256), .P_M2(59), .P_INV(3))
        ch6 (.clk(clk), .rst_n(rst_n), .start(start),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd1), .idx2(3'd3),
             .x_out(ch_x[6]), .distance(ch_dist[6]), .valid(ch_valid[6]));

    // Channel 7: pair (1,4) M1=256, M2=55, Inv=26
    decoder_channel_2nrm_param #(.P_M1(256), .P_M2(55), .P_INV(26))
        ch7 (.clk(clk), .rst_n(rst_n), .start(start),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd1), .idx2(3'd4),
             .x_out(ch_x[7]), .distance(ch_dist[7]), .valid(ch_valid[7]));

    // Channel 8: pair (1,5) M1=256, M2=53, Inv=47
    decoder_channel_2nrm_param #(.P_M1(256), .P_M2(53), .P_INV(47))
        ch8 (.clk(clk), .rst_n(rst_n), .start(start),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd1), .idx2(3'd5),
             .x_out(ch_x[8]), .distance(ch_dist[8]), .valid(ch_valid[8]));

    // Channel 9: pair (2,3) M1=61, M2=59, Inv=30
    decoder_channel_2nrm_param #(.P_M1(61), .P_M2(59), .P_INV(30))
        ch9 (.clk(clk), .rst_n(rst_n), .start(start),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd2), .idx2(3'd3),
             .x_out(ch_x[9]), .distance(ch_dist[9]), .valid(ch_valid[9]));

    // Channel 10: pair (2,4) M1=61, M2=55, Inv=46
    decoder_channel_2nrm_param #(.P_M1(61), .P_M2(55), .P_INV(46))
        ch10 (.clk(clk), .rst_n(rst_n), .start(start),
              .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
              .idx1(3'd2), .idx2(3'd4),
              .x_out(ch_x[10]), .distance(ch_dist[10]), .valid(ch_valid[10]));

    // Channel 11: pair (2,5) M1=61, M2=53, Inv=20
    decoder_channel_2nrm_param #(.P_M1(61), .P_M2(53), .P_INV(20))
        ch11 (.clk(clk), .rst_n(rst_n), .start(start),
              .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
              .idx1(3'd2), .idx2(3'd5),
              .x_out(ch_x[11]), .distance(ch_dist[11]), .valid(ch_valid[11]));

    // Channel 12: pair (3,4) M1=59, M2=55, Inv=14
    decoder_channel_2nrm_param #(.P_M1(59), .P_M2(55), .P_INV(14))
        ch12 (.clk(clk), .rst_n(rst_n), .start(start),
              .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
              .idx1(3'd3), .idx2(3'd4),
              .x_out(ch_x[12]), .distance(ch_dist[12]), .valid(ch_valid[12]));

    // Channel 13: pair (3,5) M1=59, M2=53, Inv=9
    decoder_channel_2nrm_param #(.P_M1(59), .P_M2(53), .P_INV(9))
        ch13 (.clk(clk), .rst_n(rst_n), .start(start),
              .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
              .idx1(3'd3), .idx2(3'd5),
              .x_out(ch_x[13]), .distance(ch_dist[13]), .valid(ch_valid[13]));

    // Channel 14: pair (4,5) M1=55, M2=53, Inv=27
    decoder_channel_2nrm_param #(.P_M1(55), .P_M2(53), .P_INV(27))
        ch14 (.clk(clk), .rst_n(rst_n), .start(start),
              .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
              .idx1(3'd4), .idx2(3'd5),
              .x_out(ch_x[14]), .distance(ch_dist[14]), .valid(ch_valid[14]));

    // =========================================================================
    // 3. MLD: Select Channel with Minimum Hamming Distance
    // =========================================================================
    // Pipeline stage 2: when ch_valid[0] is high (all channels valid simultaneously),
    // perform the minimum distance selection and register the output.
    //
    // Tie-breaking: lower channel index wins (deterministic behavior)

    // Combinational minimum distance tree
    reg [3:0]  min_dist_comb;
    reg [15:0] best_x_comb;
    integer k;

    always @(*) begin
        min_dist_comb = 4'd6; // Initialize to impossible max (6 moduli)
        best_x_comb   = 16'd0;
        for (k = 0; k < 15; k = k + 1) begin
            if (ch_dist[k] < min_dist_comb) begin
                min_dist_comb = ch_dist[k];
                best_x_comb   = ch_x[k];
            end
        end
    end

    // =========================================================================
    // 4. Sequential Output Register (Cycle 2)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out      <= 16'd0;
            valid         <= 1'b0;
            uncorrectable <= 1'b0;
        end else begin
            // ch_valid[0] is the registered start signal from cycle 1
            valid <= ch_valid[0];

            if (ch_valid[0]) begin
                data_out <= best_x_comb;
                // Uncorrectable if minimum distance exceeds error correction capability
                // NRM_MAX_ERRORS = 2, so if min_dist > 2, correction is not reliable
                uncorrectable <= (min_dist_comb > `NRM_MAX_ERRORS);
            end else begin
                uncorrectable <= 1'b0;
            end
        end
    end

endmodule
