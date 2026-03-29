function [data_out, uncorrectable] = decode_3nrm_mld(codeword)
% DECODE_3NRM_MLD  3NRM-RRNS Maximum Likelihood Decoder.
%
%   Moduli: m = {64, 63, 65, 31, 29, 23, 19, 17, 11}
%   M_a = 64 × 63 × 65 = 261120  (non-redundant product)
%   t = 3 (corrects up to 3 erroneous residues)
%
%   For each C(9,3)=84 triplet (i,j,k):
%     MRC reconstruction:
%       a1 = r(i)
%       a2 = (r(j) - a1) * inv(mi, mj) mod mj
%       a3 = (r(k) - a1 - a2*mi) * inv(mi*mj, mk) mod mk
%       X  = a1 + a2*mi + a3*mi*mj
%     Compute Hamming distance to all 9 received residues.
%   Select candidate with minimum distance. If <= 3: correctable.

    MODULI = [64, 63, 65, 31, 29, 23, 19, 17, 11];
    N      = 9;
    T      = 3;

    % Unpack received residues from codeword
    r_d = zeros(1, N);
    r_d(1) = double(bitand(bitshift(codeword, -42), uint64(63)));   % 6 bits, mod 64
    r_d(2) = double(bitand(bitshift(codeword, -36), uint64(63)));   % 6 bits, mod 63
    r_d(3) = double(bitand(bitshift(codeword, -29), uint64(127)));  % 7 bits, mod 65
    r_d(4) = double(bitand(bitshift(codeword, -24), uint64(31)));   % 5 bits, mod 31
    r_d(5) = double(bitand(bitshift(codeword, -19), uint64(31)));   % 5 bits, mod 29
    r_d(6) = double(bitand(bitshift(codeword, -14), uint64(31)));   % 5 bits, mod 23
    r_d(7) = double(bitand(bitshift(codeword,  -9), uint64(31)));   % 5 bits, mod 19
    r_d(8) = double(bitand(bitshift(codeword,  -4), uint64(31)));   % 5 bits, mod 17
    r_d(9) = double(bitand(codeword,              uint64(15)));     % 4 bits, mod 11

    best_X   = 0;
    min_dist = N + 1;

    % Enumerate all C(9,3)=84 triplets
    for i = 1:(N-2)
        for j = (i+1):(N-1)
            for k = (j+1):N
                mi = MODULI(i);
                mj = MODULI(j);
                mk = MODULI(k);

                % MRC reconstruction using 3 moduli (i, j, k)
                a1 = r_d(i);

                % a2 = (r(j) - a1) * inv(mi, mj) mod mj
                inv_mi_mj = mod_inv_local(mi, mj);
                diff2 = mod(r_d(j) - a1 + mj*100, mj);
                a2 = mod(diff2 * inv_mi_mj, mj);

                % a3 = (r(k) - a1 - a2*mi) * inv(mi*mj, mk) mod mk
                inv_mimj_mk = mod_inv_local(mod(mi * mj, mk), mk);
                diff3 = mod(r_d(k) - a1 - a2 * mi + mk*10000, mk);
                a3 = mod(diff3 * inv_mimj_mk, mk);

                X_base = a1 + a2 * mi + a3 * mi * mj;

                % Bug #104 fix: enumerate k>0 candidates X_k = X_base + k*PERIOD
                % PERIOD = mi * mj * mk. Same fix as 2NRM Bug #102.
                PERIOD = mi * mj * mk;
                X_k = X_base;
                while X_k <= 65535
                    % Compute Hamming distance against all 9 residues
                    dist = 0;
                    for s = 1:N
                        if mod(X_k, MODULI(s)) ~= r_d(s)
                            dist = dist + 1;
                        end
                    end

                    if dist < min_dist
                        min_dist = dist;
                        best_X   = X_k;
                    end

                    X_k = X_k + PERIOD;
                end
            end
        end
    end

    if min_dist <= T
        data_out      = uint32(best_X);
        uncorrectable = false;
    else
        data_out      = uint32(0);
        uncorrectable = true;
    end
end

function inv = mod_inv_local(a, m)
    a = mod(a, m);
    if a == 0
        inv = 0;
        return;
    end
    [~, x, ~] = extended_gcd_local(a, m);
    inv = mod(x, m);
end

function [g, x, y] = extended_gcd_local(a, b)
    if a == 0
        g = b; x = 0; y = 1;
    else
        [g, x1, y1] = extended_gcd_local(mod(b, a), a);
        x = y1 - floor(b/a) * x1;
        y = x1;
    end
end
