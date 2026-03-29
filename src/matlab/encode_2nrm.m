function codeword = encode_2nrm(data)
% ENCODE_2NRM  2NRM-RRNS encoder.
%
%   Moduli: m = {257, 256, 61, 59, 55, 53}
%   Non-redundant: {257, 256}  → M_a = 65792 > 65535
%   Redundant:     {61, 59, 55, 53}
%   Codeword: 41 bits, packed as:
%     bits [40:32] = r0 (mod 257, 9 bits)
%     bits [31:24] = r1 (mod 256, 8 bits)
%     bits [23:18] = r2 (mod 61,  6 bits)
%     bits [17:12] = r3 (mod 59,  6 bits)
%     bits [11:6]  = r4 (mod 55,  6 bits)
%     bits [5:0]   = r5 (mod 53,  6 bits)

    x = uint64(data);
    r0 = mod(x, 257);
    r1 = mod(x, 256);
    r2 = mod(x, 61);
    r3 = mod(x, 59);
    r4 = mod(x, 55);
    r5 = mod(x, 53);

    codeword = bitor(bitor(bitor(bitor(bitor( ...
        bitshift(r0, 32), ...
        bitshift(r1, 24)), ...
        bitshift(r2, 18)), ...
        bitshift(r3, 12)), ...
        bitshift(r4,  6)), ...
        r5);
end
