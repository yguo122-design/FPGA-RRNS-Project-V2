function [data_out, uncorrectable] = decode_2nrm_mld(codeword)
% DECODE_2NRM_MLD  2NRM-RRNS Maximum Likelihood Decoder.
%
%   Moduli: m = {257, 256, 61, 59, 55, 53}
%   M_a = 257 × 256 = 65792  (non-redundant product)
%   t = 2 (corrects up to 2 erroneous residues)
%
%   Algorithm:
%     For each of C(6,2)=15 pairs of moduli:
%       1. CRT reconstruction using the pair → X_base
%       2. Enumerate up to 5 candidates: X_base + k*PERIOD, k=0..4
%       3. Compute Hamming distance to received residue vector
%     Select candidate with minimum Hamming distance.
%     If min_dist <= 2: correctable; else: uncorrectable.

    MODULI = [257, 256, 61, 59, 55, 53];
    M_A    = 65792;   % 257 × 256
    N      = 6;
    T      = 2;       % Correction capability

    % Unpack received residues from codeword
    r = zeros(1, N, 'uint64');
    r(1) = bitand(bitshift(codeword, -32), uint64(511));  % 9 bits, mod 257
    r(2) = bitand(bitshift(codeword, -24), uint64(255));  % 8 bits, mod 256
    r(3) = bitand(bitshift(codeword, -18), uint64(63));   % 6 bits, mod 61
    r(4) = bitand(bitshift(codeword, -12), uint64(63));   % 6 bits, mod 59
    r(5) = bitand(bitshift(codeword,  -6), uint64(63));   % 6 bits, mod 55
    r(6) = bitand(codeword,               uint64(63));    % 6 bits, mod 53

    r_d = double(r);  % Convert to double for arithmetic

    best_X    = 0;
    min_dist  = N + 1;  % Worse than any possible distance

    % Enumerate all C(6,2)=15 pairs
    for i = 1:(N-1)
        for j = (i+1):N
            mi = MODULI(i);
            mj = MODULI(j);
            PERIOD = mi * mj;

            % CRT reconstruction for pair (i,j):
            % Find X such that X ≡ r(i) (mod mi) and X ≡ r(j) (mod mj)
            % X = r(i) + mi * ((r(j) - r(i)) * inv(mi, mj) mod mj)
            inv_mi_mj = mod_inv(mi, mj);
            diff = mod(r_d(j) - r_d(i) + mj, mj);
            coeff = mod(diff * inv_mi_mj, mj);
            X_base = r_d(i) + mi * coeff;

            % Enumerate candidates: X_base + k*PERIOD, k=0,1,...
            % Bug #102 fix: remove fixed k=4 limit; iterate until X_cand > 65535.
            % The old limit (k=0..4) was insufficient for small-modulus pairs
            % (e.g., (55,53) with PERIOD=2915 needs k up to 22 to cover all 16-bit X).
            % FPGA fix confirmed: Cluster L=5 and L=8 now reach 100% SR.
            for k = 0:22
                X_cand = X_base + k * PERIOD;
                if X_cand > 65535
                    break;
                end

                % Compute Hamming distance (number of mismatching residues)
                dist = 0;
                for s = 1:N
                    if mod(X_cand, MODULI(s)) ~= r_d(s)
                        dist = dist + 1;
                    end
                end

                % Update best candidate
                if dist < min_dist
                    min_dist = dist;
                    best_X   = X_cand;
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

function inv = mod_inv(a, m)
% MOD_INV  Compute modular inverse of a modulo m using extended Euclidean.
    [~, x, ~] = extended_gcd(mod(a, m), m);
    inv = mod(x, m);
end

function [g, x, y] = extended_gcd(a, b)
% EXTENDED_GCD  Extended Euclidean algorithm.
    if a == 0
        g = b; x = 0; y = 1;
    else
        [g, x1, y1] = extended_gcd(mod(b, a), a);
        x = y1 - floor(b/a) * x1;
        y = x1;
    end
end
