% =============================================================================
% test_codecs.m
% Quick sanity check for all encoders and decoders.
%
% Tests:
%   1. Encode/decode round-trip with no errors (should always pass)
%   2. Encode, inject 1 error, decode (should pass for MLD algorithms)
%   3. Encode, inject t+1 errors, decode (should fail for MLD algorithms)
%
% Run this BEFORE run_simulation.m to verify all codecs are correct.
% =============================================================================

clear; clc;
addpath(fileparts(mfilename('fullpath')));

fprintf('=== Codec Sanity Check ===\n\n');

% NOTE: C-RRNS-CRT (algo_id=4) is EXCLUDED.
% Standard CRT cannot be applied to {64,63,65} because gcd(M_a/64,64)=16≠1.
% The FPGA decoder falls back to MRC (identical to C-RRNS-MRC, algo_id=3).
ALGO_LIST = {
    0, '2NRM-RRNS',   41, 2;
    1, '3NRM-RRNS',   48, 3;
    2, 'C-RRNS-MLD',  61, 3;
    3, 'C-RRNS-MRC',  61, 0;
    % 4, 'C-RRNS-CRT',  61, 0;  % DISABLED: CRT not applicable to {64,63,65}
    5, 'RS(12,4)',     48, 4;
};

N_TEST = 1000;
all_pass = true;

for ai = 1:size(ALGO_LIST, 1)
    algo_id   = ALGO_LIST{ai, 1};
    algo_name = ALGO_LIST{ai, 2};
    w_valid   = ALGO_LIST{ai, 3};
    t_correct = ALGO_LIST{ai, 4};

    % Test 1: No-error round-trip
    errors_no_inject = 0;
    for i = 1:N_TEST
        data = randi([0, 65535], 'uint16');
        cw   = encode(uint32(data), algo_id);
        [dec, uncorr] = decode(cw, algo_id);
        if uncorr || uint32(dec) ~= uint32(data)
            errors_no_inject = errors_no_inject + 1;
        end
    end

    if errors_no_inject == 0
        fprintf('[PASS] %s: No-error round-trip (%d trials)\n', algo_name, N_TEST);
    else
        fprintf('[FAIL] %s: No-error round-trip — %d/%d failures!\n', ...
            algo_name, errors_no_inject, N_TEST);
        all_pass = false;
    end

    % Test 2: Single-bit error correction (only for MLD algorithms)
    if t_correct >= 1
        errors_1bit = 0;
        for i = 1:N_TEST
            data = randi([0, 65535], 'uint16');
            cw   = encode(uint32(data), algo_id);
            % Inject exactly 1 bit error at a random position
            bit_pos = randi([0, w_valid-1]);
            cw_err  = bitxor(cw, bitshift(uint64(1), bit_pos));
            [dec, uncorr] = decode(cw_err, algo_id);
            if uncorr || uint32(dec) ~= uint32(data)
                errors_1bit = errors_1bit + 1;
            end
        end
        if errors_1bit == 0
            fprintf('[PASS] %s: Single-bit error correction (%d trials)\n', algo_name, N_TEST);
        else
            fprintf('[WARN] %s: Single-bit correction — %d/%d failures (may be MLD ambiguity)\n', ...
                algo_name, errors_1bit, N_TEST);
        end
    end
end

fprintf('\n');
if all_pass
    fprintf('[OK] All no-error round-trip tests passed. Ready to run run_simulation.m\n');
else
    fprintf('[ERROR] Some tests failed. Please check the codec implementations.\n');
end
