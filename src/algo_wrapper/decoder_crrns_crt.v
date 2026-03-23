// =============================================================================
// File: decoder_crrns_crt.v
// Description: C-RRNS Decoder using Chinese Remainder Theorem (CRT)
//              Algorithm: Residue Number System with Moduli Set:
//              Non-redundant: {64, 63, 65}
//              Redundant:     {67, 71, 73, 79, 83, 89} (NOT used in decoding)
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
// Version: v1.0
//
// ALGORITHM: Chinese Remainder Theorem using only 3 non-redundant moduli.
//
//   CRT formula: X = (r0*c0 + r1*c1 + r2*c2) mod M
//
//   Where M = 64 * 63 * 65 = 262080, and:
//     c0 = (M/64) * Inv(M/64, 64) mod M = 4095 * 63 mod 262080 = 257985
//     c1 = (M/63) * Inv(M/63, 63) mod M = 4160 * 32 mod 262080 = 133120
//     c2 = (M/65) * Inv(M/65, 65) mod M = 4032 * 33 mod 262080 = 133056
//
//   All constants are pre-computed at design time (compile-time constants).
//
// CHARACTERISTICS:
//   - NO error correction: only uses 3 non-redundant moduli
//   - If any of r0, r1, r2 is corrupted, X will be wrong
//   - Errors in redundant moduli (r3~r8) are completely ignored
//   - Latency: 5 clock cycles (start -> valid)
//   - Resource: ~80 LUT (slightly more than MRC due to larger multipliers)
//   - Advantage over MRC: parallel computation (3 multiplications in parallel)
//
// COMPARISON vs C-RRNS-MRC:
//   MRC: 8 cycles, serial computation (a1->a2->a3->X)
//   CRT: 5 cycles, parallel computation (t0,t1,t2 simultaneously)
//
// BIT WIDTH ANALYSIS:
//   r0 * c0: 6-bit * 18-bit = 24-bit (max 63*257985 = 16,253,055)
//   r1 * c1: 6-bit * 18-bit = 24-bit (max 62*133120 =  8,253,440)
//   r2 * c2: 7-bit * 18-bit = 25-bit (max 64*133056 =  8,515,584)
//   sum:     25-bit (max 33,022,079)
//   X = sum mod 262080: 18-bit (0..262079)
//   Valid range check: X <= 65535 (16-bit data)
//
// INPUT BIT LAYOUT (61 bits valid, right-aligned in 64-bit bus):
//   [63:61] = padding (ignored)
//   [60:55] = r0 = received residue mod 64  (6 bits) <- USED
//   [54:49] = r1 = received residue mod 63  (6 bits) <- USED
//   [48:42] = r2 = received residue mod 65  (7 bits) <- USED
//   [41:35] = r3 = received residue mod 67  (7 bits) <- IGNORED
//   [34:28] = r4 = received residue mod 71  (7 bits) <- IGNORED
//   [27:21] = r5 = received residue mod 73  (7 bits) <- IGNORED
//   [20:14] = r6 = received residue mod 79  (7 bits) <- IGNORED
//   [13:7]  = r7 = received residue mod 83  (7 bits) <- IGNORED
//   [6:0]   = r8 = received residue mod 89  (7 bits) <- IGNORED
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
    // CRT Pre-computed Constants (compile-time, synthesized as constants)
    // =========================================================================
    // M = 64 * 63 * 65 = 262080
    // c0 = 257985  (r0 multiplier: M0 * Inv(M0, 64) mod M)
    // c1 = 133120  (r1 multiplier: M1 * Inv(M1, 63) mod M)
    // c2 = 133056  (r2 multiplier: M2 * Inv(M2, 65) mod M)
    localparam [17:0] C0 = 18'd257985;
    localparam [17:0] C1 = 18'd133120;
    localparam [17:0] C2 = 18'd133056;
    localparam [17:0] M  = 18'd262080;

    // =========================================================================
    // FSM State Encoding (parallel pipeline)
    // =========================================================================
    localparam ST_IDLE  = 3'd0;
    localparam ST_LOAD  = 3'd1;  // Unpack r0, r1, r2
    localparam ST_S1    = 3'd2;  // Parallel: t0=r0*C0, t1=r1*C1, t2=r2*C2
    localparam ST_S2    = 3'd3;  // sum = t0 + t1 + t2
    localparam ST_S3    = 3'd4;  // X = sum mod M
    localparam ST_DONE  = 3'd5;  // Output result

    reg [2:0] state;

    // =========================================================================
    // Pipeline Registers
    // =========================================================================
    reg [5:0]  r0_reg;   // mod 64 (6-bit)
    reg [5:0]  r1_reg;   // mod 63 (6-bit)
    reg [6:0]  r2_reg;   // mod 65 (7-bit)

    // ST_S1: parallel products (registered)
    reg [23:0] t0_reg;   // r0 * C0 (24-bit, max 63*257985=16,253,055)
    reg [23:0] t1_reg;   // r1 * C1 (24-bit, max 62*133120= 8,253,440)
    reg [24:0] t2_reg;   // r2 * C2 (25-bit, max 64*133056= 8,515,584)

    // ST_S2: sum (registered)
    reg [24:0] sum_reg;  // t0 + t1 + t2 (25-bit, max 33,022,079)

    // ST_S3: X = sum mod M (registered)
    reg [17:0] X_reg;    // 0..262079 (18-bit)

    // =========================================================================
    // Combinational Intermediate Signals
    // =========================================================================

    // ST_S1: parallel multiplications (combinational, registered in ST_S1)
    wire [23:0] t0_comb = {18'b0, r0_reg} * C0;  // 6-bit * 18-bit = 24-bit
    wire [23:0] t1_comb = {18'b0, r1_reg} * C1;  // 6-bit * 18-bit = 24-bit
    wire [24:0] t2_comb = {18'b0, r2_reg} * C2;  // 7-bit * 18-bit = 25-bit

    // ST_S2: sum (combinational, registered in ST_S2)
    wire [24:0] sum_comb = {1'b0, t0_reg} + {1'b0, t1_reg} + t2_reg;

    // ST_S3: X = sum mod M (combinational, registered in ST_S3)
    // sum is 25-bit (max 33,022,079), M=262080
    // sum / M max = 33,022,079 / 262,080 ≈ 126 (7-bit quotient)
    // Vivado optimizes constant modulo to ~10-15 LUT levels
    wire [17:0] X_comb = sum_reg % M;

    // =========================================================================
    // FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            r0_reg        <= 6'd0;
            r1_reg        <= 6'd0;
            r2_reg        <= 7'd0;
            t0_reg        <= 24'd0;
            t1_reg        <= 24'd0;
            t2_reg        <= 25'd0;
            sum_reg       <= 25'd0;
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
                    // Parallel: compute t0=r0*C0, t1=r1*C1, t2=r2*C2
                    // All three multiplications happen simultaneously
                    t0_reg <= t0_comb;
                    t1_reg <= t1_comb;
                    t2_reg <= t2_comb;
                    state  <= ST_S2;
                end

                ST_S2: begin
                    // sum = t0 + t1 + t2
                    sum_reg <= sum_comb;
                    state   <= ST_S3;
                end

                ST_S3: begin
                    // X = sum mod M (constant modulo, Vivado optimizes efficiently)
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
