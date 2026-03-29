// =============================================================================
// File: decoder_crrns_crt.v
// Description: C-RRNS Decoder using Mixed Radix Conversion (MRC)
//              Algorithm: Residue Number System with Moduli Set:
//              Non-redundant: {64, 63, 65}
//              Redundant:     {67, 71, 73, 79, 83, 89} (NOT used in decoding)
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
// Version: v2.0 (Bug #90 Fix: Replaced incorrect CRT with correct MRC)
//
// BUG FIX (Bug #90, 2026-03-26):
//   The original implementation used CRT with M=262,080 (wrong).
//   The correct M_a = 64 × 63 × 65 = 261,120, but standard CRT cannot be
//   applied because gcd(M_a/64, 64) = gcd(4080, 64) = 16 ≠ 1 (not invertible).
//   The CRT constants C0=257985, C1=133120, C2=133056 were computed with the
//   wrong M=262,080, causing incorrect decoding results.
//
//   FIX: Replaced with MRC (Mixed Radix Conversion), which is mathematically
//   correct for this moduli set and produces identical results to the MATLAB
//   decode_crrns_crt.m implementation (which also falls back to MRC).
//
// ALGORITHM: Mixed Radix Conversion using only 3 non-redundant moduli.
//   MRC constants (pre-computed):
//     Inv(64, 63)           = 1   (since 64 ≡ 1 mod 63)
//     Inv(64*63 mod 65, 65) = Inv(2, 65) = 33
//
//   MRC steps:
//     a1 = r0                                    (mod 64)
//     a2 = (r1 - a1 mod 63) * 1 mod 63          (mod 63, Inv=1)
//     a3 = (r2 - (a1 + a2*64) mod 65) * 33 mod 65
//     X  = a1 + a2*64 + a3*64*63
//
// CHARACTERISTICS:
//   - NO error correction: only uses 3 non-redundant moduli
//   - If any of r0, r1, r2 is corrupted, X will be wrong
//   - Errors in redundant moduli (r3~r8) are completely ignored
//   - Latency: 8 clock cycles (start -> valid)
//   - Consistent with MATLAB decode_crrns_crt.m and decode_crrns_mrc.m
//
// INPUT BIT LAYOUT (61 bits valid, right-aligned in 64-bit bus):
//   [63:61] = padding (ignored)
//   [60:55] = r0 = received residue mod 64  (6 bits) ← USED
//   [54:49] = r1 = received residue mod 63  (6 bits) ← USED
//   [48:42] = r2 = received residue mod 65  (7 bits) ← USED
//   [41:35] = r3 = received residue mod 67  (7 bits) ← IGNORED
//   [34:28] = r4 = received residue mod 71  (7 bits) ← IGNORED
//   [27:21] = r5 = received residue mod 73  (7 bits) ← IGNORED
//   [20:14] = r6 = received residue mod 79  (7 bits) ← IGNORED
//   [13:7]  = r7 = received residue mod 83  (7 bits) ← IGNORED
//   [6:0]   = r8 = received residue mod 89  (7 bits) ← IGNORED
// =============================================================================

`timescale 1ns / 1ps

module decoder_crrns_crt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [63:0] residues_in,
    output reg  [15:0] data_out,
    output reg         valid,
    output reg         uncorrectable
);

    // =========================================================================
    // FSM State Encoding (MRC pipeline, same as decoder_crrns_mrc.v)
    // =========================================================================
    localparam ST_IDLE  = 3'd0;
    localparam ST_LOAD  = 3'd1;  // Unpack r0, r1, r2
    localparam ST_S1    = 3'd2;  // a1 = r0; diff1 = (r1 - r0%63 + 63) % 63
    localparam ST_S2    = 3'd3;  // a2 = diff1 (Inv=1); compute sub = (a1 + a2*64) % 65
    localparam ST_S3    = 3'd4;  // diff2 = (r2 - sub + 65*N) % 65
    localparam ST_S4    = 3'd5;  // a3 = diff2 * 33 % 65
    localparam ST_S5    = 3'd6;  // X = a1 + a2*64 + a3*64*63; check range
    localparam ST_DONE  = 3'd7;  // Output result

    reg [2:0] state;

    // =========================================================================
    // Pipeline Registers
    // =========================================================================
    reg [5:0]  r0_reg;
    reg [5:0]  r1_reg;
    reg [6:0]  r2_reg;

    reg [5:0]  a1_reg;
    reg [5:0]  diff1_reg;

    reg [5:0]  a2_reg;
    reg [6:0]  sub_reg;

    reg [6:0]  diff2_reg;

    reg [6:0]  a3_reg;

    reg [17:0] X_reg;

    // =========================================================================
    // Combinational Intermediate Signals (identical to decoder_crrns_mrc.v)
    // =========================================================================

    // ST_S1: diff1 = (r1 - r0%63 + 63) % 63
    wire [5:0] r0_mod63   = (r0_reg == 6'd63) ? 6'd0 : r0_reg;
    wire [6:0] diff1_raw  = {1'b0, r1_reg} + 7'd63 - {1'b0, r0_mod63};
    wire [5:0] diff1_comb = (diff1_raw >= 7'd63) ? (diff1_raw - 7'd63) : diff1_raw[5:0];

    // ST_S2: a2 = diff1; sub = (a1 + a2*64) % 65
    wire [11:0] a2_64          = {diff1_reg, 6'b0};
    wire [11:0] a1_plus_a2_64  = {6'b0, a1_reg} + a2_64;
    wire [6:0]  sub_comb       = a1_plus_a2_64 % 7'd65;

    // ST_S3: diff2 = (r2 - sub + 65) % 65
    wire [7:0] diff2_raw  = {1'b0, r2_reg} + 8'd65 - {1'b0, sub_reg};
    wire [6:0] diff2_comb = (diff2_raw >= 8'd65) ? (diff2_raw - 8'd65) : diff2_raw[6:0];

    // ST_S4: a3 = diff2 * 33 % 65
    wire [11:0] a3_prod = {5'b0, diff2_reg} * 12'd33;
    wire [6:0]  a3_comb = a3_prod % 7'd65;

    // ST_S5: X = a1 + a2*64 + a3*64*63 = a1 + a2*64 + a3*4032
    wire [17:0] a3_4032 = {11'b0, a3_reg} * 18'd4032;
    wire [17:0] X_comb  = {12'b0, a1_reg} + {6'b0, a2_reg, 6'b0} + a3_4032;

    // =========================================================================
    // FSM (identical structure to decoder_crrns_mrc.v)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            r0_reg        <= 6'd0;
            r1_reg        <= 6'd0;
            r2_reg        <= 7'd0;
            a1_reg        <= 6'd0;
            diff1_reg     <= 6'd0;
            a2_reg        <= 6'd0;
            sub_reg       <= 7'd0;
            diff2_reg     <= 7'd0;
            a3_reg        <= 7'd0;
            X_reg         <= 18'd0;
            data_out      <= 16'd0;
            valid         <= 1'b0;
            uncorrectable <= 1'b0;
        end else begin
            valid         <= 1'b0;
            uncorrectable <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) state <= ST_LOAD;
                end

                ST_LOAD: begin
                    r0_reg <= residues_in[60:55];  // mod 64 (6-bit)
                    r1_reg <= residues_in[54:49];  // mod 63 (6-bit)
                    r2_reg <= residues_in[48:42];  // mod 65 (7-bit)
                    state  <= ST_S1;
                end

                ST_S1: begin
                    a1_reg    <= r0_reg;
                    diff1_reg <= diff1_comb;
                    state     <= ST_S2;
                end

                ST_S2: begin
                    a2_reg  <= diff1_reg;
                    sub_reg <= sub_comb;
                    state   <= ST_S3;
                end

                ST_S3: begin
                    diff2_reg <= diff2_comb;
                    state     <= ST_S4;
                end

                ST_S4: begin
                    a3_reg <= a3_comb;
                    state  <= ST_S5;
                end

                ST_S5: begin
                    X_reg <= X_comb;
                    state <= ST_DONE;
                end

                ST_DONE: begin
                    valid <= 1'b1;
                    if (X_reg <= 18'd65535) begin
                        data_out      <= X_reg[15:0];
                        uncorrectable <= 1'b0;
                    end else begin
                        data_out      <= 16'd0;
                        uncorrectable <= 1'b1;
                    end
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
