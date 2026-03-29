// =============================================================================
// File: decoder_2nrm_serial.v
// Description: 2NRM-RRNS Decoder — Sequential FSM MLD (Serial Architecture)
//              Algorithm: Residue Number System with Moduli Set:
//              {257, 256, 61, 59, 55, 53}  (2 information + 4 redundant)
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
// Version: v1.2 (Bug fix: 2-step decomposition for modulo operations in DIST states)
//
// BUG FIX v1.2 (Bug #96):
//   v1.1 computed candidate residues using direct 16-bit modulo operations:
//     ds1_r0 = crt_x_k[15:0] % 9'd257  (~15 CARRY4, ~5ns logic delay)
//     ds1_r2 = crt_x_k[15:0] % 9'd61   (~13 CARRY4, ~4.5ns logic delay)
//   At 50MHz (20ns period), these paths combined with routing delay may exceed
//   the timing budget, causing cand_r[] to capture wrong values and dist_comb
//   to be incorrect, leading to MLD selecting wrong candidates.
//   This explains the ~10% SR difference between Parallel and Serial at BER=10%.
//
//   FIX: Apply 2-step decomposition (same as decoder_2nrm.v Parallel):
//     % 257: step1 = x_lo - x_hi + 257 (~2 CARRY4), then step1 % 257 (~2-3 CARRY4)
//     % 61:  step1 = x_hi*12 + x_lo    (~5 CARRY4), then step1 % 61  (~3-4 CARRY4)
//     % 59:  step1 = x_hi*20 + x_lo    (~5 CARRY4), then step1 % 59  (~4-5 CARRY4)
//     % 55:  step1 = x_hi*36 + x_lo    (~5 CARRY4), then step1 % 55  (~4-5 CARRY4)
//     % 53:  step1 = x_hi*44 + x_lo    (~5 CARRY4), then step1 % 53  (~4-5 CARRY4)
//     % 256: x[7:0] (trivial, no CARRY4)
//   Each step is now safely within 10ns budget.
//   New states: ST_DIST_S1B (register step1 for r0/r2), ST_DIST_S2B (register step1 for r3/r4/r5)
//   Total latency per candidate: 6 states (was 4), increase ~2 cycles per candidate.
//
// BUG FIX v1.1:
//   v1.0 only computed k=0 candidate (X = ri + Mi*a2) for each pair.
//   For large X values, the correct answer may be X + k*PERIOD (k=1~4).
//
// ALGORITHM: Sequential MLD over C(6,2)=15 modulus pairs × up to 5 candidates
//   For each pair (M_i, M_j):
//     PERIOD = M_i * M_j
//     For k = 0, 1, 2, 3, 4:
//       X_k = X_0 + k * PERIOD  (where X_0 = ri + Mi * a2)
//       If X_k > 65535: skip (out of 16-bit data range)
//       Compute residues of X_k modulo all 6 moduli (2-step decomposition)
//       Compute Hamming distance
//       Update best candidate if distance is smaller
//   Select X with minimum distance. If min_dist > 2 → uncorrectable.
//
// FSM STATES (per pair, per candidate):
//   IDLE → LOAD → CRT_S1 → CRT_S2 → CRT_S3 → CRT_S3B → CRT_S4
//        → CAND_LOOP: for k=0..4:
//            → DIST_S1 → DIST_S1B → DIST_S2 → DIST_S2B → UPDATE → CAND_NEXT
//        → NEXT (advance pair_idx) → ... → DONE
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
    localparam ST_CRT_S3    = 4'd4;   // Register s3_prod = diff * Inv (pipeline break)
    localparam ST_CRT_S3B   = 4'd13;  // Compute a2 = s3_prod % Mj, then register a2*Mi
    localparam ST_CRT_S4    = 4'd5;   // Compute X_base = ri + Mi * a2
    localparam ST_DIST_S1   = 4'd6;   // Compute step1 values for r0(257), r1(256), r2(61)
    localparam ST_DIST_S1B  = 4'd12;  // Register step1 results, compute final r0/r1/r2
    localparam ST_DIST_S2   = 4'd7;   // Compute step1 values for r3(59), r4(55), r5(53)
    localparam ST_DIST_S2B  = 4'd14;  // Register step1 results, compute final r3/r4/r5
    localparam ST_UPDATE    = 4'd8;   // Compare distance, update best
    localparam ST_CAND_NEXT = 4'd11;  // Advance to next candidate k
    localparam ST_NEXT      = 4'd9;   // Advance to next pair
    localparam ST_DONE      = 4'd10;  // Output result

    localparam NRM_MAX_ERRORS = 2'd2;  // t=2 for 2NRM

    reg [3:0] state;
    reg [3:0] pair_idx;   // 0~14 (15 pairs)
    // Bug #102 fix: extend cand_k from 3-bit (0..4) to 5-bit (0..22)
    // The old limit cand_k==4 stopped enumeration too early for small-modulus pairs
    // (e.g., (55,53) with PERIOD=2915 needs k up to 22 to cover all 16-bit X values).
    // Fix: remove the fixed k=4 limit; rely solely on x_next > 65535 as termination.
    reg [4:0] cand_k;     // 0~22 (candidate index: X_k = X_base + k*PERIOD)

    // =========================================================================
    // 2. Lookup Tables for 15 Pairs
    // =========================================================================
    reg [8:0]  lut_mi     [0:14];
    reg [8:0]  lut_mj     [0:14];
    reg [7:0]  lut_inv    [0:14];
    reg [2:0]  lut_idx_i  [0:14];
    reg [2:0]  lut_idx_j  [0:14];
    reg [16:0] lut_period [0:14];

    initial begin
        // Pair  0: (257,256) PERIOD=65792
        lut_mi[0]=9'd257; lut_mj[0]=9'd256; lut_inv[0]=8'd1;
        lut_idx_i[0]=3'd0; lut_idx_j[0]=3'd1; lut_period[0]=17'd65792;
        // Pair  1: (257, 61) PERIOD=15677 — inv=47: inv(13,61)=47 (13*47=611=10*61+1)
        lut_mi[1]=9'd257; lut_mj[1]=9'd61;  lut_inv[1]=8'd47;
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
    (* max_fanout = 8 *) reg [8:0]  crt_mi;
    (* max_fanout = 8 *) reg [8:0]  crt_mj;
    reg [7:0]  crt_inv;
    reg [8:0]  crt_ri;
    reg [8:0]  crt_rj;
    reg [8:0]  crt_a1;
    reg [8:0]  crt_diff;
    reg [16:0] crt_s3_prod;    // Registered: diff * Inv (pipeline break)
    reg [2:0]  crt_idx_j;      // Registered: lut_idx_j[pair_idx]
    reg [7:0]  crt_a2;
    reg [16:0] crt_a2mi_prod;
    reg [16:0] crt_x_base;
    reg [16:0] crt_x_k;
    reg [16:0] crt_period;

    // =========================================================================
    // 5. Distance Computation Registers
    //    2-step decomposition: step1 registers + final cand_r registers
    // =========================================================================
    reg [8:0]  cand_r [0:5];   // Final candidate residues for current X_k

    // Step1 intermediate registers for 2-step decomposition
    // ST_DIST_S1 computes step1 values, ST_DIST_S1B computes final residues
    reg [8:0]  step1_257_reg;  // x_lo - x_hi + 257 (9-bit, range 1..511)
    reg [7:0]  step1_256_reg;  // x[7:0] (trivial, = % 256)
    reg [11:0] step1_61_reg;   // x_hi*12 + x_lo (12-bit, max 3315)
    // ST_DIST_S2 computes step1 values, ST_DIST_S2B computes final residues
    reg [12:0] step1_59_reg;   // x_hi*20 + x_lo (13-bit, max 5355)
    reg [13:0] step1_55_reg;   // x_hi*36 + x_lo (14-bit, max 9435)
    reg [13:0] step1_53_reg;   // x_hi*44 + x_lo (14-bit, max 11475)
    // Validity flag: whether crt_x_k was in range when step1 was computed
    reg        dist_valid_s1;  // Latched validity from ST_DIST_S1
    reg        dist_valid_s2;  // Latched validity from ST_DIST_S2

    // =========================================================================
    // 6. MLD Accumulator
    // =========================================================================
    reg [2:0]  min_dist;
    reg [15:0] best_x;

    // =========================================================================
    // 7. Case-Based Constant Modulo Function
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

    // ST_CRT_S3: register s3_prod = diff * Inv
    wire [16:0] s3_prod_comb = {8'b0, crt_diff} * {9'b0, crt_inv};
    // ST_CRT_S3B: compute a2 = s3_prod % Mj from registered product
    wire [8:0]  s3_a2_comb   = mod_by_idx(crt_s3_prod[16:0], crt_idx_j);

    // ST_CRT_S4: X_base = ri + Mi * a2
    wire [16:0] s4_x = {8'b0, crt_a1} + crt_a2mi_prod;

    // =========================================================================
    // 9. 2-Step Decomposition for Distance Computation
    //
    // ST_DIST_S1: Compute step1 values for r0(257), r1(256), r2(61)
    //   % 257: step1 = x_lo - x_hi + 257  (9-bit, ~2 CARRY4, ~1ns)
    //          Mathematical: 256 ≡ -1 (mod 257), so x%257 = (x_lo - x_hi + 257)%257
    //   % 256: step1 = x[7:0]  (trivial)
    //   % 61:  step1 = x_hi*12 + x_lo  (12-bit, ~5 CARRY4, ~1.5ns)
    //          Mathematical: 256%61=12, so x%61 = (x_hi*12 + x_lo)%61
    //
    // ST_DIST_S1B: Register step1 values, compute final residues
    //   r0 = step1_257_reg % 257  (9-bit input, ~2-3 CARRY4, ~1ns)
    //   r1 = step1_256_reg        (already final)
    //   r2 = step1_61_reg % 61   (12-bit input, ~3-4 CARRY4, ~1.5ns)
    //
    // ST_DIST_S2: Compute step1 values for r3(59), r4(55), r5(53)
    //   % 59: step1 = x_hi*20 + x_lo  (13-bit, ~5 CARRY4, ~1.5ns)
    //   % 55: step1 = x_hi*36 + x_lo  (14-bit, ~5 CARRY4, ~1.5ns)
    //   % 53: step1 = x_hi*44 + x_lo  (14-bit, ~5 CARRY4, ~1.5ns)
    //
    // ST_DIST_S2B: Register step1 values, compute final residues
    //   r3 = step1_59_reg % 59  (13-bit input, ~4-5 CARRY4, ~1.5ns)
    //   r4 = step1_55_reg % 55  (14-bit input, ~4-5 CARRY4, ~1.5ns)
    //   r5 = step1_53_reg % 53  (14-bit input, ~4-5 CARRY4, ~1.5ns)
    // =========================================================================

    // ST_DIST_S1 combinational: step1 values for r0/r1/r2
    wire [8:0]  ds1_step1_257 = {1'b0, crt_x_k[7:0]} - {1'b0, crt_x_k[15:8]} + 9'd257;
    wire [7:0]  ds1_step1_256 = crt_x_k[7:0];  // % 256 = x[7:0] (trivial)
    wire [11:0] ds1_step1_61  = ({4'd0, crt_x_k[15:8]} * 12'd12) + {4'd0, crt_x_k[7:0]};

    // ST_DIST_S1B combinational: final r0/r1/r2 from registered step1
    wire [8:0] ds1b_r0 = step1_257_reg % 9'd257;   // 9-bit input → ~2-3 CARRY4
    wire [8:0] ds1b_r1 = {1'b0, step1_256_reg};    // trivial
    wire [8:0] ds1b_r2 = step1_61_reg % 9'd61;     // 12-bit input → ~3-4 CARRY4

    // ST_DIST_S2 combinational: step1 values for r3/r4/r5
    wire [12:0] ds2_step1_59 = ({5'd0, crt_x_k[15:8]} * 13'd20) + {5'd0, crt_x_k[7:0]};
    wire [13:0] ds2_step1_55 = ({6'd0, crt_x_k[15:8]} * 14'd36) + {6'd0, crt_x_k[7:0]};
    wire [13:0] ds2_step1_53 = ({6'd0, crt_x_k[15:8]} * 14'd44) + {6'd0, crt_x_k[7:0]};

    // ST_DIST_S2B combinational: final r3/r4/r5 from registered step1
    wire [8:0] ds2b_r3 = step1_59_reg % 9'd59;     // 13-bit input → ~4-5 CARRY4
    wire [8:0] ds2b_r4 = step1_55_reg % 9'd55;     // 14-bit input → ~4-5 CARRY4
    wire [8:0] ds2b_r5 = step1_53_reg % 9'd53;     // 14-bit input → ~4-5 CARRY4

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
            state         <= ST_IDLE;
            pair_idx      <= 4'd0;
            cand_k        <= 3'd0;
            min_dist      <= 3'd6;
            best_x        <= 16'd0;
            crt_mi        <= 9'd1;
            crt_mj        <= 9'd1;
            crt_inv       <= 8'd1;
            crt_ri        <= 9'd0;
            crt_rj        <= 9'd0;
            crt_a1        <= 9'd0;
            crt_diff      <= 9'd0;
            crt_s3_prod   <= 17'd0;
            crt_idx_j     <= 3'd0;
            crt_a2        <= 8'd0;
            crt_a2mi_prod <= 17'd0;
            crt_x_base    <= 17'd0;
            crt_x_k       <= 17'd0;
            crt_period    <= 17'd0;
            step1_257_reg <= 9'd0;
            step1_256_reg <= 8'd0;
            step1_61_reg  <= 12'd0;
            step1_59_reg  <= 13'd0;
            step1_55_reg  <= 14'd0;
            step1_53_reg  <= 14'd0;
            dist_valid_s1 <= 1'b0;
            dist_valid_s2 <= 1'b0;
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

                ST_IDLE: begin
                    if (start) state <= ST_LOAD;
                end

                ST_LOAD: begin
                    recv_r[0] <= residues_in[40:32];
                    recv_r[1] <= {1'b0, residues_in[31:24]};
                    recv_r[2] <= {3'b0, residues_in[23:18]};
                    recv_r[3] <= {3'b0, residues_in[17:12]};
                    recv_r[4] <= {3'b0, residues_in[11:6]};
                    recv_r[5] <= {3'b0, residues_in[5:0]};
                    pair_idx  <= 4'd0;
                    min_dist  <= 3'd6;
                    best_x    <= 16'd0;
                    state     <= ST_CRT_S1;
                end

                ST_CRT_S1: begin
                    crt_mi     <= lut_mi[pair_idx];
                    crt_mj     <= lut_mj[pair_idx];
                    crt_inv    <= lut_inv[pair_idx];
                    crt_ri     <= recv_r[lut_idx_i[pair_idx]];
                    crt_rj     <= recv_r[lut_idx_j[pair_idx]];
                    crt_period <= lut_period[pair_idx];
                    state      <= ST_CRT_S2;
                end

                ST_CRT_S2: begin
                    crt_a1   <= crt_ri;
                    crt_diff <= diff_comb;
                    state    <= ST_CRT_S3;
                end

                // ST_CRT_S3: Register s3_prod = diff * Inv (pipeline break)
                ST_CRT_S3: begin
                    crt_s3_prod <= s3_prod_comb;
                    crt_idx_j   <= lut_idx_j[pair_idx];
                    state       <= ST_CRT_S3B;
                end

                // ST_CRT_S3B: Compute a2 = s3_prod % Mj, register a2*Mi
                ST_CRT_S3B: begin
                    crt_a2        <= s3_a2_comb[7:0];
                    crt_a2mi_prod <= {9'b0, s3_a2_comb[7:0]} * crt_mi;
                    state         <= ST_CRT_S4;
                end

                ST_CRT_S4: begin
                    crt_x_base <= s4_x;
                    crt_x_k    <= s4_x;
                    cand_k     <= 3'd0;
                    state      <= ST_DIST_S1;
                end

                // =============================================================
                // ST_DIST_S1: Compute step1 values for r0(257), r1(256), r2(61)
                //   step1_257 = x_lo - x_hi + 257  (~2 CARRY4, ~1ns)
                //   step1_256 = x[7:0]              (trivial)
                //   step1_61  = x_hi*12 + x_lo      (~5 CARRY4, ~1.5ns)
                // =============================================================
                ST_DIST_S1: begin
                    dist_valid_s1 <= (crt_x_k <= 17'd65535);
                    if (crt_x_k <= 17'd65535) begin
                        step1_257_reg <= ds1_step1_257;
                        step1_256_reg <= ds1_step1_256;
                        step1_61_reg  <= ds1_step1_61;
                    end else begin
                        step1_257_reg <= 9'd255;  // Invalid marker
                        step1_256_reg <= 8'd255;
                        step1_61_reg  <= 12'd255;
                    end
                    state <= ST_DIST_S1B;
                end

                // =============================================================
                // ST_DIST_S1B: Compute final r0/r1/r2 from registered step1
                //   r0 = step1_257_reg % 257  (9-bit input, ~2-3 CARRY4, ~1ns)
                //   r1 = step1_256_reg        (trivial)
                //   r2 = step1_61_reg % 61    (12-bit input, ~3-4 CARRY4, ~1.5ns)
                // =============================================================
                ST_DIST_S1B: begin
                    if (dist_valid_s1) begin
                        cand_r[0] <= ds1b_r0;
                        cand_r[1] <= ds1b_r1;
                        cand_r[2] <= ds1b_r2;
                    end else begin
                        cand_r[0] <= 9'd255;
                        cand_r[1] <= 9'd255;
                        cand_r[2] <= 9'd255;
                    end
                    state <= ST_DIST_S2;
                end

                // =============================================================
                // ST_DIST_S2: Compute step1 values for r3(59), r4(55), r5(53)
                //   step1_59 = x_hi*20 + x_lo  (~5 CARRY4, ~1.5ns)
                //   step1_55 = x_hi*36 + x_lo  (~5 CARRY4, ~1.5ns)
                //   step1_53 = x_hi*44 + x_lo  (~5 CARRY4, ~1.5ns)
                // =============================================================
                ST_DIST_S2: begin
                    dist_valid_s2 <= (crt_x_k <= 17'd65535);
                    if (crt_x_k <= 17'd65535) begin
                        step1_59_reg <= ds2_step1_59;
                        step1_55_reg <= ds2_step1_55;
                        step1_53_reg <= ds2_step1_53;
                    end else begin
                        step1_59_reg <= 13'd255;
                        step1_55_reg <= 14'd255;
                        step1_53_reg <= 14'd255;
                    end
                    state <= ST_DIST_S2B;
                end

                // =============================================================
                // ST_DIST_S2B: Compute final r3/r4/r5 from registered step1
                //   r3 = step1_59_reg % 59  (13-bit input, ~4-5 CARRY4, ~1.5ns)
                //   r4 = step1_55_reg % 55  (14-bit input, ~4-5 CARRY4, ~1.5ns)
                //   r5 = step1_53_reg % 53  (14-bit input, ~4-5 CARRY4, ~1.5ns)
                // =============================================================
                ST_DIST_S2B: begin
                    if (dist_valid_s2) begin
                        cand_r[3] <= ds2b_r3;
                        cand_r[4] <= ds2b_r4;
                        cand_r[5] <= ds2b_r5;
                    end else begin
                        cand_r[3] <= 9'd255;
                        cand_r[4] <= 9'd255;
                        cand_r[5] <= 9'd255;
                    end
                    state <= ST_UPDATE;
                end

                ST_UPDATE: begin
                    if (crt_x_k <= 17'd65535) begin
                        if (dist_comb < min_dist) begin
                            min_dist <= dist_comb;
                            best_x   <= crt_x_k[15:0];
                        end
                    end
                    state <= ST_CAND_NEXT;
                end

                // Bug #102 fix: remove fixed k=4 limit; rely solely on x_next > 65535
                // The old condition (cand_k == 4) stopped enumeration too early for
                // small-modulus pairs (e.g., (55,53) PERIOD=2915 needs k up to 22).
                // Now the loop continues until X exceeds 65535, which correctly handles
                // all pairs. For large-modulus pairs (PERIOD >= 13568), x_next > 65535
                // will trigger after k=4 anyway, so behavior is unchanged for those pairs.
                ST_CAND_NEXT: begin
                    if (x_next > 18'd65535) begin
                        state <= ST_NEXT;
                    end else begin
                        cand_k  <= cand_k + 5'd1;
                        crt_x_k <= x_next[16:0];
                        state   <= ST_DIST_S1;
                    end
                end

                ST_NEXT: begin
                    if (pair_idx == 4'd14) begin
                        state <= ST_DONE;
                    end else begin
                        pair_idx <= pair_idx + 4'd1;
                        state    <= ST_CRT_S1;
                    end
                end

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
