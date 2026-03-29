function codeword = encode_rs(data)
% ENCODE_RS  RS(12,4) encoder over GF(2^4).
%
%   Encodes a 16-bit data word as 4 symbols × 4 bits = 16 data bits,
%   producing a 48-bit codeword (12 symbols × 4 bits).
%
%   Uses MATLAB Communications Toolbox rsenc() with GF(2^4).
%   n=12, k=4, t=4 symbol errors correctable.
%
%   Codeword packing (48 bits, right-aligned in uint64):
%     bits [47:44] = symbol 0  (MSB first)
%     bits [43:40] = symbol 1
%     ...
%     bits [3:0]   = symbol 11

    % Split 16-bit data into 4 × 4-bit symbols (MSB first)
    x = uint32(data);
    d0 = double(bitand(bitshift(x, -12), uint32(15)));  % bits [15:12]
    d1 = double(bitand(bitshift(x,  -8), uint32(15)));  % bits [11:8]
    d2 = double(bitand(bitshift(x,  -4), uint32(15)));  % bits [7:4]
    d3 = double(bitand(x,               uint32(15)));   % bits [3:0]

    % Encode using RS(12,4) over GF(2^4)
    msg     = gf([d0, d1, d2, d3], 4);
    encoded = rsenc(msg, 12, 4);
    syms    = double(encoded.x);  % 12 symbols

    % Pack 12 × 4-bit symbols into uint64 (right-aligned, 48 bits total)
    codeword = uint64(0);
    for i = 1:12
        shift    = (12 - i) * 4;
        codeword = bitor(codeword, bitshift(uint64(syms(i)), shift));
    end
end
