function [data_out, uncorrectable] = decode_crrns_mrc(codeword)
% DECODE_CRRNS_MRC  C-RRNS Mixed Radix Conversion decoder (no error correction).
%
%   Reconstructs data directly from the 3 non-redundant residues {r0, r1, r2}
%   using Mixed Radix Conversion. No error correction capability.
%
%   Non-redundant moduli: m0=64, m1=63, m2=65
%   MRC formula:
%     a1 = r0
%     a2 = (r1 - r0) * inv(m0, m1) mod m1
%     a3 = ((r2 - r0) * inv(m0, m2) - a2 * m0 * inv(m0, m2)) * inv(m0*m1, m2) mod m2
%     X  = a1 + a2*m0 + a3*m0*m1

    % Unpack only the 3 non-redundant residues
    r0 = double(bitand(bitshift(codeword, -55), uint64(63)));   % mod 64
    r1 = double(bitand(bitshift(codeword, -49), uint64(63)));   % mod 63
    r2 = double(bitand(bitshift(codeword, -42), uint64(127)));  % mod 65

    m0 = 64; m1 = 63; m2 = 65;

    % Pre-computed modular inverses:
    %   inv(m0, m1) = inv(64, 63) = inv(1, 63) = 1
    %   inv(m0*m1, m2) = inv(64*63, 65) = inv(4032, 65) = inv(33, 65) = 33
    %   (since 64*63 mod 65 = 4032 mod 65 = 4032 - 61*65 = 4032-3965 = 67 mod 65 = 2... 
    %    let's compute properly)
    inv_m0_m1 = mod_inv_local(m0, m1);   % inv(64, 63)
    inv_m0m1_m2 = mod_inv_local(mod(m0*m1, m2), m2);  % inv(64*63 mod 65, 65)

    a1 = r0;
    diff2 = mod(r1 - r0 + m1, m1);
    a2 = mod(diff2 * inv_m0_m1, m1);

    diff3 = mod(r2 - r0 + m2, m2);
    a3_num = mod(diff3 - a2 * mod(m0, m2) + m2*m2, m2);
    a3 = mod(a3_num * inv_m0m1_m2, m2);

    X = a1 + a2 * m0 + a3 * m0 * m1;

    data_out      = uint32(X);
    uncorrectable = false;  % MRC never reports uncorrectable
end

function inv = mod_inv_local(a, m)
    [~, x, ~] = extended_gcd_local(mod(a, m), m);
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
