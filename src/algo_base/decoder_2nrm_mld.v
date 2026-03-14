`timescale 1ns / 1ps

module decoder_2nrm_mld (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    // Input: 41-bit packed residues
    // Order: r257(9), r256(8), r61(6), r59(6), r55(6), r53(6)
    // Bits: [40:32]=r257, [31:24]=r256, [23:18]=r61, [17:12]=r59, [11:6]=r55, [5:0]=r53
    input  wire [40:0] residues_in, 
    
    output reg [15:0] data_out,
    output reg        valid,
    output reg        uncorrectable // 1 if errors > 2 (theoretical limit)
);

    // --- 1. Unpack Residues ---
    wire [8:0] r_257 = residues_in[40:32];
    wire [7:0] r_256 = residues_in[31:24];
    wire [5:0] r_61  = residues_in[23:18];
    wire [5:0] r_59  = residues_in[17:12];
    wire [5:0] r_55  = residues_in[11:6];
    wire [5:0] r_53  = residues_in[5:0];

    // Uniform array for easy indexing (zero-padded to 9 bits for consistency)
    wire [8:0] r_vec [0:5] = '{r_257, r_256, {3'd0, r_61}, {3'd0, r_59}, {3'd0, r_55}, {3'd0, r_53}};
    wire [8:0] m_vec [0:5] = '{9'd257, 9'd256, 9'd61, 9'd59, 9'd55, 9'd53};

    // --- 2. Parallel Channels Signals ---
    wire [15:0] chan_x [0:14];
    wire [3:0]  chan_dist [0:14];
    wire        chan_valid [0:14];

    // --- 3. Generate 15 Parallel Channels with Pre-calculated Constants ---
    genvar i;
    generate
        for (i=0; i<15; i=i+1) begin : gen_channels
            // Map channel index to pair indices (idx1, idx2)
            // 0:(0,1), 1:(0,2), 2:(0,3), 3:(0,4), 4:(0,5)
            // 5:(1,2), 6:(1,3), 7:(1,4), 8:(1,5)
            // 9:(2,3), 10:(2,4), 11:(2,5)
            // 12:(3,4), 13:(3,5)
            // 14:(4,5)
            localparam int IDX1 = (i < 5) ? 0 : (i < 9) ? 1 : (i < 12) ? 2 : (i < 14) ? 3 : 4;
            localparam int IDX2 = (i < 5) ? i+1 : (i < 9) ? i-3 : (i < 12) ? i-6 : (i < 14) ? i-9 : 5;

            // --- Pre-calculated Constants from Python Script ---
            localparam [8:0] P_M1_VAL = 
                (i==0)?9'd257:(i==1)?9'd257:(i==2)?9'd257:(i==3)?9'd257:(i==4)?9'd257:
                (i==5)?9'd256:(i==6)?9'd256:(i==7)?9'd256:(i==8)?9'd256:
                (i==9)?9'd61:(i==10)?9'd61:(i==11)?9'd61:
                (i==12)?9'd59:(i==13)?9'd59:9'd55;

            localparam [8:0] P_M2_VAL = 
                (i==0)?9'd256:(i==1)?9'd61:(i==2)?9'd59:(i==3)?9'd55:(i==4)?9'd53:
                (i==5)?9'd61:(i==6)?9'd59:(i==7)?9'd55:(i==8)?9'd53:
                (i==9)?9'd59:(i==10)?9'd55:(i==11)?9'd53:
                (i==12)?9'd55:(i==13)?9'd53:9'd53;

            localparam [8:0] P_INV_VAL = 
                (i==0)?9'd1:(i==1)?9'd47:(i==2)?9'd45:(i==3)?9'd3:(i==4)?9'd33:
                (i==5)?9'd56:(i==6)?9'd3:(i==7)?9'd26:(i==8)?9'd47:
                (i==9)?9'd30:(i==10)?9'd46:(i==11)?9'd20:
                (i==12)?9'd14:(i==13)?9'd9:9'd27;

            decoder_channel_2nrm_param #(
                .P_M1(P_M1_VAL),
                .P_M2(P_M2_VAL),
                .P_INV_M1_MOD_M2(P_INV_VAL),
                .P_IDX1(IDX1),
                .P_IDX2(IDX2)
            ) u_chan (
                .clk(clk),
                .start(start),
                .r1(r_vec[IDX1]),
                .r2(r_vec[IDX2]),
                .r_all(r_vec),
                .m_all(m_vec),
                .x_out(chan_x[i]),
                .distance(chan_dist[i]),
                .valid(chan_valid[i])
            );
        end
    endgenerate

    // --- 4. Minimum Distance Finder (MLD Decision Logic) ---
    reg [15:0] best_x;
    reg [3:0]  min_dist;
    reg        found_solution;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            min_dist <= 4'd10; // Larger than max possible distance (6)
            best_x <= 0;
            found_solution <= 0;
        end else if (start) begin
            min_dist <= 4'd10;
            best_x <= 0;
            found_solution <= 0;
            
            // Scan all 15 channels to find the one with minimum Hamming distance
            // This loop unrolls completely in synthesis
            for (integer j=0; j<15; j=j+1) begin
                if (chan_valid[j]) begin
                    if (chan_dist[j] < min_dist) begin
                        min_dist <= chan_dist[j];
                        best_x <= chan_x[j];
                        found_solution <= 1;
                    end
                end
            end
        end
    end

    // --- 5. Output Pipeline & Final Decision ---
    // Align valid signal with the latency of the finder (1 cycle after start + channel latency)
    // Assuming channel latency is 1 cycle (combinational logic registered at end)
    reg [1:0] pipe_start;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pipe_start <= 0;
        else pipe_start <= {pipe_start[0], start};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= 0;
            uncorrectable <= 0;
            data_out <= 0;
        end else begin
            valid <= 0;
            // Output valid when the pipeline completes
            if (pipe_start[1]) begin 
                if (found_solution && min_dist <= 3'd2) begin
                    // Theoretical limit for 2NRM is t=2
                    data_out <= best_x;
                    uncorrectable <= 0;
                    valid <= 1;
                end else begin
                    // Errors > 2, cannot correct reliably
                    data_out <= 16'd0;
                    uncorrectable <= 1;
                    valid <= 1; // Indicate completion but flag as uncorrectable
                end
            end
        end
    end

endmodule

// ============================================================================
// Sub-module: Parameterized Single Decoding Channel
// Performs CRT reconstruction and Hamming distance calculation
// ============================================================================
module decoder_channel_2nrm_param #(
    parameter [8:0] P_M1 = 9'd257,
    parameter [8:0] P_M2 = 9'd256,
    parameter [8:0] P_INV_M1_MOD_M2 = 9'd1, // (P_M1^-1) % P_M2
    parameter [2:0] P_IDX1 = 3'd0,
    parameter [2:0] P_IDX2 = 3'd1
) (
    input  wire       clk,
    input  wire       start,
    input  wire [8:0] r1, r2, 
    input  wire [8:0] r_all [0:5],
    input  wire [8:0] m_all [0:5],
    
    output reg [15:0] x_out,
    output reg [3:0]  distance,
    output reg        valid
);

    // --- CRT Calculation (Combinational) ---
    // Formula: X = r1 + P_M1 * ((r2 - r1) * P_INV_M1_MOD_M2 % P_M2)
    // All parameters are constants, so synthesizer optimizes modulo and multiplication
    
    wire [8:0] diff = (r2 >= r1) ? (r2 - r1) : (r2 + P_M2 - r1);
    wire [16:0] term = diff * P_INV_M1_MOD_M2;
    wire [8:0] k = term % P_M2; // Optimized to constant modulo logic
    wire [16:0] x_cand = r1 + P_M1 * k;
    
    // --- Hamming Distance Calculation ---
    // Count mismatches between re-encoded x_cand and received r_all
    // We only need to check the 4 redundant moduli (those not used for reconstruction)
    // because the 2 used for reconstruction will always match by definition.
    
    reg [3:0] dist_cnt;
    
    always @(posedge clk) begin
        if (start) begin
            x_out <= x_cand[15:0]; // Truncate to 16-bit data range
            
            dist_cnt = 0;
            // Check against all 6 moduli, skip the two used for reconstruction
            for (integer j=0; j<6; j=j+1) begin
                if (j != P_IDX1 && j != P_IDX2) begin
                    // Re-calculate residue: x_cand % m_all[j]
                    // m_all[j] is dynamic input, but from a small set. 
                    // Vivado should handle this small modulo efficiently.
                    if (x_cand % m_all[j] != r_all[j]) begin
                        dist_cnt = dist_cnt + 1;
                    end
                end
            end
            distance <= dist_cnt;
            valid <= 1;
        end
    end
endmodule