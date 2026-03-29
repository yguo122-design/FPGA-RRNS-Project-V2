function codeword = encode_crrns(data)
% ENCODE_CRRNS  C-RRNS encoder (shared by MLD, MRC, CRT variants).
%
%   Moduli: m = {64, 63, 65, 67, 71, 73, 79, 83, 89}
%   Non-redundant: {64, 63, 65}  → M_a = 261120 > 65535
%   Redundant:     {67, 71, 73, 79, 83, 89}
%   Codeword: 61 bits, packed as:
%     bits [60:55] = r0 (mod 64,  6 bits)
%     bits [54:49] = r1 (mod 63,  6 bits)
%     bits [48:42] = r2 (mod 65,  7 bits)
%     bits [41:35] = r3 (mod 67,  7 bits)
%     bits [34:28] = r4 (mod 71,  7 bits)
%     bits [27:21] = r5 (mod 73,  7 bits)
%     bits [20:14] = r6 (mod 79,  7 bits)
%     bits [13:7]  = r7 (mod 83,  7 bits)
%     bits [6:0]   = r8 (mod 89,  7 bits)

    x = uint64(data);
    r0 = mod(x, 64);
    r1 = mod(x, 63);
    r2 = mod(x, 65);
    r3 = mod(x, 67);
    r4 = mod(x, 71);
    r5 = mod(x, 73);
    r6 = mod(x, 79);
    r7 = mod(x, 83);
    r8 = mod(x, 89);

    codeword = bitor(bitor(bitor(bitor(bitor(bitor(bitor(bitor( ...
        bitshift(r0, 55), ...
        bitshift(r1, 49)), ...
        bitshift(r2, 42)), ...
        bitshift(r3, 35)), ...
        bitshift(r4, 28)), ...
        bitshift(r5, 21)), ...
        bitshift(r6, 14)), ...
        bitshift(r7,  7)), ...
        r8);
end
