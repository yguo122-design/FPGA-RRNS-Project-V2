// =============================================================================
// File: decoder_3nrm.v
// Description: 3NRM-RRNS Decoder - FSM Sequential MRC Architecture
//              Algorithm: Residue Number System with Moduli Set:
//              Non-redundant: {64, 63, 65}
//              Redundant:     {31, 29, 23, 19, 17, 11}
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
// Version: v3.0 (Timing Fix: Case-based constant modulo replaces dynamic modulo)
//
// TIMING FIX (v3.0 vs v2.0):
//   Root cause: Dynamic modulo (e.g., prod % mrc_mj where mrc_mj is a register)
//   synthesizes to a full divider circuit with ~45-51 logic levels (~18-21ns),
//   exceeding the 20ns clock period at 50MHz. WNS = -14.235ns.
//
//   Fix: All modulo operations use case-based constant modulo functions.
//   Each case branch has a compile-time constant modulus, allowing Vivado to
//   optimize to ~5-8 LUT levels (~2-3ns). Expected WNS > 0 at 50MHz.
//
// ARCHITECTURE: Single MRC engine + FSM iterates through all 84 triplets.
//   - LUT: ~1500-3000 (case-based modulo is more LUT-efficient than dynamic)
//   - Latency: ~842 clock cycles (well within 10,000-cycle watchdog)
//
// INPUT BIT LAYOUT (48 bits valid, right-aligned in 64-bit bus):
//   [63:48] = padding (ignored)
//   [47:42] = r0 = received residue mod 64  (6 bits)
//   [41:36] = r1 = received residue mod 63  (6 bits)
//   [35:29] = r2 = received residue mod 65  (7 bits)
//   [28:24] = r3 = received residue mod 31  (5 bits)
//   [23:19] = r4 = received residue mod 29  (5 bits)
//   [18:14] = r5 = received residue mod 23  (5 bits)
//   [13:9]  = r6 = received residue mod 19  (5 bits)
//   [8:4]   = r7 = received residue mod 17  (5 bits)
//   [3:0]   = r8 = received residue mod 11  (4 bits)
// =============================================================================

`timescale 1ns / 1ps

module decoder_3nrm (
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
    localparam ST_IDLE    = 4'd0;
    localparam ST_LOAD    = 4'd1;
    localparam ST_MRC_S1  = 4'd2;
    localparam ST_MRC_S2  = 4'd3;
    localparam ST_MRC_S3  = 4'd4;
    localparam ST_MRC_S4  = 4'd5;
    localparam ST_MRC_S5  = 4'd6;
    localparam ST_DIST_S1 = 4'd7;
    localparam ST_DIST_S2 = 4'd8;
    localparam ST_DIST_S3 = 4'd9;
    localparam ST_UPDATE  = 4'd10;
    localparam ST_NEXT    = 4'd11;
    localparam ST_DONE    = 4'd12;

    localparam NRM_MAX_ERRORS = 3;

    reg [3:0] state;
    reg [6:0] trip_idx;  // 0..83: current triplet index

    // =========================================================================
    // 2. Lookup Tables for 84 Triplets (synthesized as ROM/LUTRAM)
    // =========================================================================
    reg [6:0] lut_mi [0:83];
    reg [6:0] lut_mj [0:83];
    reg [6:0] lut_mk [0:83];
    reg [6:0] lut_inv_ij  [0:83];
    reg [6:0] lut_inv_ijk [0:83];
    reg [3:0] lut_idx_i [0:83];
    reg [3:0] lut_idx_j [0:83];
    reg [3:0] lut_idx_k [0:83];

    initial begin
        lut_mi[ 0]=7'd64; lut_mj[ 0]=7'd63; lut_mk[ 0]=7'd65;
        lut_inv_ij[ 0]=7'd1; lut_inv_ijk[ 0]=7'd33;
        lut_idx_i[ 0]=4'd0; lut_idx_j[ 0]=4'd1; lut_idx_k[ 0]=4'd2;
        lut_mi[ 1]=7'd64; lut_mj[ 1]=7'd63; lut_mk[ 1]=7'd31;
        lut_inv_ij[ 1]=7'd1; lut_inv_ijk[ 1]=7'd16;
        lut_idx_i[ 1]=4'd0; lut_idx_j[ 1]=4'd1; lut_idx_k[ 1]=4'd3;
        lut_mi[ 2]=7'd64; lut_mj[ 2]=7'd63; lut_mk[ 2]=7'd29;
        lut_inv_ij[ 2]=7'd1; lut_inv_ijk[ 2]=7'd1;
        lut_idx_i[ 2]=4'd0; lut_idx_j[ 2]=4'd1; lut_idx_k[ 2]=4'd4;
        lut_mi[ 3]=7'd64; lut_mj[ 3]=7'd63; lut_mk[ 3]=7'd23;
        lut_inv_ij[ 3]=7'd1; lut_inv_ijk[ 3]=7'd10;
        lut_idx_i[ 3]=4'd0; lut_idx_j[ 3]=4'd1; lut_idx_k[ 3]=4'd5;
        lut_mi[ 4]=7'd64; lut_mj[ 4]=7'd63; lut_mk[ 4]=7'd19;
        lut_inv_ij[ 4]=7'd1; lut_inv_ijk[ 4]=7'd5;
        lut_idx_i[ 4]=4'd0; lut_idx_j[ 4]=4'd1; lut_idx_k[ 4]=4'd6;
        lut_mi[ 5]=7'd64; lut_mj[ 5]=7'd63; lut_mk[ 5]=7'd17;
        lut_inv_ij[ 5]=7'd1; lut_inv_ijk[ 5]=7'd6;
        lut_idx_i[ 5]=4'd0; lut_idx_j[ 5]=4'd1; lut_idx_k[ 5]=4'd7;
        lut_mi[ 6]=7'd64; lut_mj[ 6]=7'd63; lut_mk[ 6]=7'd11;
        lut_inv_ij[ 6]=7'd1; lut_inv_ijk[ 6]=7'd2;
        lut_idx_i[ 6]=4'd0; lut_idx_j[ 6]=4'd1; lut_idx_k[ 6]=4'd8;
        lut_mi[ 7]=7'd64; lut_mj[ 7]=7'd65; lut_mk[ 7]=7'd31;
        lut_inv_ij[ 7]=7'd64; lut_inv_ijk[ 7]=7'd26;
        lut_idx_i[ 7]=4'd0; lut_idx_j[ 7]=4'd2; lut_idx_k[ 7]=4'd3;
        lut_mi[ 8]=7'd64; lut_mj[ 8]=7'd65; lut_mk[ 8]=7'd29;
        lut_inv_ij[ 8]=7'd64; lut_inv_ijk[ 8]=7'd9;
        lut_idx_i[ 8]=4'd0; lut_idx_j[ 8]=4'd2; lut_idx_k[ 8]=4'd4;
        lut_mi[ 9]=7'd64; lut_mj[ 9]=7'd65; lut_mk[ 9]=7'd23;
        lut_inv_ij[ 9]=7'd64; lut_inv_ijk[ 9]=7'd15;
        lut_idx_i[ 9]=4'd0; lut_idx_j[ 9]=4'd2; lut_idx_k[ 9]=4'd5;
        lut_mi[10]=7'd64; lut_mj[10]=7'd65; lut_mk[10]=7'd19;
        lut_inv_ij[10]=7'd64; lut_inv_ijk[10]=7'd18;
        lut_idx_i[10]=4'd0; lut_idx_j[10]=4'd2; lut_idx_k[10]=4'd6;
        lut_mi[11]=7'd64; lut_mj[11]=7'd65; lut_mk[11]=7'd17;
        lut_inv_ij[11]=7'd64; lut_inv_ijk[11]=7'd10;
        lut_idx_i[11]=4'd0; lut_idx_j[11]=4'd2; lut_idx_k[11]=4'd7;
        lut_mi[12]=7'd64; lut_mj[12]=7'd65; lut_mk[12]=7'd11;
        lut_inv_ij[12]=7'd64; lut_inv_ijk[12]=7'd6;
        lut_idx_i[12]=4'd0; lut_idx_j[12]=4'd2; lut_idx_k[12]=4'd8;
        lut_mi[13]=7'd64; lut_mj[13]=7'd31; lut_mk[13]=7'd29;
        lut_inv_ij[13]=7'd16; lut_inv_ijk[13]=7'd17;
        lut_idx_i[13]=4'd0; lut_idx_j[13]=4'd3; lut_idx_k[13]=4'd4;
        lut_mi[14]=7'd64; lut_mj[14]=7'd31; lut_mk[14]=7'd23;
        lut_inv_ij[14]=7'd16; lut_inv_ijk[14]=7'd4;
        lut_idx_i[14]=4'd0; lut_idx_j[14]=4'd3; lut_idx_k[14]=4'd5;
        lut_mi[15]=7'd64; lut_mj[15]=7'd31; lut_mk[15]=7'd19;
        lut_inv_ij[15]=7'd16; lut_inv_ijk[15]=7'd12;
        lut_idx_i[15]=4'd0; lut_idx_j[15]=4'd3; lut_idx_k[15]=4'd6;
        lut_mi[16]=7'd64; lut_mj[16]=7'd31; lut_mk[16]=7'd17;
        lut_inv_ij[16]=7'd16; lut_inv_ijk[16]=7'd10;
        lut_idx_i[16]=4'd0; lut_idx_j[16]=4'd3; lut_idx_k[16]=4'd7;
        lut_mi[17]=7'd64; lut_mj[17]=7'd31; lut_mk[17]=7'd11;
        lut_inv_ij[17]=7'd16; lut_inv_ijk[17]=7'd3;
        lut_idx_i[17]=4'd0; lut_idx_j[17]=4'd3; lut_idx_k[17]=4'd8;
        lut_mi[18]=7'd64; lut_mj[18]=7'd29; lut_mk[18]=7'd23;
        lut_inv_ij[18]=7'd5; lut_inv_ijk[18]=7'd13;
        lut_idx_i[18]=4'd0; lut_idx_j[18]=4'd4; lut_idx_k[18]=4'd5;
        lut_mi[19]=7'd64; lut_mj[19]=7'd29; lut_mk[19]=7'd19;
        lut_inv_ij[19]=7'd5; lut_inv_ijk[19]=7'd3;
        lut_idx_i[19]=4'd0; lut_idx_j[19]=4'd4; lut_idx_k[19]=4'd6;
        lut_mi[20]=7'd64; lut_mj[20]=7'd29; lut_mk[20]=7'd17;
        lut_inv_ij[20]=7'd5; lut_inv_ijk[20]=7'd6;
        lut_idx_i[20]=4'd0; lut_idx_j[20]=4'd4; lut_idx_k[20]=4'd7;
        lut_mi[21]=7'd64; lut_mj[21]=7'd29; lut_mk[21]=7'd11;
        lut_inv_ij[21]=7'd5; lut_inv_ijk[21]=7'd7;
        lut_idx_i[21]=4'd0; lut_idx_j[21]=4'd4; lut_idx_k[21]=4'd8;
        lut_mi[22]=7'd64; lut_mj[22]=7'd23; lut_mk[22]=7'd19;
        lut_inv_ij[22]=7'd9; lut_inv_ijk[22]=7'd17;
        lut_idx_i[22]=4'd0; lut_idx_j[22]=4'd5; lut_idx_k[22]=4'd6;
        lut_mi[23]=7'd64; lut_mj[23]=7'd23; lut_mk[23]=7'd17;
        lut_inv_ij[23]=7'd9; lut_inv_ijk[23]=7'd12;
        lut_idx_i[23]=4'd0; lut_idx_j[23]=4'd5; lut_idx_k[23]=4'd7;
        lut_mi[24]=7'd64; lut_mj[24]=7'd23; lut_mk[24]=7'd11;
        lut_inv_ij[24]=7'd9; lut_inv_ijk[24]=7'd5;
        lut_idx_i[24]=4'd0; lut_idx_j[24]=4'd5; lut_idx_k[24]=4'd8;
        lut_mi[25]=7'd64; lut_mj[25]=7'd19; lut_mk[25]=7'd17;
        lut_inv_ij[25]=7'd11; lut_inv_ijk[25]=7'd2;
        lut_idx_i[25]=4'd0; lut_idx_j[25]=4'd6; lut_idx_k[25]=4'd7;
        lut_mi[26]=7'd64; lut_mj[26]=7'd19; lut_mk[26]=7'd11;
        lut_inv_ij[26]=7'd11; lut_inv_ijk[26]=7'd2;
        lut_idx_i[26]=4'd0; lut_idx_j[26]=4'd6; lut_idx_k[26]=4'd8;
        lut_mi[27]=7'd64; lut_mj[27]=7'd17; lut_mk[27]=7'd11;
        lut_inv_ij[27]=7'd4; lut_inv_ijk[27]=7'd10;
        lut_idx_i[27]=4'd0; lut_idx_j[27]=4'd7; lut_idx_k[27]=4'd8;
        lut_mi[28]=7'd63; lut_mj[28]=7'd65; lut_mk[28]=7'd31;
        lut_inv_ij[28]=7'd32; lut_inv_ijk[28]=7'd21;
        lut_idx_i[28]=4'd1; lut_idx_j[28]=4'd2; lut_idx_k[28]=4'd3;
        lut_mi[29]=7'd63; lut_mj[29]=7'd65; lut_mk[29]=7'd29;
        lut_inv_ij[29]=7'd32; lut_inv_ijk[29]=7'd5;
        lut_idx_i[29]=4'd1; lut_idx_j[29]=4'd2; lut_idx_k[29]=4'd4;
        lut_mi[30]=7'd63; lut_mj[30]=7'd65; lut_mk[30]=7'd23;
        lut_inv_ij[30]=7'd32; lut_inv_ijk[30]=7'd1;
        lut_idx_i[30]=4'd1; lut_idx_j[30]=4'd2; lut_idx_k[30]=4'd5;
        lut_mi[31]=7'd63; lut_mj[31]=7'd65; lut_mk[31]=7'd19;
        lut_inv_ij[31]=7'd32; lut_inv_ijk[31]=7'd2;
        lut_idx_i[31]=4'd1; lut_idx_j[31]=4'd2; lut_idx_k[31]=4'd6;
        lut_mi[32]=7'd63; lut_mj[32]=7'd65; lut_mk[32]=7'd17;
        lut_inv_ij[32]=7'd32; lut_inv_ijk[32]=7'd8;
        lut_idx_i[32]=4'd1; lut_idx_j[32]=4'd2; lut_idx_k[32]=4'd7;
        lut_mi[33]=7'd63; lut_mj[33]=7'd65; lut_mk[33]=7'd11;
        lut_inv_ij[33]=7'd32; lut_inv_ijk[33]=7'd4;
        lut_idx_i[33]=4'd1; lut_idx_j[33]=4'd2; lut_idx_k[33]=4'd8;
        lut_mi[34]=7'd63; lut_mj[34]=7'd31; lut_mk[34]=7'd29;
        lut_inv_ij[34]=7'd1; lut_inv_ijk[34]=7'd3;
        lut_idx_i[34]=4'd1; lut_idx_j[34]=4'd3; lut_idx_k[34]=4'd4;
        lut_mi[35]=7'd63; lut_mj[35]=7'd31; lut_mk[35]=7'd23;
        lut_inv_ij[35]=7'd1; lut_inv_ijk[35]=7'd11;
        lut_idx_i[35]=4'd1; lut_idx_j[35]=4'd3; lut_idx_k[35]=4'd5;
        lut_mi[36]=7'd63; lut_mj[36]=7'd31; lut_mk[36]=7'd19;
        lut_inv_ij[36]=7'd1; lut_inv_ijk[36]=7'd14;
        lut_idx_i[36]=4'd1; lut_idx_j[36]=4'd3; lut_idx_k[36]=4'd6;
        lut_mi[37]=7'd63; lut_mj[37]=7'd31; lut_mk[37]=7'd17;
        lut_inv_ij[37]=7'd1; lut_inv_ijk[37]=7'd8;
        lut_idx_i[37]=4'd1; lut_idx_j[37]=4'd3; lut_idx_k[37]=4'd7;
        lut_mi[38]=7'd63; lut_mj[38]=7'd31; lut_mk[38]=7'd11;
        lut_inv_ij[38]=7'd1; lut_inv_ijk[38]=7'd2;
        lut_idx_i[38]=4'd1; lut_idx_j[38]=4'd3; lut_idx_k[38]=4'd8;
        lut_mi[39]=7'd63; lut_mj[39]=7'd29; lut_mk[39]=7'd23;
        lut_inv_ij[39]=7'd6; lut_inv_ijk[39]=7'd7;
        lut_idx_i[39]=4'd1; lut_idx_j[39]=4'd4; lut_idx_k[39]=4'd5;
        lut_mi[40]=7'd63; lut_mj[40]=7'd29; lut_mk[40]=7'd19;
        lut_inv_ij[40]=7'd6; lut_inv_ijk[40]=7'd13;
        lut_idx_i[40]=4'd1; lut_idx_j[40]=4'd4; lut_idx_k[40]=4'd6;
        lut_mi[41]=7'd63; lut_mj[41]=7'd29; lut_mk[41]=7'd17;
        lut_inv_ij[41]=7'd6; lut_inv_ijk[41]=7'd15;
        lut_idx_i[41]=4'd1; lut_idx_j[41]=4'd4; lut_idx_k[41]=4'd7;
        lut_mi[42]=7'd63; lut_mj[42]=7'd29; lut_mk[42]=7'd11;
        lut_inv_ij[42]=7'd6; lut_inv_ijk[42]=7'd1;
        lut_idx_i[42]=4'd1; lut_idx_j[42]=4'd4; lut_idx_k[42]=4'd8;
        lut_mi[43]=7'd63; lut_mj[43]=7'd23; lut_mk[43]=7'd19;
        lut_inv_ij[43]=7'd19; lut_inv_ijk[43]=7'd4;
        lut_idx_i[43]=4'd1; lut_idx_j[43]=4'd5; lut_idx_k[43]=4'd6;
        lut_mi[44]=7'd63; lut_mj[44]=7'd23; lut_mk[44]=7'd17;
        lut_inv_ij[44]=7'd19; lut_inv_ijk[44]=7'd13;
        lut_idx_i[44]=4'd1; lut_idx_j[44]=4'd5; lut_idx_k[44]=4'd7;
        lut_mi[45]=7'd63; lut_mj[45]=7'd23; lut_mk[45]=7'd11;
        lut_inv_ij[45]=7'd19; lut_inv_ijk[45]=7'd7;
        lut_idx_i[45]=4'd1; lut_idx_j[45]=4'd5; lut_idx_k[45]=4'd8;
        lut_mi[46]=7'd63; lut_mj[46]=7'd19; lut_mk[46]=7'd17;
        lut_inv_ij[46]=7'd16; lut_inv_ijk[46]=7'd5;
        lut_idx_i[46]=4'd1; lut_idx_j[46]=4'd6; lut_idx_k[46]=4'd7;
        lut_mi[47]=7'd63; lut_mj[47]=7'd19; lut_mk[47]=7'd11;
        lut_inv_ij[47]=7'd16; lut_inv_ijk[47]=7'd5;
        lut_idx_i[47]=4'd1; lut_idx_j[47]=4'd6; lut_idx_k[47]=4'd8;
        lut_mi[48]=7'd63; lut_mj[48]=7'd17; lut_mk[48]=7'd11;
        lut_inv_ij[48]=7'd10; lut_inv_ijk[48]=7'd3;
        lut_idx_i[48]=4'd1; lut_idx_j[48]=4'd7; lut_idx_k[48]=4'd8;
        lut_mi[49]=7'd65; lut_mj[49]=7'd31; lut_mk[49]=7'd29;
        lut_inv_ij[49]=7'd21; lut_inv_ijk[49]=7'd27;
        lut_idx_i[49]=4'd2; lut_idx_j[49]=4'd3; lut_idx_k[49]=4'd4;
        lut_mi[50]=7'd65; lut_mj[50]=7'd31; lut_mk[50]=7'd23;
        lut_inv_ij[50]=7'd21; lut_inv_ijk[50]=7'd5;
        lut_idx_i[50]=4'd2; lut_idx_j[50]=4'd3; lut_idx_k[50]=4'd5;
        lut_mi[51]=7'd65; lut_mj[51]=7'd31; lut_mk[51]=7'd19;
        lut_inv_ij[51]=7'd21; lut_inv_ijk[51]=7'd1;
        lut_idx_i[51]=4'd2; lut_idx_j[51]=4'd3; lut_idx_k[51]=4'd6;
        lut_mi[52]=7'd65; lut_mj[52]=7'd31; lut_mk[52]=7'd17;
        lut_inv_ij[52]=7'd21; lut_inv_ijk[52]=7'd2;
        lut_idx_i[52]=4'd2; lut_idx_j[52]=4'd3; lut_idx_k[52]=4'd7;
        lut_mi[53]=7'd65; lut_mj[53]=7'd31; lut_mk[53]=7'd11;
        lut_inv_ij[53]=7'd21; lut_inv_ijk[53]=7'd6;
        lut_idx_i[53]=4'd2; lut_idx_j[53]=4'd3; lut_idx_k[53]=4'd8;
        lut_mi[54]=7'd65; lut_mj[54]=7'd29; lut_mk[54]=7'd23;
        lut_inv_ij[54]=7'd25; lut_inv_ijk[54]=7'd22;
        lut_idx_i[54]=4'd2; lut_idx_j[54]=4'd4; lut_idx_k[54]=4'd5;
        lut_mi[55]=7'd65; lut_mj[55]=7'd29; lut_mk[55]=7'd19;
        lut_inv_ij[55]=7'd25; lut_inv_ijk[55]=7'd5;
        lut_idx_i[55]=4'd2; lut_idx_j[55]=4'd4; lut_idx_k[55]=4'd6;
        lut_mi[56]=7'd65; lut_mj[56]=7'd29; lut_mk[56]=7'd17;
        lut_inv_ij[56]=7'd25; lut_inv_ijk[56]=7'd8;
        lut_idx_i[56]=4'd2; lut_idx_j[56]=4'd4; lut_idx_k[56]=4'd7;
        lut_mi[57]=7'd65; lut_mj[57]=7'd29; lut_mk[57]=7'd11;
        lut_inv_ij[57]=7'd25; lut_inv_ijk[57]=7'd3;
        lut_idx_i[57]=4'd2; lut_idx_j[57]=4'd4; lut_idx_k[57]=4'd8;
        lut_mi[58]=7'd65; lut_mj[58]=7'd23; lut_mk[58]=7'd19;
        lut_inv_ij[58]=7'd17; lut_inv_ijk[58]=7'd3;
        lut_idx_i[58]=4'd2; lut_idx_j[58]=4'd5; lut_idx_k[58]=4'd6;
        lut_mi[59]=7'd65; lut_mj[59]=7'd23; lut_mk[59]=7'd17;
        lut_inv_ij[59]=7'd17; lut_inv_ijk[59]=7'd16;
        lut_idx_i[59]=4'd2; lut_idx_j[59]=4'd5; lut_idx_k[59]=4'd7;
        lut_mi[60]=7'd65; lut_mj[60]=7'd23; lut_mk[60]=7'd11;
        lut_inv_ij[60]=7'd17; lut_inv_ijk[60]=7'd10;
        lut_idx_i[60]=4'd2; lut_idx_j[60]=4'd5; lut_idx_k[60]=4'd8;
        lut_mi[61]=7'd65; lut_mj[61]=7'd19; lut_mk[61]=7'd17;
        lut_inv_ij[61]=7'd12; lut_inv_ijk[61]=7'd14;
        lut_idx_i[61]=4'd2; lut_idx_j[61]=4'd6; lut_idx_k[61]=4'd7;
        lut_mi[62]=7'd65; lut_mj[62]=7'd19; lut_mk[62]=7'd11;
        lut_inv_ij[62]=7'd12; lut_inv_ijk[62]=7'd4;
        lut_idx_i[62]=4'd2; lut_idx_j[62]=4'd6; lut_idx_k[62]=4'd8;
        lut_mi[63]=7'd65; lut_mj[63]=7'd17; lut_mk[63]=7'd11;
        lut_inv_ij[63]=7'd11; lut_inv_ijk[63]=7'd9;
        lut_idx_i[63]=4'd2; lut_idx_j[63]=4'd7; lut_idx_k[63]=4'd8;
        lut_mi[64]=7'd31; lut_mj[64]=7'd29; lut_mk[64]=7'd23;
        lut_inv_ij[64]=7'd15; lut_inv_ijk[64]=7'd12;
        lut_idx_i[64]=4'd3; lut_idx_j[64]=4'd4; lut_idx_k[64]=4'd5;
        lut_mi[65]=7'd31; lut_mj[65]=7'd29; lut_mk[65]=7'd19;
        lut_inv_ij[65]=7'd15; lut_inv_ijk[65]=7'd16;
        lut_idx_i[65]=4'd3; lut_idx_j[65]=4'd4; lut_idx_k[65]=4'd6;
        lut_mi[66]=7'd31; lut_mj[66]=7'd29; lut_mk[66]=7'd17;
        lut_inv_ij[66]=7'd15; lut_inv_ijk[66]=7'd8;
        lut_idx_i[66]=4'd3; lut_idx_j[66]=4'd4; lut_idx_k[66]=4'd7;
        lut_mi[67]=7'd31; lut_mj[67]=7'd29; lut_mk[67]=7'd11;
        lut_inv_ij[67]=7'd15; lut_inv_ijk[67]=7'd7;
        lut_idx_i[67]=4'd3; lut_idx_j[67]=4'd4; lut_idx_k[67]=4'd8;
        lut_mi[68]=7'd31; lut_mj[68]=7'd23; lut_mk[68]=7'd19;
        lut_inv_ij[68]=7'd3; lut_inv_ijk[68]=7'd2;
        lut_idx_i[68]=4'd3; lut_idx_j[68]=4'd5; lut_idx_k[68]=4'd6;
        lut_mi[69]=7'd31; lut_mj[69]=7'd23; lut_mk[69]=7'd17;
        lut_inv_ij[69]=7'd3; lut_inv_ijk[69]=7'd16;
        lut_idx_i[69]=4'd3; lut_idx_j[69]=4'd5; lut_idx_k[69]=4'd7;
        lut_mi[70]=7'd31; lut_mj[70]=7'd23; lut_mk[70]=7'd11;
        lut_inv_ij[70]=7'd3; lut_inv_ijk[70]=7'd5;
        lut_idx_i[70]=4'd3; lut_idx_j[70]=4'd5; lut_idx_k[70]=4'd8;
        lut_mi[71]=7'd31; lut_mj[71]=7'd19; lut_mk[71]=7'd17;
        lut_inv_ij[71]=7'd8; lut_inv_ijk[71]=7'd14;
        lut_idx_i[71]=4'd3; lut_idx_j[71]=4'd6; lut_idx_k[71]=4'd7;
        lut_mi[72]=7'd31; lut_mj[72]=7'd19; lut_mk[72]=7'd11;
        lut_inv_ij[72]=7'd8; lut_inv_ijk[72]=7'd2;
        lut_idx_i[72]=4'd3; lut_idx_j[72]=4'd6; lut_idx_k[72]=4'd8;
        lut_mi[73]=7'd31; lut_mj[73]=7'd17; lut_mk[73]=7'd11;
        lut_inv_ij[73]=7'd11; lut_inv_ijk[73]=7'd10;
        lut_idx_i[73]=4'd3; lut_idx_j[73]=4'd7; lut_idx_k[73]=4'd8;
        lut_mi[74]=7'd29; lut_mj[74]=7'd23; lut_mk[74]=7'd19;
        lut_inv_ij[74]=7'd4; lut_inv_ijk[74]=7'd10;
        lut_idx_i[74]=4'd4; lut_idx_j[74]=4'd5; lut_idx_k[74]=4'd6;
        lut_mi[75]=7'd29; lut_mj[75]=7'd23; lut_mk[75]=7'd17;
        lut_inv_ij[75]=7'd4; lut_inv_ijk[75]=7'd13;
        lut_idx_i[75]=4'd4; lut_idx_j[75]=4'd5; lut_idx_k[75]=4'd7;
        lut_mi[76]=7'd29; lut_mj[76]=7'd23; lut_mk[76]=7'd11;
        lut_inv_ij[76]=7'd4; lut_inv_ijk[76]=7'd8;
        lut_idx_i[76]=4'd4; lut_idx_j[76]=4'd5; lut_idx_k[76]=4'd8;
        lut_mi[77]=7'd29; lut_mj[77]=7'd19; lut_mk[77]=7'd17;
        lut_inv_ij[77]=7'd2; lut_inv_ijk[77]=7'd5;
        lut_idx_i[77]=4'd4; lut_idx_j[77]=4'd6; lut_idx_k[77]=4'd7;
        lut_mi[78]=7'd29; lut_mj[78]=7'd19; lut_mk[78]=7'd11;
        lut_inv_ij[78]=7'd2; lut_inv_ijk[78]=7'd1;
        lut_idx_i[78]=4'd4; lut_idx_j[78]=4'd6; lut_idx_k[78]=4'd8;
        lut_mi[79]=7'd29; lut_mj[79]=7'd17; lut_mk[79]=7'd11;
        lut_inv_ij[79]=7'd10; lut_inv_ijk[79]=7'd5;
        lut_idx_i[79]=4'd4; lut_idx_j[79]=4'd7; lut_idx_k[79]=4'd8;
        lut_mi[80]=7'd23; lut_mj[80]=7'd19; lut_mk[80]=7'd17;
        lut_inv_ij[80]=7'd5; lut_inv_ijk[80]=7'd10;
        lut_idx_i[80]=4'd5; lut_idx_j[80]=4'd6; lut_idx_k[80]=4'd7;
        lut_mi[81]=7'd23; lut_mj[81]=7'd19; lut_mk[81]=7'd11;
        lut_inv_ij[81]=7'd5; lut_inv_ijk[81]=7'd7;
        lut_idx_i[81]=4'd5; lut_idx_j[81]=4'd6; lut_idx_k[81]=4'd8;
        lut_mi[82]=7'd23; lut_mj[82]=7'd17; lut_mk[82]=7'd11;
        lut_inv_ij[82]=7'd3; lut_inv_ijk[82]=7'd2;
        lut_idx_i[82]=4'd5; lut_idx_j[82]=4'd7; lut_idx_k[82]=4'd8;
        lut_mi[83]=7'd19; lut_mj[83]=7'd17; lut_mk[83]=7'd11;
        lut_inv_ij[83]=7'd9; lut_inv_ijk[83]=7'd3;
        lut_idx_i[83]=4'd6; lut_idx_j[83]=4'd7; lut_idx_k[83]=4'd8;
    end

    // =========================================================================
    // 3. Received Residues Register Bank
    // =========================================================================
    reg [6:0] recv_r [0:8];

    // =========================================================================
    // 4. MRC Computation Registers
    // =========================================================================
    reg [6:0] mrc_ri, mrc_rj, mrc_rk;
    reg [6:0] mrc_mi, mrc_mj, mrc_mk;
    reg [6:0] mrc_inv_ij, mrc_inv_ijk;
    reg [3:0] mrc_idx_j, mrc_idx_k;  // v3.0: save modulus indices for case-based modulo
    reg [6:0] mrc_a1;
    reg [7:0] mrc_diff2;
    reg [7:0] mrc_diff3;
    reg [6:0] mrc_a2;
    reg [7:0] mrc_a3raw;
    reg [6:0] mrc_a3;
    reg [17:0] mrc_x;

    // =========================================================================
    // 5. Distance Computation Registers
    // =========================================================================
    reg [6:0] cand_r [0:8];
    reg [3:0] cur_dist;

    // =========================================================================
    // 6. MLD Accumulator
    // =========================================================================
    reg [3:0]  min_dist;
    reg [15:0] best_x;

    // =========================================================================
    // 7. Case-Based Constant Modulo Functions (v3.0 TIMING FIX)
    // =========================================================================
    // These functions replace dynamic modulo (prod % mrc_mj) with case statements
    // where each branch uses a compile-time constant modulus.
    // Vivado optimizes constant modulo to ~5-8 LUT levels (~2-3ns) vs
    // dynamic modulo which requires ~45-51 LUT levels (~18-21ns).
    //
    // mod_by_idx_7bit: compute val % MODS[idx] for 7-bit result (max mod=65)
    // Input: val up to 14-bit (product of two 7-bit values)
    // Output: 7-bit result
    function automatic [6:0] mod_by_idx_7bit(input [13:0] val, input [3:0] idx);
        case (idx)
            4'd0: mod_by_idx_7bit = val % 7'd64;
            4'd1: mod_by_idx_7bit = val % 7'd63;
            4'd2: mod_by_idx_7bit = val % 7'd65;
            4'd3: mod_by_idx_7bit = val % 7'd31;
            4'd4: mod_by_idx_7bit = val % 7'd29;
            4'd5: mod_by_idx_7bit = val % 7'd23;
            4'd6: mod_by_idx_7bit = val % 7'd19;
            4'd7: mod_by_idx_7bit = val % 7'd17;
            4'd8: mod_by_idx_7bit = val % 7'd11;
            default: mod_by_idx_7bit = 7'd0;
        endcase
    endfunction

    // mod_by_idx_16bit: compute val % MODS[idx] for 16-bit input (candidate X)
    // Input: val up to 16-bit (candidate X value)
    // Output: 7-bit result
    function automatic [6:0] mod_by_idx_16bit(input [15:0] val, input [3:0] idx);
        case (idx)
            4'd0: mod_by_idx_16bit = val % 7'd64;
            4'd1: mod_by_idx_16bit = val % 7'd63;
            4'd2: mod_by_idx_16bit = val % 7'd65;
            4'd3: mod_by_idx_16bit = val % 7'd31;
            4'd4: mod_by_idx_16bit = val % 7'd29;
            4'd5: mod_by_idx_16bit = val % 7'd23;
            4'd6: mod_by_idx_16bit = val % 7'd19;
            4'd7: mod_by_idx_16bit = val % 7'd17;
            4'd8: mod_by_idx_16bit = val % 7'd11;
            default: mod_by_idx_16bit = 7'd0;
        endcase
    endfunction

    // =========================================================================
    // 8. Combinational MRC Intermediate Signals (v3.0: case-based modulo)
    // =========================================================================
    // MRC_S2: a2 = (diff2 * inv_ij) % mj
    // v3.0: use mod_by_idx_7bit with mrc_idx_j instead of % mrc_mj
    wire [13:0] s2_prod  = mrc_diff2 * mrc_inv_ij;
    wire [6:0]  s2_a2    = mod_by_idx_7bit(s2_prod, mrc_idx_j);

    // MRC_S3: a3_raw = (diff3 - (a2*mi % mk) + mk) % mk
    // v3.0: use mod_by_idx_7bit with mrc_idx_k instead of % mrc_mk
    wire [13:0] s3_a2mi_prod = mrc_a2 * mrc_mi;
    wire [6:0]  s3_a2mi_mod  = mod_by_idx_7bit(s3_a2mi_prod, mrc_idx_k);
    wire [7:0]  s3_a3raw = (mrc_diff3 >= s3_a2mi_mod) ?
                           (mrc_diff3 - s3_a2mi_mod) :
                           (mrc_diff3 + mrc_mk - s3_a2mi_mod);

    // MRC_S4: a3 = (a3_raw * inv_ijk) % mk
    // v3.0: use mod_by_idx_7bit with mrc_idx_k instead of % mrc_mk
    wire [13:0] s4_prod = mrc_a3raw * mrc_inv_ijk;
    wire [6:0]  s4_a3   = mod_by_idx_7bit(s4_prod, mrc_idx_k);

    // MRC_S5: X = a1 + a2*mi + a3*mi*mj
    wire [17:0] s5_x = {11'b0, mrc_a1} + ({11'b0, mrc_a2} * {11'b0, mrc_mi}) +
                       ({11'b0, mrc_a3} * {11'b0, mrc_mi} * {11'b0, mrc_mj});

    // =========================================================================
    // 9. Combinational Distance Computation (v3.0: case-based modulo)
    // =========================================================================
    // DIST_S1: compute cand_r[0..2] = X % {64, 63, 65}
    wire [6:0] ds1_r0 = mrc_x[15:0] % 7'd64;
    wire [6:0] ds1_r1 = mrc_x[15:0] % 7'd63;
    wire [6:0] ds1_r2 = mrc_x[15:0] % 7'd65;

    // DIST_S2: compute cand_r[3..5] = X % {31, 29, 23}
    wire [6:0] ds2_r3 = mrc_x[15:0] % 7'd31;
    wire [6:0] ds2_r4 = mrc_x[15:0] % 7'd29;
    wire [6:0] ds2_r5 = mrc_x[15:0] % 7'd23;

    // DIST_S3: compute cand_r[6..8] = X % {19, 17, 11}
    wire [6:0] ds3_r6 = mrc_x[15:0] % 7'd19;
    wire [6:0] ds3_r7 = mrc_x[15:0] % 7'd17;
    wire [6:0] ds3_r8 = mrc_x[15:0] % 7'd11;

    // Hamming distance
    wire [3:0] dist_comb =
        ((cand_r[0] != recv_r[0]) ? 4'd1 : 4'd0) +
        ((cand_r[1] != recv_r[1]) ? 4'd1 : 4'd0) +
        ((cand_r[2] != recv_r[2]) ? 4'd1 : 4'd0) +
        ((cand_r[3] != recv_r[3]) ? 4'd1 : 4'd0) +
        ((cand_r[4] != recv_r[4]) ? 4'd1 : 4'd0) +
        ((cand_r[5] != recv_r[5]) ? 4'd1 : 4'd0) +
        ((cand_r[6] != recv_r[6]) ? 4'd1 : 4'd0) +
        ((cand_r[7] != recv_r[7]) ? 4'd1 : 4'd0) +
        ((cand_r[8] != recv_r[8]) ? 4'd1 : 4'd0);

    // =========================================================================
    // 10. FSM
    // =========================================================================
    integer ii;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            trip_idx      <= 7'd0;
            min_dist      <= 4'd9;
            best_x        <= 16'd0;
            cur_dist      <= 4'd9;
            mrc_ri        <= 7'd0;
            mrc_rj        <= 7'd0;
            mrc_rk        <= 7'd0;
            mrc_mi        <= 7'd1;
            mrc_mj        <= 7'd1;
            mrc_mk        <= 7'd1;
            mrc_inv_ij    <= 7'd1;
            mrc_inv_ijk   <= 7'd1;
            mrc_idx_j     <= 4'd0;
            mrc_idx_k     <= 4'd0;
            mrc_a1        <= 7'd0;
            mrc_diff2     <= 8'd0;
            mrc_diff3     <= 8'd0;
            mrc_a2        <= 7'd0;
            mrc_a3raw     <= 8'd0;
            mrc_a3        <= 7'd0;
            mrc_x         <= 18'd0;
            for (ii=0; ii<9; ii=ii+1) begin
                recv_r[ii] <= 7'd0;
                cand_r[ii] <= 7'd0;
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
                    recv_r[0] <= {1'b0, residues_in[47:42]};
                    recv_r[1] <= {1'b0, residues_in[41:36]};
                    recv_r[2] <=        residues_in[35:29];
                    recv_r[3] <= {2'b0, residues_in[28:24]};
                    recv_r[4] <= {2'b0, residues_in[23:19]};
                    recv_r[5] <= {2'b0, residues_in[18:14]};
                    recv_r[6] <= {2'b0, residues_in[13:9]};
                    recv_r[7] <= {2'b0, residues_in[8:4]};
                    recv_r[8] <= {3'b0, residues_in[3:0]};
                    trip_idx  <= 7'd0;
                    min_dist  <= 4'd9;
                    best_x    <= 16'd0;
                    state     <= ST_MRC_S1;
                end

                ST_MRC_S1: begin
                    // Load triplet parameters + save modulus indices for case-based modulo
                    mrc_mi      <= lut_mi[trip_idx];
                    mrc_mj      <= lut_mj[trip_idx];
                    mrc_mk      <= lut_mk[trip_idx];
                    mrc_inv_ij  <= lut_inv_ij[trip_idx];
                    mrc_inv_ijk <= lut_inv_ijk[trip_idx];
                    mrc_idx_j   <= lut_idx_j[trip_idx];  // v3.0: save for case-based modulo
                    mrc_idx_k   <= lut_idx_k[trip_idx];  // v3.0: save for case-based modulo
                    mrc_ri      <= recv_r[lut_idx_i[trip_idx]];
                    mrc_rj      <= recv_r[lut_idx_j[trip_idx]];
                    mrc_rk      <= recv_r[lut_idx_k[trip_idx]];
                    state <= ST_MRC_S2;
                end

                ST_MRC_S2: begin
                    mrc_a1    <= mrc_ri;
                    mrc_diff2 <= (mrc_rj >= mrc_ri) ? (mrc_rj - mrc_ri) :
                                 (mrc_rj + mrc_mj - mrc_ri);
                    mrc_diff3 <= (mrc_rk >= mrc_ri) ? (mrc_rk - mrc_ri) :
                                 (mrc_rk + mrc_mk - mrc_ri);
                    state <= ST_MRC_S3;
                end

                ST_MRC_S3: begin
                    // v3.0: s2_a2 uses mod_by_idx_7bit(s2_prod, mrc_idx_j)
                    // mrc_idx_j is a registered value -> case branch is selected at runtime
                    // but each branch has a CONSTANT modulus -> ~5-8 LUT levels
                    mrc_a2 <= s2_a2;
                    state  <= ST_MRC_S4;
                end

                ST_MRC_S4: begin
                    // v3.0: s3_a3raw uses mod_by_idx_7bit(s3_a2mi_prod, mrc_idx_k)
                    mrc_a3raw <= s3_a3raw;
                    state     <= ST_MRC_S5;
                end

                ST_MRC_S5: begin
                    // v3.0: s4_a3 uses mod_by_idx_7bit(s4_prod, mrc_idx_k)
                    mrc_a3 <= s4_a3;
                    state  <= ST_DIST_S1;
                end

                ST_DIST_S1: begin
                    mrc_x <= s5_x;
                    state <= ST_DIST_S2;
                end

                ST_DIST_S2: begin
                    if (mrc_x <= 18'd65535) begin
                        cand_r[0] <= ds1_r0;
                        cand_r[1] <= ds1_r1;
                        cand_r[2] <= ds1_r2;
                    end else begin
                        cand_r[0] <= 7'd127;
                        cand_r[1] <= 7'd127;
                        cand_r[2] <= 7'd127;
                    end
                    state <= ST_DIST_S3;
                end

                ST_DIST_S3: begin
                    if (mrc_x <= 18'd65535) begin
                        cand_r[3] <= ds2_r3;
                        cand_r[4] <= ds2_r4;
                        cand_r[5] <= ds2_r5;
                        cand_r[6] <= ds3_r6;
                        cand_r[7] <= ds3_r7;
                        cand_r[8] <= ds3_r8;
                    end else begin
                        cand_r[3] <= 7'd127; cand_r[4] <= 7'd127; cand_r[5] <= 7'd127;
                        cand_r[6] <= 7'd127; cand_r[7] <= 7'd127; cand_r[8] <= 7'd127;
                    end
                    state <= ST_UPDATE;
                end

                ST_UPDATE: begin
                    cur_dist <= dist_comb;
                    if (dist_comb < min_dist) begin
                        min_dist <= dist_comb;
                        best_x   <= mrc_x[15:0];
                    end
                    state <= ST_NEXT;
                end

                ST_NEXT: begin
                    if (trip_idx == 7'd83) begin
                        state <= ST_DONE;
                    end else begin
                        trip_idx <= trip_idx + 1'b1;
                        state    <= ST_MRC_S1;
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
