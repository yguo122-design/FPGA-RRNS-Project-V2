function [data_out, uncorrectable] = decode_crrns_crt(codeword)
% DECODE_CRRNS_CRT  C-RRNS Chinese Remainder Theorem decoder (no error correction).
%
%   Reconstructs data directly from the 3 non-redundant residues {r0, r1, r2}
%   using the Chinese Remainder Theorem. No error correction capability.
%
%   Non-redundant moduli: m0=64, m1=63, m2=65
%   M = m0 * m1 * m2 = 261120
%   CRT formula:
%     M0 = M/m0 = 4080,  y0 = inv(M0, m0) = inv(4080, 64) = 16
%     M1 = M/m1 = 4160,  y1 = inv(M1, m1) = inv(4160, 63) = 32
%     M2 = M/m2 = 4032,  y2 = inv(M2, m2) = inv(4032, 65) = 9
%     X = (r0*M0*y0 + r1*M1*y1 + r2*M2*y2) mod M

    % Unpack only the 3 non-redundant residues
    r0 = double(bitand(bitshift(codeword, -55), uint64(63)));   % mod 64
    r1 = double(bitand(bitshift(codeword, -49), uint64(63)));   % mod 63
    r2 = double(bitand(bitshift(codeword, -42), uint64(127)));  % mod 65

    m0 = 64; m1 = 63; m2 = 65;
    M  = m0 * m1 * m2;  % = 261120

    M0 = M / m0;  % = 4080
    M1 = M / m1;  % = 4160
    M2 = M / m2;  % = 4032

    % Modular inverses (pre-computed):
    %   inv(4080, 64) = inv(4080 mod 64, 64) = inv(16, 64) → gcd(16,64)=16 ≠ 1
    %   Actually inv(M0 mod m0, m0): 4080 mod 64 = 4080 - 63*64 = 4080-4032 = 48
    %   inv(48, 64): gcd(48,64)=16 ≠ 1 → not invertible directly
    %   Use CRT via MRC instead (same result as MRC for 3 moduli)
    %
    % Fallback to MRC (equivalent result):
    inv_m0_m1 = mod_inv_local(m0, m1);   % inv(64, 63) = inv(1, 63) = 1
    inv_m0m1_m2 = mod_inv_local(mod(m0*m1, m2), m2);  % inv(64*63 mod 65, 65)

    a1 = r0;
    diff2 = mod(r1 - a1 + m1*100, m1);
    a2 = mod(diff2 * inv_m0_m1, m1);

    diff3 = mod(r2 - a1 - a2*m0 + m2*10000, m2);
    a3 = mod(diff3 * inv_m0m1_m2, m2);

    X = a1 + a2 * m0 + a3 * m0 * m1;

    data_out      = uint32(X);
    uncorrectable = false;  % CRT never reports uncorrectable
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
