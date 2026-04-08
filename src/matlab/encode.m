function codeword = encode(data, algo_id)
% ENCODE  Route encoding to the appropriate algorithm.
%
%   codeword = encode(data, algo_id)
%
%   Inputs:
%     data     - uint32 scalar, 16-bit data value [0, 65535]
%     algo_id  - Algorithm ID:
%                  6 = 2NRM-RRNS-Serial  (41-bit codeword)
%                  1 = 3NRM-RRNS  (48-bit codeword)
%                  2 = C-RRNS-MLD (61-bit codeword)
%                  3 = C-RRNS-MRC (61-bit codeword, same encoder as MLD)
%                  5 = RS(12,4)   (48-bit codeword)
%
%   Output:
%     codeword - uint64 packed codeword (right-aligned)

    switch algo_id
        case 6
            codeword = encode_2nrm(data);
        case 1
            codeword = encode_3nrm(data);
        case {2, 3, 4}
            codeword = encode_crrns(data);
        case 5
            codeword = encode_rs(data);
        otherwise
            error('encode: unknown algo_id=%d', algo_id);
    end
end
