function codeword = encode_3nrm(data)
% ENCODE_3NRM  3NRM-RRNS encoder.
%
%   Moduli: m = {64, 63, 65, 31, 29, 23, 19, 17, 11}
%   Non-redundant: {64, 63, 65}  → M_a = 261120 > 65535
%   Redundant:     {31, 29, 23, 19, 17, 11}
%   Codeword: 48 bits, packed as:
%     bits [47:42] = r0 (mod 64,  6 bits)
%     bits [41:36] = r1 (mod 63,  6 bits)
%     bits [35:29] = r2 (mod 65,  7 bits)
%     bits [28:24] = r3 (mod 31,  5 bits)
%     bits [23:19] = r4 (mod 29,  5 bits)
%     bits [18:14] = r5 (mod 23,  5 bits)
%     bits [13:9]  = r6 (mod 19,  5 bits)
%     bits [8:4]   = r7 (mod 17,  5 bits)
%     bits [3:0]   = r8 (mod 11,  4 bits)

    x = uint64(data);
    r0 = mod(x, 64);
    r1 = mod(x, 63);
    r2 = mod(x, 65);
    r3 = mod(x, 31);
    r4 = mod(x, 29);
    r5 = mod(x, 23);
    r6 = mod(x, 19);
    r7 = mod(x, 17);
    r8 = mod(x, 11);

    codeword = bitor(bitor(bitor(bitor(bitor(bitor(bitor(bitor( ...
        bitshift(r0, 42), ...
        bitshift(r1, 36)), ...
        bitshift(r2, 29)), ...
        bitshift(r3, 24)), ...
        bitshift(r4, 19)), ...
        bitshift(r5, 14)), ...
        bitshift(r6,  9)), ...
        bitshift(r7,  4)), ...
        r8);
end
