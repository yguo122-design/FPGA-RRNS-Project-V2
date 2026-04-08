% =============================================================================
% run_simulation.m
% MATLAB BER Simulation — FPGA-Consistent Fault Injection Model
%
% Description:
%   Simulates BER performance of 5 ECC algorithms using the same fault
%   injection model as the FPGA implementation:
%     - Probabilistic injection: P_trigger = BER_target * W_valid / burst_len
%     - Burst injection strictly within valid codeword bits
%     - BER_actual = total_flips / (N_samples * W_valid)
%
%   Output CSV format matches FPGA result CSV, enabling direct comparison
%   using the existing compare_ber_curves.py script.
%
% Algorithms:
%   6: 2NRM-RRNS-Serial  (41 bits, t=2, MLD)
%   1: 3NRM-RRNS  (48 bits, t=3, MLD)
%   2: C-RRNS-MLD (61 bits, t=3, MLD)
%   3: C-RRNS-MRC (61 bits, no correction)
%   5: RS(12,4)   (48 bits, t=4)
%
% Usage:
%   run_simulation   % runs all algorithms, all 3 fault modes
%
% Output:
%   src/matlab/results/test_results_YYYYMMDD_HHMMSS.csv  (one per run)
% =============================================================================

clear; clc;
% All .m files are in the same directory — just add the matlab folder itself
addpath(fileparts(mfilename('fullpath')));

% ─── Start Parallel Pool (once for all runs) ─────────────────────────────────
% Starting the pool takes ~10-20 seconds. By starting it here once, we avoid
% repeated startup overhead inside ber_sweep.m.
% On Intel i7-1360P (12 cores): expect ~8-10x speedup vs serial execution.
if isempty(gcp('nocreate'))
    fprintf('Starting parallel pool...\n');
    parpool('local');  % Uses all available cores automatically
    fprintf('Parallel pool ready.\n\n');
end

%% ─── Configuration ──────────────────────────────────────────────────────────

SAMPLE_COUNT = 100000;   % Quick validation run (change to 100000 for final results)
NUM_BER_POINTS = 101;    % BER 0.0% to 10.0%, step 0.1%

% Algorithms to simulate: [algo_id, name, W_valid]
%
% NOTE: C-RRNS-CRT (algo_id=4) is EXCLUDED from simulation.
% Reason: Standard CRT cannot be applied to the non-redundant moduli set
% {64, 63, 65} because gcd(M_a/64, 64) = gcd(4080, 64) = 16 ≠ 1, making
% the CRT coefficient for m0=64 non-invertible. The FPGA implementation
% falls back to MRC (Mixed Radix Conversion), which is identical to
% C-RRNS-MRC (algo_id=3). Testing C-RRNS-CRT would produce the same BER
% curves as C-RRNS-MRC and add no additional information.
% Bug #104 verification: temporarily run only 3NRM-RRNS Cluster L=5
% to compare with FPGA results. Uncomment other entries to restore full run.
ALGO_LIST = {
    6, '2NRM-RRNS-Serial',   41;
    1, '3NRM-RRNS',   48;
    2, 'C-RRNS-MLD',  61;
    3, 'C-RRNS-MRC',  61;
    4, 'C-RRNS-CRT',  61;  % DISABLED: CRT not applicable to {64,63,65} moduli set
    5, 'RS',          48;
};

% Fault modes: [burst_len, error_mode_str]
FAULT_MODES = {
    1, 'Random Single Bit';
    5, 'Cluster (Burst)';   % Bug #104 verification: Cluster L=5 only
    8, 'Cluster (Burst)';
    12, 'Cluster (Burst)';
    15, 'Cluster (Burst)';
};

% Output directory
RESULT_DIR = fullfile(fileparts(mfilename('fullpath')), 'results');
if ~exist(RESULT_DIR, 'dir')
    mkdir(RESULT_DIR);
end

%% ─── Main Loop ──────────────────────────────────────────────────────────────

fprintf('=============================================================\n');
fprintf('MATLAB BER Simulation — FPGA-Consistent Fault Injection Model\n');
fprintf('Sample count per BER point: %d\n', SAMPLE_COUNT);
fprintf('=============================================================\n\n');

total_runs = size(ALGO_LIST, 1) * size(FAULT_MODES, 1);
run_idx = 0;

for fi = 1:size(FAULT_MODES, 1)
    burst_len   = FAULT_MODES{fi, 1};
    mode_str    = FAULT_MODES{fi, 2};

    for ai = 1:size(ALGO_LIST, 1)
        algo_id   = ALGO_LIST{ai, 1};
        algo_name = ALGO_LIST{ai, 2};
        w_valid   = ALGO_LIST{ai, 3};

        run_idx = run_idx + 1;
        fprintf('[Run %d/%d] Algo=%s  BurstLen=%d  Mode=%s\n', ...
            run_idx, total_runs, algo_name, burst_len, mode_str);
        fprintf('  Starting BER sweep (%d points × %d samples)...\n', ...
            NUM_BER_POINTS, SAMPLE_COUNT);

        % RS algorithm (algo_id=5) uses smaller sample count for quick trend check
        % RS uses gf() objects which are much slower than RRNS integer operations
        if algo_id == 5
            effective_samples = 100000;
            fprintf('  [RS] Using reduced sample count %d for quick trend check\n', effective_samples);
        else
            effective_samples = SAMPLE_COUNT;
        end

        t_start = tic;

        % Run BER sweep
        results = ber_sweep(algo_id, algo_name, w_valid, burst_len, ...
                            mode_str, effective_samples, NUM_BER_POINTS);

        elapsed = toc(t_start);
        fprintf('  Done in %.1f seconds.\n\n', elapsed);

        % Save to CSV
        timestamp = datestr(now, 'yyyymmdd_HHMMSS');
        csv_filename = fullfile(RESULT_DIR, ...
            sprintf('test_results_%s.csv', timestamp));
        save_results_csv(results, algo_id, algo_name, mode_str, ...
                         burst_len, SAMPLE_COUNT, csv_filename);
        fprintf('  Saved: %s\n\n', csv_filename);

        % Small pause to ensure unique timestamps
        pause(1.1);
    end
end

fprintf('=============================================================\n');
fprintf('All simulations complete. Results saved to:\n  %s\n', RESULT_DIR);
fprintf('=============================================================\n');
fprintf('\nTo generate comparison plots, run compare_ber_curves.py\n');
fprintf('(copy CSV files to src/PCpython/result/sum_result/ first)\n');
