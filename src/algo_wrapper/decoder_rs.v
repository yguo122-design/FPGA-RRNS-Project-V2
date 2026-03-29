// =============================================================================
// File: decoder_rs.v
// Description: RS(12,4) Decoder over GF(2^4)
//              Primitive polynomial: x^4 + x + 1 (0x13)
//              Generator polynomial roots: alpha^1 .. alpha^8 (t=4)
//              Corrects up to 4 symbol errors in a 12-symbol codeword
//
// INPUT FORMAT (residues_in[63:0]):
//   [63:48] = 16'b0  (padding, ignored)
//   [47:44] = sym[0]  (MSN of data)
//   [43:40] = sym[1]
//   [39:36] = sym[2]
//   [35:32] = sym[3]  (LSN of data)
//   [31:28] = sym[4]  (parity 0)
//   [27:24] = sym[5]  (parity 1)
//   [23:20] = sym[6]  (parity 2)
//   [19:16] = sym[7]  (parity 3)
//   [15:12] = sym[8]  (parity 4)
//   [11:8]  = sym[9]  (parity 5)
//   [7:4]   = sym[10] (parity 6)
//   [3:0]   = sym[11] (parity 7)
//
// ALGORITHM: BM (Berlekamp-Massey) + Chien Search + Forney
//   Total latency: ~60 clock cycles
//
// INTERFACE: Identical to decoder_crrns_mld.v for drop-in compatibility.
// =============================================================================

`timescale 1ns / 1ps

module decoder_rs (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [63:0] residues_in,
    output reg  [15:0] data_out,
    output reg         valid,
    output reg         uncorrectable
);

    // =========================================================================
    // GF(2^4) Functions (combinational)
    // =========================================================================

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
            4'd15: gf_alog = 4'd1;  // Bug #99 fix: α^15 = α^0 = 1 in GF(2^4)
                                     // Without this, gf_inv(1) = gf_alog(15-0) = gf_alog(15) = 0 (wrong!)
                                     // This caused BM to fail when b_reg=1, and Forney to fail when fn_sv=1
            default: gf_alog = 4'd0;
        endcase
    endfunction

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

    function [3:0] gf_mul;
        input [3:0] a, b;
        reg [4:0] s;
        begin
            if (a == 4'd0 || b == 4'd0)
                gf_mul = 4'd0;
            else begin
                s = {1'b0, gf_log(a)} + {1'b0, gf_log(b)};
                if (s >= 5'd15) s = s - 5'd15;
                gf_mul = gf_alog(s[3:0]);
            end
        end
    endfunction

    function [3:0] gf_inv;
        input [3:0] a;
        reg [4:0] e;
        begin
            if (a == 4'd0) gf_inv = 4'd0;
            else begin
                e = 5'd15 - {1'b0, gf_log(a)};
                gf_inv = gf_alog(e[3:0]);
            end
        end
    endfunction

    function [3:0] gf_div;
        input [3:0] a, b;
        begin
            if (b == 4'd0) gf_div = 4'd0;
            else gf_div = gf_mul(a, gf_inv(b));
        end
    endfunction

    // =========================================================================
    // FSM States
    // =========================================================================
    localparam [4:0]
        ST_IDLE       = 5'd0,
        ST_LOAD       = 5'd1,
        ST_SYN_CALC   = 5'd2,   // Syndrome: Horner step
        ST_SYN_STORE  = 5'd3,   // Store syndrome, advance to next
        ST_SYN_DONE   = 5'd4,
        ST_BM_INIT    = 5'd5,
        ST_BM_DISC    = 5'd6,   // Compute discrepancy
        ST_BM_UPD     = 5'd7,   // Update sigma/B
        ST_CHIEN_INIT = 5'd8,
        ST_CHIEN      = 5'd9,
        ST_OMEGA_INIT = 5'd10,
        ST_OMEGA      = 5'd11,
        ST_FORNEY     = 5'd12,
        ST_OUTPUT     = 5'd13,
        ST_UNCORR     = 5'd14;

    reg [4:0] state;

    // =========================================================================
    // Storage
    // =========================================================================
    reg [3:0] cw [0:11];
    reg [3:0] S  [1:8];
    reg [3:0] sigma [0:8];
    reg [3:0] B_reg [0:8];
    reg [3:0] sigma_save [0:8];  // Save sigma before BM update
    reg [3:0] omega [0:7];
    reg [3:0] err_pos [0:3];

    // =========================================================================
    // Control registers
    // =========================================================================
    reg [3:0] syn_j;        // Syndrome index 1..8
    reg [3:0] syn_idx;      // Symbol index 0..11
    reg [3:0] syn_acc;      // Horner accumulator
    reg [3:0] L_reg;        // BM: LFSR length
    reg [3:0] m_reg;        // BM: steps since last update
    reg [3:0] b_reg;        // BM: previous discrepancy
    reg [3:0] bm_n;         // BM: iteration 1..8
    reg [3:0] bm_disc;      // BM: computed discrepancy
    reg [3:0] chien_pos;    // Chien: current position 0..11
    reg [2:0] err_cnt;      // Number of errors found
    reg [3:0] omega_i;      // Omega computation index 0..7
    reg [2:0] forney_idx;   // Forney: current error index
    // BM coefficient (module-level to avoid local reg in always block)
    reg [3:0] bm_coef;
    // Chien search: combinational final error count (includes current position)
    wire [2:0] chien_final_cnt = (chien_val == 4'd0 && err_cnt < 3'd4) ? (err_cnt + 3'd1) : err_cnt;

    // =========================================================================
    // Combinational helpers for BM discrepancy
    // =========================================================================
    // Compute delta = S[n] ^ sigma[1]*S[n-1] ^ sigma[2]*S[n-2] ^ ... ^ sigma[L]*S[n-L]
    // We unroll for max L=4
    wire [3:0] bm_s1 = (bm_n >= 4'd2 && L_reg >= 4'd1) ? gf_mul(sigma[1], S[bm_n - 4'd1]) : 4'd0;
    wire [3:0] bm_s2 = (bm_n >= 4'd3 && L_reg >= 4'd2) ? gf_mul(sigma[2], S[bm_n - 4'd2]) : 4'd0;
    wire [3:0] bm_s3 = (bm_n >= 4'd4 && L_reg >= 4'd3) ? gf_mul(sigma[3], S[bm_n - 4'd3]) : 4'd0;
    wire [3:0] bm_s4 = (bm_n >= 4'd5 && L_reg >= 4'd4) ? gf_mul(sigma[4], S[bm_n - 4'd4]) : 4'd0;
    wire [3:0] bm_delta_comb = S[bm_n] ^ bm_s1 ^ bm_s2 ^ bm_s3 ^ bm_s4;

    // =========================================================================
    // Combinational helpers for Chien search
    // Evaluate sigma at alpha^((chien_pos+4)%15)
    // sigma(z) = sigma[0] + sigma[1]*z + sigma[2]*z^2 + sigma[3]*z^3 + sigma[4]*z^4
    // =========================================================================
    wire [3:0] chien_xi_exp = (chien_pos + 4'd4) % 4'd15;
    wire [3:0] chien_xi     = gf_alog(chien_xi_exp);
    wire [3:0] chien_xi2    = gf_mul(chien_xi, chien_xi);
    wire [3:0] chien_xi3    = gf_mul(chien_xi2, chien_xi);
    wire [3:0] chien_xi4    = gf_mul(chien_xi3, chien_xi);
    wire [3:0] chien_val    = sigma[0]
                            ^ gf_mul(sigma[1], chien_xi)
                            ^ gf_mul(sigma[2], chien_xi2)
                            ^ gf_mul(sigma[3], chien_xi3)
                            ^ gf_mul(sigma[4], chien_xi4);

    // =========================================================================
    // Combinational helpers for Omega computation
    // omega[i] = sum_{j=0}^{4} sigma[j] * S[i-j+1]  (where 1 <= i-j+1 <= 8)
    // =========================================================================
    wire [3:0] om_k0 = (omega_i >= 4'd0 && omega_i <= 4'd7) ? S[omega_i + 4'd1] : 4'd0;
    wire [3:0] om_k1 = (omega_i >= 4'd1) ? S[omega_i] : 4'd0;
    wire [3:0] om_k2 = (omega_i >= 4'd2) ? S[omega_i - 4'd1] : 4'd0;
    wire [3:0] om_k3 = (omega_i >= 4'd3) ? S[omega_i - 4'd2] : 4'd0;
    wire [3:0] om_k4 = (omega_i >= 4'd4) ? S[omega_i - 4'd3] : 4'd0;
    // Clamp to valid range [1..8]
    wire [3:0] om_s0 = (omega_i + 4'd1 >= 4'd1 && omega_i + 4'd1 <= 4'd8) ? gf_mul(sigma[0], S[omega_i + 4'd1]) : 4'd0;
    wire [3:0] om_s1 = (omega_i >= 4'd1 && omega_i <= 4'd8) ? gf_mul(sigma[1], S[omega_i]) : 4'd0;
    wire [3:0] om_s2 = (omega_i >= 4'd2 && omega_i - 4'd1 <= 4'd7) ? gf_mul(sigma[2], S[omega_i - 4'd1]) : 4'd0;
    wire [3:0] om_s3 = (omega_i >= 4'd3 && omega_i - 4'd2 <= 4'd6) ? gf_mul(sigma[3], S[omega_i - 4'd2]) : 4'd0;
    wire [3:0] om_s4 = (omega_i >= 4'd4 && omega_i - 4'd3 <= 4'd5) ? gf_mul(sigma[4], S[omega_i - 4'd3]) : 4'd0;
    wire [3:0] omega_comb = om_s0 ^ om_s1 ^ om_s2 ^ om_s3 ^ om_s4;

    // =========================================================================
    // Combinational helpers for Forney
    // =========================================================================
    wire [3:0] fn_pos      = err_pos[forney_idx];
    wire [3:0] fn_xi_exp   = (fn_pos + 4'd4) % 4'd15;
    wire [3:0] fn_xi       = gf_alog(fn_xi_exp);   // X_inv = alpha^((pos+4)%15)
    wire [3:0] fn_xi2      = gf_mul(fn_xi, fn_xi);
    wire [3:0] fn_xi3      = gf_mul(fn_xi2, fn_xi);
    wire [3:0] fn_xi4      = gf_mul(fn_xi3, fn_xi);
    wire [3:0] fn_xi5      = gf_mul(fn_xi4, fn_xi);
    wire [3:0] fn_xi6      = gf_mul(fn_xi5, fn_xi);
    wire [3:0] fn_xi7      = gf_mul(fn_xi6, fn_xi);
    // omega(xi): omega[0] + omega[1]*xi + ... + omega[7]*xi^7
    wire [3:0] fn_ov = omega[0]
                     ^ gf_mul(omega[1], fn_xi)
                     ^ gf_mul(omega[2], fn_xi2)
                     ^ gf_mul(omega[3], fn_xi3)
                     ^ gf_mul(omega[4], fn_xi4)
                     ^ gf_mul(omega[5], fn_xi5)
                     ^ gf_mul(omega[6], fn_xi6)
                     ^ gf_mul(omega[7], fn_xi7);
    // sigma_prime(xi): odd terms only (char 2)
    // sigma_prime = sigma[1]*xi^0 + sigma[3]*xi^2
    wire [3:0] fn_sv = gf_mul(sigma[1], 4'd1)
                     ^ gf_mul(sigma[3], fn_xi2);
    wire [3:0] fn_e  = gf_div(fn_ov, fn_sv);

    // =========================================================================
    // Main FSM
    // =========================================================================
    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            valid         <= 1'b0;
            uncorrectable <= 1'b0;
            data_out      <= 16'd0;
            syn_j         <= 4'd0;
            syn_idx       <= 4'd0;
            syn_acc       <= 4'd0;
            L_reg         <= 4'd0;
            m_reg         <= 4'd1;
            b_reg         <= 4'd1;
            bm_n          <= 4'd1;
            bm_disc       <= 4'd0;
            chien_pos     <= 4'd0;
            err_cnt       <= 3'd0;
            omega_i       <= 4'd0;
            forney_idx    <= 3'd0;
            for (k = 0; k < 12; k = k+1) cw[k] <= 4'd0;
            for (k = 1; k <= 8; k = k+1) S[k] <= 4'd0;
            for (k = 0; k <= 8; k = k+1) begin
                sigma[k]      <= 4'd0;
                B_reg[k]      <= 4'd0;
                sigma_save[k] <= 4'd0;
            end
            for (k = 0; k < 8; k = k+1) omega[k] <= 4'd0;
            for (k = 0; k < 4; k = k+1) err_pos[k] <= 4'd0;
        end else begin
            valid         <= 1'b0;
            uncorrectable <= 1'b0;

            case (state)

                // -------------------------------------------------------
                ST_IDLE: begin
                    if (start) state <= ST_LOAD;
                end

                // -------------------------------------------------------
                // Load codeword symbols from residues_in
                // -------------------------------------------------------
                ST_LOAD: begin
                    cw[0]  <= residues_in[47:44];
                    cw[1]  <= residues_in[43:40];
                    cw[2]  <= residues_in[39:36];
                    cw[3]  <= residues_in[35:32];
                    cw[4]  <= residues_in[31:28];
                    cw[5]  <= residues_in[27:24];
                    cw[6]  <= residues_in[23:20];
                    cw[7]  <= residues_in[19:16];
                    cw[8]  <= residues_in[15:12];
                    cw[9]  <= residues_in[11:8];
                    cw[10] <= residues_in[7:4];
                    cw[11] <= residues_in[3:0];
                    syn_j   <= 4'd1;
                    syn_idx <= 4'd0;
                    syn_acc <= 4'd0;
                    state   <= ST_SYN_CALC;
                end

                // -------------------------------------------------------
                // Syndrome computation: Horner's method
                // S[j] = (...((cw[0]*alpha^j + cw[1])*alpha^j + cw[2])...)*alpha^j + cw[11]
                // Each step: acc = acc * alpha^j ^ cw[syn_idx]
                // After 12 steps (idx 0..11), acc = S[j]
                //
                // NOTE: In Verilog NBA semantics, when syn_idx=11 triggers
                // ST_SYN_STORE, syn_acc already holds the fully updated value
                // (including cw[11]) from the previous clock edge. The original
                // code S[syn_j] <= syn_acc is correct.
                // -------------------------------------------------------
                ST_SYN_CALC: begin
                    // Horner step: acc = acc * alpha^j ^ cw[syn_idx]
                    syn_acc <= gf_mul(syn_acc, gf_alog(syn_j)) ^ cw[syn_idx];
                    if (syn_idx == 4'd11) begin
                        state <= ST_SYN_STORE;
                    end else begin
                        syn_idx <= syn_idx + 4'd1;
                    end
                end

                ST_SYN_STORE: begin
                    // REVERTED: Bug #97 fix was incorrect.
                    // In Verilog NBA semantics, syn_acc in ST_SYN_STORE already holds
                    // the value registered at the end of ST_SYN_CALC (syn_idx=11),
                    // which correctly includes cw[11]. The original code is correct.
                    S[syn_j] <= syn_acc;
                    if (syn_j == 4'd8) begin
                        state <= ST_SYN_DONE;
                    end else begin
                        syn_j   <= syn_j + 4'd1;
                        syn_idx <= 4'd0;
                        syn_acc <= 4'd0;
                        state   <= ST_SYN_CALC;
                    end
                end

                ST_SYN_DONE: begin
                    if (S[1]==4'd0 && S[2]==4'd0 && S[3]==4'd0 && S[4]==4'd0 &&
                        S[5]==4'd0 && S[6]==4'd0 && S[7]==4'd0 && S[8]==4'd0) begin
                        state <= ST_OUTPUT;
                    end else begin
                        state <= ST_BM_INIT;
                    end
                end

                // -------------------------------------------------------
                // Berlekamp-Massey Algorithm (Massey 1969)
                // sigma(x) = error locator polynomial
                // -------------------------------------------------------
                ST_BM_INIT: begin
                    sigma[0] <= 4'd1;
                    sigma[1] <= 4'd0; sigma[2] <= 4'd0; sigma[3] <= 4'd0;
                    sigma[4] <= 4'd0; sigma[5] <= 4'd0; sigma[6] <= 4'd0;
                    sigma[7] <= 4'd0; sigma[8] <= 4'd0;
                    B_reg[0] <= 4'd1;
                    B_reg[1] <= 4'd0; B_reg[2] <= 4'd0; B_reg[3] <= 4'd0;
                    B_reg[4] <= 4'd0; B_reg[5] <= 4'd0; B_reg[6] <= 4'd0;
                    B_reg[7] <= 4'd0; B_reg[8] <= 4'd0;
                    L_reg  <= 4'd0;
                    m_reg  <= 4'd1;
                    b_reg  <= 4'd1;
                    bm_n   <= 4'd1;
                    state  <= ST_BM_DISC;
                end

                ST_BM_DISC: begin
                    // Compute discrepancy using combinational logic
                    bm_disc <= bm_delta_comb;
                    state   <= ST_BM_UPD;
                end

                ST_BM_UPD: begin
                    // bm_coef = gf_div(bm_disc, b_reg) — computed combinationally
                    // Use module-level bm_coef to avoid local reg in always block
                    bm_coef <= gf_div(bm_disc, b_reg);
                    if (bm_disc == 4'd0) begin
                        // delta=0: shift m
                        m_reg <= m_reg + 4'd1;
                    end else if ((L_reg << 1) <= (bm_n - 4'd1)) begin
                        // Update sigma: sigma[i] ^= coef * B[i-m] for i >= m
                        // Save old sigma to B_reg (will be new B after update)
                        // Note: sigma updates use current bm_disc/b_reg directly
                        sigma_save[0] <= sigma[0]; sigma_save[1] <= sigma[1];
                        sigma_save[2] <= sigma[2]; sigma_save[3] <= sigma[3];
                        sigma_save[4] <= sigma[4]; sigma_save[5] <= sigma[5];
                        sigma_save[6] <= sigma[6]; sigma_save[7] <= sigma[7];
                        sigma_save[8] <= sigma[8];
                        // sigma[m+j] ^= coef * B[j] for j=0..4
                        if (m_reg <= 4'd8) sigma[m_reg]         <= sigma[m_reg]         ^ gf_mul(gf_div(bm_disc,b_reg), B_reg[0]);
                        if (m_reg+1 <= 4'd8) sigma[m_reg+4'd1]  <= sigma[m_reg+4'd1]    ^ gf_mul(gf_div(bm_disc,b_reg), B_reg[1]);
                        if (m_reg+2 <= 4'd8) sigma[m_reg+4'd2]  <= sigma[m_reg+4'd2]    ^ gf_mul(gf_div(bm_disc,b_reg), B_reg[2]);
                        if (m_reg+3 <= 4'd8) sigma[m_reg+4'd3]  <= sigma[m_reg+4'd3]    ^ gf_mul(gf_div(bm_disc,b_reg), B_reg[3]);
                        if (m_reg+4 <= 4'd8) sigma[m_reg+4'd4]  <= sigma[m_reg+4'd4]    ^ gf_mul(gf_div(bm_disc,b_reg), B_reg[4]);
                        // B = old sigma, b = delta, L = n-L, m = 1
                        B_reg[0] <= sigma[0]; B_reg[1] <= sigma[1];
                        B_reg[2] <= sigma[2]; B_reg[3] <= sigma[3];
                        B_reg[4] <= sigma[4]; B_reg[5] <= sigma[5];
                        B_reg[6] <= sigma[6]; B_reg[7] <= sigma[7];
                        B_reg[8] <= sigma[8];
                        L_reg <= bm_n - L_reg;
                        b_reg <= bm_disc;
                        m_reg <= 4'd1;
                    end else begin
                        // sigma[i] ^= coef * B[i-m], m++
                        if (m_reg <= 4'd8) sigma[m_reg]         <= sigma[m_reg]         ^ gf_mul(gf_div(bm_disc,b_reg), B_reg[0]);
                        if (m_reg+1 <= 4'd8) sigma[m_reg+4'd1]  <= sigma[m_reg+4'd1]    ^ gf_mul(gf_div(bm_disc,b_reg), B_reg[1]);
                        if (m_reg+2 <= 4'd8) sigma[m_reg+4'd2]  <= sigma[m_reg+4'd2]    ^ gf_mul(gf_div(bm_disc,b_reg), B_reg[2]);
                        if (m_reg+3 <= 4'd8) sigma[m_reg+4'd3]  <= sigma[m_reg+4'd3]    ^ gf_mul(gf_div(bm_disc,b_reg), B_reg[3]);
                        if (m_reg+4 <= 4'd8) sigma[m_reg+4'd4]  <= sigma[m_reg+4'd4]    ^ gf_mul(gf_div(bm_disc,b_reg), B_reg[4]);
                        m_reg <= m_reg + 4'd1;
                    end
                    // Advance BM iteration
                    if (bm_n == 4'd8) begin
                        state <= ST_CHIEN_INIT;
                    end else begin
                        bm_n  <= bm_n + 4'd1;
                        state <= ST_BM_DISC;
                    end
                end

                // -------------------------------------------------------
                // Chien Search
                // For pos=0..11: evaluate sigma at alpha^((pos+4)%15)
                // If result=0, error at position pos
                // -------------------------------------------------------
                ST_CHIEN_INIT: begin
                    chien_pos <= 4'd0;
                    err_cnt   <= 3'd0;
                    state     <= ST_CHIEN;
                end

                ST_CHIEN: begin
                    // chien_final_cnt is a combinational wire that includes current position
                    // Update error list if current position is a root
                    if (chien_val == 4'd0 && err_cnt < 3'd4) begin
                        err_pos[err_cnt] <= chien_pos;
                        err_cnt <= chien_final_cnt;
                    end
                    if (chien_pos == 4'd11) begin
                        // Check final error count == L_reg (use chien_final_cnt for last position)
                        if (chien_final_cnt != L_reg[2:0]) begin
                            state <= ST_UNCORR;
                        end else if (L_reg == 4'd0) begin
                            state <= ST_OUTPUT;
                        end else begin
                            state <= ST_OMEGA_INIT;
                        end
                    end else begin
                        chien_pos <= chien_pos + 4'd1;
                    end
                end

                // -------------------------------------------------------
                // Omega computation: omega[i] = sum sigma[j]*S[i-j+1]
                // -------------------------------------------------------
                ST_OMEGA_INIT: begin
                    omega[0] <= 4'd0; omega[1] <= 4'd0;
                    omega[2] <= 4'd0; omega[3] <= 4'd0;
                    omega[4] <= 4'd0; omega[5] <= 4'd0;
                    omega[6] <= 4'd0; omega[7] <= 4'd0;
                    omega_i  <= 4'd0;
                    state    <= ST_OMEGA;
                end

                ST_OMEGA: begin
                    omega[omega_i] <= omega_comb;
                    if (omega_i == 4'd7) begin
                        forney_idx <= 3'd0;
                        state      <= ST_FORNEY;
                    end else begin
                        omega_i <= omega_i + 4'd1;
                    end
                end

                // -------------------------------------------------------
                // Forney: e = omega(xi_inv) / sigma_prime(xi_inv)
                // Apply correction to codeword
                // -------------------------------------------------------
                ST_FORNEY: begin
                    if (fn_sv == 4'd0) begin
                        state <= ST_UNCORR;
                    end else begin
                        cw[fn_pos] <= cw[fn_pos] ^ fn_e;
                        if (forney_idx == err_cnt - 3'd1) begin
                            state <= ST_OUTPUT;
                        end else begin
                            forney_idx <= forney_idx + 3'd1;
                        end
                    end
                end

                // -------------------------------------------------------
                ST_OUTPUT: begin
                    data_out      <= {cw[0], cw[1], cw[2], cw[3]};
                    valid         <= 1'b1;
                    uncorrectable <= 1'b0;
                    state         <= ST_IDLE;
                end

                ST_UNCORR: begin
                    data_out      <= 16'd0;
                    valid         <= 1'b1;
                    uncorrectable <= 1'b1;
                    state         <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
