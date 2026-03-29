function [data_out, uncorrectable] = decode_rs(codeword)
% DECODE_RS  RS(12,4) decoder over GF(2^4).
%
%   Uses MATLAB Communications Toolbox rsdec() with GF(2^4).
%   n=12, k=4, t=4 symbol errors correctable.
%
%   Note: rsdec() returns only the k=4 data symbols (not all 12).
%   The decoded output is a 1×4 GF vector.

    % Unpack 12 × 4-bit symbols from 48-bit codeword (MSB first)
    syms = zeros(1, 12);
    for i = 1:12
        shift   = (12 - i) * 4;
        syms(i) = double(bitand(bitshift(codeword, -shift), uint64(15)));
    end

    received = gf(syms, 4);

    % rsdec returns: decoded (1×k data symbols), cnumerr
    [decoded, cnumerr] = rsdec(received, 12, 4);

    if cnumerr < 0
        % Uncorrectable error
        data_out      = uint32(0);
        uncorrectable = true;
    else
        % decoded is 1×4 GF vector (data symbols only, MSB first)
        % decoded.x gives the underlying integer array
        d = double(decoded.x);
        % d = [d0, d1, d2, d3] where d0 is bits[15:12], d3 is bits[3:0]
        X = d(1)*4096 + d(2)*256 + d(3)*16 + d(4);
        data_out      = uint32(X);
        uncorrectable = false;
    end
end
