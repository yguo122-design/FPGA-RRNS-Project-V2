// =============================================================================
// File: decoder_crrns_mrc.v
// Description: C-RRNS Decoder using Mixed Radix Conversion (MRC)
//              Algorithm: Residue Number System with Moduli Set:
//              Non-redundant: {64, 63, 65}
//              Redundant:     {67, 71, 73, 79, 83, 89} (NOT used in decoding)
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
// Version: v1.0
//
// ALGORITHM: Mixed Radix Conversion using only 3 non-redundant moduli.
//   MRC constants (pre-computed):
//     Inv(64, 63)         = 1   (since 64 ≡ 1 mod 63)
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
//   - Resource: minimal (~50 LUT)
//
// COMPARISON vs C-RRNS-MLD:
//   MLD: 924 cycles, 100% correction for t<=3 errors
//   MRC: 8 cycles, 0% correction (fails if any non-redundant modulus is wrong)
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

module decoder_crrns_mrc (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [63:0] residues_in,
    output reg  [15:0] data_out,
    output reg         valid,
    output reg         uncorrectable
);

    // =========================================================================
    // FSM State Encoding (simple pipeline)
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
    reg [5:0]  r0_reg;   // mod 64 (6-bit)
    reg [5:0]  r1_reg;   // mod 63 (6-bit)
    reg [6:0]  r2_reg;   // mod 65 (7-bit)

    reg [5:0]  a1_reg;   // = r0 (6-bit)
    reg [5:0]  diff1_reg; // (r1 - r0%63 + 63) % 63 (6-bit)

    reg [5:0]  a2_reg;   // = diff1 (Inv=1, so a2 = diff1) (6-bit)
    reg [6:0]  sub_reg;  // (a1 + a2*64) % 65 (7-bit)

    reg [6:0]  diff2_reg; // (r2 - sub + 65*N) % 65 (7-bit)

    reg [6:0]  a3_reg;   // diff2 * 33 % 65 (7-bit)

    reg [17:0] X_reg;    // a1 + a2*64 + a3*64*63 (18-bit)

    // =========================================================================
    // Combinational Intermediate Signals
    // =========================================================================

    // ST_S1: diff1 = (r1 - r0%63 + 63) % 63
    // r0 % 63: since r0 is 6-bit (0..63), r0%63 = r0 if r0<63, else 0
    wire [5:0] r0_mod63 = (r0_reg == 6'd63) ? 6'd0 : r0_reg;
    wire [6:0] diff1_raw = {1'b0, r1_reg} + 7'd63 - {1'b0, r0_mod63};
    wire [5:0] diff1_comb = (diff1_raw >= 7'd63) ? (diff1_raw - 7'd63) : diff1_raw[5:0];

    // ST_S2: a2 = diff1 (Inv(64,63)=1, so a2 = diff1 * 1 % 63 = diff1)
    // sub = (a1 + a2*64) % 65
    // a2*64: 6-bit * 64 = 12-bit (max 62*64=3968)
    // a1 + a2*64: max 63 + 3968 = 4031
    // 4031 % 65: need to compute
    wire [11:0] a2_64 = {diff1_reg, 6'b0};  // diff1 * 64 (shift left 6)
    wire [11:0] a1_plus_a2_64 = {6'b0, a1_reg} + a2_64;
    wire [6:0]  sub_comb = a1_plus_a2_64 % 7'd65;

    // ST_S3: diff2 = (r2 - sub + 65*N) % 65
    // r2 is 7-bit (0..64), sub is 7-bit (0..64)
    // Add 65 to ensure non-negative before mod
    wire [7:0] diff2_raw = {1'b0, r2_reg} + 8'd65 - {1'b0, sub_reg};
    wire [6:0] diff2_comb = (diff2_raw >= 8'd65) ? (diff2_raw - 8'd65) : diff2_raw[6:0];

    // ST_S4: a3 = diff2 * 33 % 65
    // diff2 is 7-bit (0..64), 33 is constant
    // diff2 * 33: max 64*33 = 2112 (12-bit)
    wire [11:0] a3_prod = {5'b0, diff2_reg} * 12'd33;
    wire [6:0]  a3_comb = a3_prod % 7'd65;

    // ST_S5: X = a1 + a2*64 + a3*64*63
    // a3*64*63 = a3 * 4032: max 64*4032 = 258048 (18-bit)
    // a2*64: max 62*64 = 3968 (12-bit)
    // a1: max 63 (6-bit)
    // X max = 63 + 3968 + 258048 = 262079 (18-bit)
    wire [17:0] a3_4032 = {11'b0, a3_reg} * 18'd4032;  // a3 * 64 * 63
    wire [17:0] X_comb  = {12'b0, a1_reg} + {6'b0, a2_reg, 6'b0} + a3_4032;

    // =========================================================================
    // FSM
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
                    // Unpack only the 3 non-redundant residues
                    r0_reg <= residues_in[60:55];  // mod 64 (6-bit)
                    r1_reg <= residues_in[54:49];  // mod 63 (6-bit)
                    r2_reg <= residues_in[48:42];  // mod 65 (7-bit)
                    state  <= ST_S1;
                end

                ST_S1: begin
                    // a1 = r0
                    // diff1 = (r1 - r0%63 + 63) % 63
                    a1_reg    <= r0_reg;
                    diff1_reg <= diff1_comb;
                    state     <= ST_S2;
                end

                ST_S2: begin
                    // a2 = diff1 (Inv(64,63)=1)
                    // sub = (a1 + a2*64) % 65
                    a2_reg  <= diff1_reg;
                    sub_reg <= sub_comb;
                    state   <= ST_S3;
                end

                ST_S3: begin
                    // diff2 = (r2 - sub + 65) % 65
                    diff2_reg <= diff2_comb;
                    state     <= ST_S4;
                end

                ST_S4: begin
                    // a3 = diff2 * 33 % 65
                    a3_reg <= a3_comb;
                    state  <= ST_S5;
                end

                ST_S5: begin
                    // X = a1 + a2*64 + a3*64*63
                    X_reg <= X_comb;
                    state <= ST_DONE;
                end

                ST_DONE: begin
                    valid <= 1'b1;
                    if (X_reg <= 18'd65535) begin
                        data_out      <= X_reg[15:0];
                        uncorrectable <= 1'b0;
                    end else begin
                        // X out of range: non-redundant moduli were corrupted
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
