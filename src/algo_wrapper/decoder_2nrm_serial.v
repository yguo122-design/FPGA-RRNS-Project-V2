// =============================================================================
// File: decoder_2nrm_serial.v
// Description: 2NRM-RRNS Decoder — Sequential FSM MLD (Serial Architecture)
//              Algorithm: Residue Number System with Moduli Set:
//              {257, 256, 61, 59, 55, 53}  (2 information + 4 redundant)
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
// Version: v1.1 (Bug fix: added multi-candidate enumeration k=0~4)
//
// BUG FIX v1.1:
//   v1.0 only computed k=0 candidate (X = ri + Mi*a2) for each pair.
//   For large X values, the correct answer may be X + k*PERIOD (k=1~4).
//   Without enumerating these candidates, the decoder fails for ~30% of cases
//   where the correct X > M_i*M_j (the base CRT solution range).
//   This is the same multi-candidate logic as in decoder_2nrm.v (parallel),
//   Stage 3a (x_k0~x_k4).
//
// ALGORITHM: Sequential MLD over C(6,2)=15 modulus pairs × up to 5 candidates
//   For each pair (M_i, M_j):
//     PERIOD = M_i * M_j
//     For k = 0, 1, 2, 3, 4:
//       X_k = X_0 + k * PERIOD  (where X_0 = ri + Mi * a2)
//       If X_k > 65535: skip (out of 16-bit data range)
//       Compute residues of X_k modulo all 6 moduli
//       Compute Hamming distance
//       Update best candidate if distance is smaller
//   Select X with minimum distance. If min_dist > 2 → uncorrectable.
//
// FSM STATES (per pair, per candidate):
//   IDLE → LOAD → CRT_S1 → CRT_S2 → CRT_S3 → CRT_S3B → CRT_S4
//        → CAND_LOOP: for k=0..4:
//            → DIST_S1 → DIST_S2 → UPDATE → CAND_NEXT
//        → NEXT (advance pair_idx) → ... → DONE
//
// LATENCY: ~15 pairs × (7 CRT states + 5 candidates × 4 dist states)
//        = ~15 × (7 + 20) = ~405 cycles (worst case, all 5 candidates valid)
//        Typical: ~15 × (7 + 2~3 × 4) ≈ ~225 cycles
//        (Most pairs have only 1~2 valid candidates since PERIOD is large)
// =============================================================================

`timescale 1ns / 1ps

module decoder_2nrm_serial (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [63:0] residues_in,
    output reg  [15:0] data_out,
    output reg         valid,
    output reg         uncorrectable
);

    // =========================================================================
    // 1. FSM State Encoding
    // =========================================================================
    localparam ST_IDLE      = 4'd0;
    localparam ST_LOAD      = 4'd1;
    localparam ST_CRT_S1    = 4'd2;   // Load pair parameters
    localparam ST_CRT_S2    = 4'd3;   // Compute diff = (rj - ri + Mj) % Mj
    localparam ST_CRT_S3    = 4'd4;   // Compute a2 = (diff * Inv) % Mj
    localparam ST_CRT_S3B   = 4'd13;  // Register a2*Mi product (pipeline break)
    localparam ST_CRT_S4    = 4'd5;   // Compute X_base = ri + Mi * a2
    localparam ST_DIST_S1   = 4'd6;   // Compute cand_r[0..2] = X_k % {257,256,61}
    localparam ST_DIST_S2   = 4'd7;   // Compute cand_r[3..5] = X_k % {59,55,53}
    localparam ST_UPDATE    = 4'd8;   // Compare distance, update best
    localparam ST_CAND_NEXT = 4'd11;  // Advance to next candidate k
    localparam ST_NEXT      = 4'd9;   // Advance to next pair
    localparam ST_DONE      = 4'd10;  // Output result

    localparam NRM_MAX_ERRORS = 2'd2;  // t=2 for 2NRM

    reg [3:0] state;
    reg [3:0] pair_idx;   // 0~14 (15 pairs)
    reg [2:0] cand_k;     // 0~4 (candidate index: X_k = X_base + k*PERIOD)

    // =========================================================================
    // 2. Lookup Tables for 15 Pairs
    //    Each entry: (M_i, M_j, Inv(M_i mod M_j, M_j), idx_i, idx_j, PERIOD)
    // =========================================================================
    reg [8:0]  lut_mi     [0:14];
    reg [8:0]  lut_mj     [0:14];
    reg [7:0]  lut_inv    [0:14];
    reg [2:0]  lut_idx_i  [0:14];
    reg [2:0]  lut_idx_j  [0:14];
    reg [16:0] lut_period [0:14];  // PERIOD = M_i * M_j (17-bit, max 257*256=65792)

    initial begin
        // Pair  0: (257,256) PERIOD=65792
        lut_mi[0]=9'd257; lut_mj[0]=9'd256; lut_inv[0]=8'd1;
        lut_idx_i[0]=3'd0; lut_idx_j[0]=3'd1; lut_period[0]=17'd65792;
        // Pair  1: (257, 61) PERIOD=15677
        lut_mi[1]=9'd257; lut_mj[1]=9'd61;  lut_inv[1]=8'd48;
        lut_idx_i[1]=3'd0; lut_idx_j[1]=3'd2; lut_period[1]=17'd15677;
        // Pair  2: (257, 59) PERIOD=15163
        lut_mi[2]=9'd257; lut_mj[2]=9'd59;  lut_inv[2]=8'd45;
        lut_idx_i[2]=3'd0; lut_idx_j[2]=3'd3; lut_period[2]=17'd15163;
        // Pair  3: (257, 55) PERIOD=14135
        lut_mi[3]=9'd257; lut_mj[3]=9'd55;  lut_inv[3]=8'd3;
        lut_idx_i[3]=3'd0; lut_idx_j[3]=3'd4; lut_period[3]=17'd14135;
        // Pair  4: (257, 53) PERIOD=13621
        lut_mi[4]=9'd257; lut_mj[4]=9'd53;  lut_inv[4]=8'd33;
        lut_idx_i[4]=3'd0; lut_idx_j[4]=3'd5; lut_period[4]=17'd13621;
        // Pair  5: (256, 61) PERIOD=15616
        lut_mi[5]=9'd256; lut_mj[5]=9'd61;  lut_inv[5]=8'd56;
        lut_idx_i[5]=3'd1; lut_idx_j[5]=3'd2; lut_period[5]=17'd15616;
        // Pair  6: (256, 59) PERIOD=15104
        lut_mi[6]=9'd256; lut_mj[6]=9'd59;  lut_inv[6]=8'd3;
        lut_idx_i[6]=3'd1; lut_idx_j[6]=3'd3; lut_period[6]=17'd15104;
        // Pair  7: (256, 55) PERIOD=14080
        lut_mi[7]=9'd256; lut_mj[7]=9'd55;  lut_inv[7]=8'd26;
        lut_idx_i[7]=3'd1; lut_idx_j[7]=3'd4; lut_period[7]=17'd14080;
        // Pair  8: (256, 53) PERIOD=13568
        lut_mi[8]=9'd256; lut_mj[8]=9'd53;  lut_inv[8]=8'd47;
        lut_idx_i[8]=3'd1; lut_idx_j[8]=3'd5; lut_period[8]=17'd13568;
        // Pair  9: ( 61, 59) PERIOD=3599
        lut_mi[9]=9'd61;  lut_mj[9]=9'd59;  lut_inv[9]=8'd30;
        lut_idx_i[9]=3'd2; lut_idx_j[9]=3'd3; lut_period[9]=17'd3599;
        // Pair 10: ( 61, 55) PERIOD=3355
        lut_mi[10]=9'd61; lut_mj[10]=9'd55; lut_inv[10]=8'd46;
        lut_idx_i[10]=3'd2; lut_idx_j[10]=3'd4; lut_period[10]=17'd3355;
        // Pair 11: ( 61, 53) PERIOD=3233
        lut_mi[11]=9'd61; lut_mj[11]=9'd53; lut_inv[11]=8'd20;
        lut_idx_i[11]=3'd2; lut_idx_j[11]=3'd5; lut_period[11]=17'd3233;
        // Pair 12: ( 59, 55) PERIOD=3245
        lut_mi[12]=9'd59; lut_mj[12]=9'd55; lut_inv[12]=8'd14;
        lut_idx_i[12]=3'd3; lut_idx_j[12]=3'd4; lut_period[12]=17'd3245;
        // Pair 13: ( 59, 53) PERIOD=3127
        lut_mi[13]=9'd59; lut_mj[13]=9'd53; lut_inv[13]=8'd9;
        lut_idx_i[13]=3'd3; lut_idx_j[13]=3'd5; lut_period[13]=17'd3127;
        // Pair 14: ( 55, 53) PERIOD=2915
        lut_mi[14]=9'd55; lut_mj[14]=9'd53; lut_inv[14]=8'd27;
        lut_idx_i[14]=3'd4; lut_idx_j[14]=3'd5; lut_period[14]=17'd2915;
    end

    // =========================================================================
    // 3. Received Residues Register Bank
    // =========================================================================
    reg [8:0] recv_r [0:5];  // 9-bit (max 257)

    // =========================================================================
    // 4. CRT Computation Registers
    // =========================================================================
    (* max_fanout = 8 *) reg [8:0]  crt_mi;        // Current M_i
    (* max_fanout = 8 *) reg [8:0]  crt_mj;        // Current M_j
    reg [7:0]  crt_inv;        // Inv(M_i mod M_j, M_j)
    reg [8:0]  crt_ri;         // Received residue for M_i
    reg [8:0]  crt_rj;         // Received residue for M_j
    reg [8:0]  crt_a1;         // = ri (first MRC coefficient)
    reg [8:0]  crt_diff;       // (rj - ri + Mj) % Mj
    reg [7:0]  crt_a2;         // (diff * Inv) % Mj
    reg [16:0] crt_a2mi_prod;  // Registered: a2 * Mi (pipeline break)
    reg [16:0] crt_x_base;     // Base candidate X_0 = ri + Mi * a2
    reg [16:0] crt_x_k;        // Current candidate X_k = X_0 + k*PERIOD
    reg [16:0] crt_period;     // PERIOD = M_i * M_j for current pair

    // =========================================================================
    // 5. Distance Computation Registers
    // =========================================================================
    reg [8:0] cand_r [0:5];  // Candidate residues for current X_k

    // =========================================================================
    // 6. MLD Accumulator
    // =========================================================================
    reg [2:0]  min_dist;
    reg [15:0] best_x;

    // =========================================================================
    // 7. Case-Based Constant Modulo Function (Timing-Safe at 50MHz)
    //    2NRM moduli: {257, 256, 61, 59, 55, 53}
    // =========================================================================
    function automatic [8:0] mod_by_idx(input [16:0] val, input [2:0] idx);
        case (idx)
            3'd0: mod_by_idx = val % 9'd257;
            3'd1: mod_by_idx = val % 9'd256;
            3'd2: mod_by_idx = val % 9'd61;
            3'd3: mod_by_idx = val % 9'd59;
            3'd4: mod_by_idx = val % 9'd55;
            3'd5: mod_by_idx = val % 9'd53;
            default: mod_by_idx = 9'd0;
        endcase
    endfunction

    // =========================================================================
    // 8. Combinational CRT Intermediate Signals
    // =========================================================================

    // ST_CRT_S2: diff = (rj - ri + Mj) % Mj
    wire [9:0] diff_raw  = {1'b0, crt_rj} + {1'b0, crt_mj} - {1'b0, crt_ri};
    wire [8:0] diff_comb = (diff_raw >= {1'b0, crt_mj}) ?
                           (diff_raw - {1'b0, crt_mj}) : diff_raw[8:0];

    // ST_CRT_S3: a2 = (diff * Inv) % Mj
    wire [16:0] s3_prod = {8'b0, crt_diff} * {9'b0, crt_inv};
    wire [8:0]  s3_a2   = mod_by_idx(s3_prod[16:0], lut_idx_j[pair_idx]);

    // ST_CRT_S4: X_base = ri + Mi * a2 (using registered a2mi_prod)
    wire [16:0] s4_x = {8'b0, crt_a1} + crt_a2mi_prod;

    // =========================================================================
    // 9. Combinational Distance Computation (uses crt_x_k)
    // =========================================================================
    // DIST_S1: cand_r[0..2] = X_k % {257, 256, 61}
    wire [8:0] ds1_r0 = crt_x_k[15:0] % 9'd257;
    wire [8:0] ds1_r1 = crt_x_k[15:0] % 9'd256;
    wire [8:0] ds1_r2 = crt_x_k[15:0] % 9'd61;
    // DIST_S2: cand_r[3..5] = X_k % {59, 55, 53}
    wire [8:0] ds2_r3 = crt_x_k[15:0] % 9'd59;
    wire [8:0] ds2_r4 = crt_x_k[15:0] % 9'd55;
    wire [8:0] ds2_r5 = crt_x_k[15:0] % 9'd53;

    // Hamming distance: count mismatches across all 6 moduli
    wire [2:0] dist_comb =
        ((cand_r[0] != recv_r[0]) ? 3'd1 : 3'd0) +
        ((cand_r[1] != recv_r[1]) ? 3'd1 : 3'd0) +
        ((cand_r[2] != recv_r[2]) ? 3'd1 : 3'd0) +
        ((cand_r[3] != recv_r[3]) ? 3'd1 : 3'd0) +
        ((cand_r[4] != recv_r[4]) ? 3'd1 : 3'd0) +
        ((cand_r[5] != recv_r[5]) ? 3'd1 : 3'd0);

    // Next candidate X_{k+1} = X_k + PERIOD
    wire [17:0] x_next = {1'b0, crt_x_k} + {1'b0, crt_period};

    // =========================================================================
    // 10. Main FSM
    // =========================================================================
    integer ii;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            pair_idx     <= 4'd0;
            cand_k       <= 3'd0;
            min_dist     <= 3'd6;
            best_x       <= 16'd0;
            crt_mi       <= 9'd1;
            crt_mj       <= 9'd1;
            crt_inv      <= 8'd1;
            crt_ri       <= 9'd0;
            crt_rj       <= 9'd0;
            crt_a1       <= 9'd0;
            crt_diff     <= 9'd0;
            crt_a2       <= 8'd0;
            crt_a2mi_prod <= 17'd0;
            crt_x_base   <= 17'd0;
            crt_x_k      <= 17'd0;
            crt_period   <= 17'd0;
            for (ii = 0; ii < 6; ii = ii + 1) begin
                recv_r[ii] <= 9'd0;
                cand_r[ii] <= 9'd0;
            end
            data_out      <= 16'd0;
            valid         <= 1'b0;
            uncorrectable <= 1'b0;
        end else begin
            valid         <= 1'b0;
            uncorrectable <= 1'b0;

            case (state)

                // =============================================================
                // IDLE: Wait for start pulse
                // =============================================================
                ST_IDLE: begin
                    if (start) state <= ST_LOAD;
                end

                // =============================================================
                // LOAD: Unpack received residues from 64-bit bus
                // =============================================================
                ST_LOAD: begin
                    recv_r[0] <= residues_in[40:32];          // mod 257 (9-bit)
                    recv_r[1] <= {1'b0, residues_in[31:24]};  // mod 256 (8-bit→9-bit)
                    recv_r[2] <= {3'b0, residues_in[23:18]};  // mod  61 (6-bit→9-bit)
                    recv_r[3] <= {3'b0, residues_in[17:12]};  // mod  59 (6-bit→9-bit)
                    recv_r[4] <= {3'b0, residues_in[11:6]};   // mod  55 (6-bit→9-bit)
                    recv_r[5] <= {3'b0, residues_in[5:0]};    // mod  53 (6-bit→9-bit)
                    pair_idx  <= 4'd0;
                    min_dist  <= 3'd6;
                    best_x    <= 16'd0;
                    state     <= ST_CRT_S1;
                end

                // =============================================================
                // CRT_S1: Load current pair parameters from LUT
                // =============================================================
                ST_CRT_S1: begin
                    crt_mi     <= lut_mi[pair_idx];
                    crt_mj     <= lut_mj[pair_idx];
                    crt_inv    <= lut_inv[pair_idx];
                    crt_ri     <= recv_r[lut_idx_i[pair_idx]];
                    crt_rj     <= recv_r[lut_idx_j[pair_idx]];
                    crt_period <= lut_period[pair_idx];
                    state      <= ST_CRT_S2;
                end

                // =============================================================
                // CRT_S2: Compute a1=ri, diff=(rj-ri+Mj)%Mj
                // =============================================================
                ST_CRT_S2: begin
                    crt_a1   <= crt_ri;
                    crt_diff <= diff_comb;
                    state    <= ST_CRT_S3;
                end

                // =============================================================
                // CRT_S3: Compute a2 = (diff * Inv) % Mj
                // =============================================================
                ST_CRT_S3: begin
                    crt_a2 <= s3_a2[7:0];
                    state  <= ST_CRT_S3B;
                end

                // =============================================================
                // CRT_S3B: Register a2*Mi product (pipeline break for timing)
                // =============================================================
                ST_CRT_S3B: begin
                    crt_a2mi_prod <= {9'b0, crt_a2} * crt_mi;  // Full 9-bit Mi
                    state <= ST_CRT_S4;
                end

                // =============================================================
                // CRT_S4: Compute X_base = ri + Mi * a2
                //         Initialize candidate loop: k=0, X_k = X_base
                // =============================================================
                ST_CRT_S4: begin
                    crt_x_base <= s4_x;
                    crt_x_k    <= s4_x;   // Start with k=0
                    cand_k     <= 3'd0;
                    state      <= ST_DIST_S1;
                end

                // =============================================================
                // DIST_S1: Compute candidate residues mod {257, 256, 61}
                //          for current X_k
                // =============================================================
                ST_DIST_S1: begin
                    if (crt_x_k <= 17'd65535) begin
                        cand_r[0] <= ds1_r0;
                        cand_r[1] <= ds1_r1;
                        cand_r[2] <= ds1_r2;
                    end else begin
                        // X_k out of 16-bit range → mark as invalid (max distance)
                        cand_r[0] <= 9'd255;
                        cand_r[1] <= 9'd255;
                        cand_r[2] <= 9'd255;
                    end
                    state <= ST_DIST_S2;
                end

                // =============================================================
                // DIST_S2: Compute candidate residues mod {59, 55, 53}
                // =============================================================
                ST_DIST_S2: begin
                    if (crt_x_k <= 17'd65535) begin
                        cand_r[3] <= ds2_r3;
                        cand_r[4] <= ds2_r4;
                        cand_r[5] <= ds2_r5;
                    end else begin
                        cand_r[3] <= 9'd255;
                        cand_r[4] <= 9'd255;
                        cand_r[5] <= 9'd255;
                    end
                    state <= ST_UPDATE;
                end

                // =============================================================
                // UPDATE: Compare distance, update best candidate
                // =============================================================
                ST_UPDATE: begin
                    if (crt_x_k <= 17'd65535) begin
                        // Only update if X_k is in valid range
                        if (dist_comb < min_dist) begin
                            min_dist <= dist_comb;
                            best_x   <= crt_x_k[15:0];
                        end
                    end
                    state <= ST_CAND_NEXT;
                end

                // =============================================================
                // CAND_NEXT: Advance to next candidate k+1
                //   X_{k+1} = X_k + PERIOD
                //   If X_{k+1} > 65535 OR k==4: done with this pair → ST_NEXT
                //   Otherwise: process next candidate → ST_DIST_S1
                // =============================================================
                ST_CAND_NEXT: begin
                    if (cand_k == 3'd4 || x_next > 18'd65535) begin
                        // All valid candidates for this pair processed
                        state <= ST_NEXT;
                    end else begin
                        // Advance to next candidate
                        cand_k  <= cand_k + 3'd1;
                        crt_x_k <= x_next[16:0];  // X_{k+1} = X_k + PERIOD
                        state   <= ST_DIST_S1;
                    end
                end

                // =============================================================
                // NEXT: Advance to next pair or go to DONE
                // =============================================================
                ST_NEXT: begin
                    if (pair_idx == 4'd14) begin
                        state <= ST_DONE;
                    end else begin
                        pair_idx <= pair_idx + 4'd1;
                        state    <= ST_CRT_S1;
                    end
                end

                // =============================================================
                // DONE: Output result
                // =============================================================
                ST_DONE: begin
                    valid <= 1'b1;
                    if (min_dist <= NRM_MAX_ERRORS) begin
                        data_out      <= best_x;
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
