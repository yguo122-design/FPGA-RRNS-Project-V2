function [data_out, uncorrectable] = decode(codeword, algo_id)
% DECODE  Route decoding to the appropriate algorithm.
%
%   [data_out, uncorrectable] = decode(codeword, algo_id)
%
%   Inputs:
%     codeword      - uint64 packed (possibly corrupted) codeword
%     algo_id       - Algorithm ID:
%                       6 = 2NRM-RRNS-Serial (MLD, t=2)
%                       1 = 3NRM-RRNS (MLD, t=3)
%                       2 = C-RRNS-MLD (MLD, t=3)
%                       3 = C-RRNS-MRC (no correction)
%                       4 = C-RRNS-CRT (DISABLED — see note below)
%                       5 = RS(12,4) (t=4)
%
%   NOTE on algo_id=4 (C-RRNS-CRT):
%     Standard CRT cannot be applied to the non-redundant moduli set
%     {64, 63, 65} because gcd(M_a/64, 64) = gcd(4080, 64) = 16 ≠ 1,
%     making the CRT coefficient for m0=64 non-invertible. The FPGA
%     implementation falls back to MRC, which is identical to C-RRNS-MRC
%     (algo_id=3). Therefore algo_id=4 is disabled to avoid redundant testing.
%
%   Outputs:
%     data_out      - uint32 decoded 16-bit data
%     uncorrectable - logical, true if decoder cannot correct errors

    switch algo_id
        case 6
            [data_out, uncorrectable] = decode_2nrm_mld(codeword);
        case 1
            [data_out, uncorrectable] = decode_3nrm_mld(codeword);
        case 2
            [data_out, uncorrectable] = decode_crrns_mld(codeword);
        case 3
            [data_out, uncorrectable] = decode_crrns_mrc(codeword);
        % case 4  % C-RRNS-CRT: DISABLED
        %   CRT is not applicable to {64,63,65} moduli set (gcd(M_a/64,64)=16≠1).
        %   FPGA implementation uses MRC fallback (identical to algo_id=3).
        %   [data_out, uncorrectable] = decode_crrns_crt(codeword);
        case 5
            [data_out, uncorrectable] = decode_rs(codeword);
        otherwise
            error('decode: unknown or disabled algo_id=%d', algo_id);
    end
end
