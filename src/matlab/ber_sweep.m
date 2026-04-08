function results = ber_sweep(algo_id, algo_name, w_valid, burst_len, ...
                              mode_str, sample_count, num_ber_points)
% BER_SWEEP  Run a full BER sweep for one algorithm and one fault mode.
%            Uses parfor (Parallel Computing Toolbox) to accelerate the
%            inner trial loop across all available CPU cores.
%
%   results = ber_sweep(algo_id, algo_name, w_valid, burst_len, mode_str,
%                       sample_count, num_ber_points)
%
%   Inputs:
%     algo_id        - Algorithm ID (6=2NRM-RRNS-Serial, 1=3NRM, 2=C-RRNS-MLD,
%                      3=C-RRNS-MRC, 5=RS)
%     algo_name      - Algorithm name string (for display)
%     w_valid        - Valid codeword bit width
%     burst_len      - Burst error length (1=random single-bit)
%     mode_str       - Error mode string ('Random Single Bit' or 'Cluster (Burst)')
%     sample_count   - Number of trials per BER point
%     num_ber_points - Number of BER points (101 for 0.0%~10.0%)
%
%   Output:
%     results - struct with fields:
%       ber_idx        [1×101] BER index (0~100)
%       ber_value      [1×101] Target BER value (0.000~0.100)
%       success_count  [1×101] Number of successful decodes
%       fail_count     [1×101] Number of failed decodes
%       flip_count     [1×101] Total bits flipped
%       ber_value_act  [1×101] Actual BER = flip_count/(trials*w_valid)
%
%   Parallelization:
%     The inner trial loop uses parfor to distribute work across CPU cores.
%     On Intel i7-1360P (12 cores), expect ~8-10x speedup vs serial.
%     Parallel pool is started automatically if not already running.
%     Each parfor worker uses an independent random stream (no contention).

    results.ber_idx       = zeros(1, num_ber_points);
    results.ber_value     = zeros(1, num_ber_points);
    results.success_count = zeros(1, num_ber_points);
    results.fail_count    = zeros(1, num_ber_points);
    results.flip_count    = zeros(1, num_ber_points);
    results.ber_value_act = zeros(1, num_ber_points);

    % ─────────────────────────────────────────────────────────────────────
    % Start parallel pool if not already running.
    % Uses all available logical cores by default.
    % On i7-1360P: 12 physical cores → up to 12 workers.
    % ─────────────────────────────────────────────────────────────────────
    pool = gcp('nocreate');
    if isempty(pool)
        parpool('local');  % Start pool with default (max) workers
    end

    % Progress display interval
    PRINT_INTERVAL = 10;

    for ber_idx = 0:(num_ber_points - 1)
        ber_target = ber_idx * 0.001;   % 0.000 to 0.100

        % Compute p_trigger based on injection model:
        %
        % burst_len == 1 (Random Single Bit, Bit-Scan LFSR model):
        %   p_trigger = BER_target  (per-bit flip probability, no clamping)
        %   fault_injector uses LFSR internally with random seed per trial.
        %
        % burst_len > 1 (Cluster Burst, single-injection):
        %   p_trigger = BER_target * w_valid / burst_len  (clamped to [0,1])
        %   fault_injector makes one binary inject/no-inject decision per trial.
        if burst_len <= 0
            p_trigger = 0;
        elseif burst_len == 1
            % Bit-scan LFSR: p_trigger is the per-bit flip probability
            p_trigger = ber_target;  % No clamping needed
        else
            % Single-injection: p_trigger is the burst trigger probability
            p_trigger = min(ber_target * w_valid / burst_len, 1.0);
        end

        % ─────────────────────────────────────────────────────────────────
        % Parallel trial loop using parfor.
        %
        % Each worker independently:
        %   1. Generates a random 16-bit data word
        %   2. Encodes it
        %   3. Injects faults (fault_injector uses its own random state)
        %   4. Decodes
        %   5. Compares
        %
        % Results are collected in pre-allocated arrays (parfor-safe).
        % No shared mutable state between workers.
        %
        % Random number independence:
        %   MATLAB parfor automatically assigns each worker an independent
        %   random stream (using 'combRecursive' generator with different
        %   substreams), so rand()/randi() calls are statistically independent
        %   across workers without any extra setup.
        % ─────────────────────────────────────────────────────────────────
        trial_success = zeros(1, sample_count, 'uint8');  % 1=pass, 0=fail
        trial_flips   = zeros(1, sample_count, 'uint32'); % bits flipped

        parfor trial = 1:sample_count
            % 1. Generate random 16-bit data
            data_orig = randi([0, 65535], 'uint16');

            % 2. Encode
            codeword = encode(uint32(data_orig), algo_id);

            % 3. Fault injection (FPGA-consistent model)
            [codeword_corrupted, flip] = fault_injector(codeword, w_valid, ...
                                                         burst_len, p_trigger);

            % 4. Decode
            [data_recov, uncorrectable] = decode(codeword_corrupted, algo_id);

            % 5. Compare (store result in array, not accumulator)
            if ~uncorrectable && (uint32(data_recov) == uint32(data_orig))
                trial_success(trial) = 1;
            end
            trial_flips(trial) = uint32(flip);
        end

        % Aggregate results after parfor completes
        acc_success = sum(trial_success);
        acc_flip    = sum(trial_flips);

        % Store results
        pt = ber_idx + 1;  % MATLAB 1-based index
        results.ber_idx(pt)       = ber_idx;
        results.ber_value(pt)     = ber_target;
        results.success_count(pt) = acc_success;
        results.fail_count(pt)    = sample_count - acc_success;
        results.flip_count(pt)    = acc_flip;
        results.ber_value_act(pt) = acc_flip / (sample_count * w_valid);

        % Progress display
        if mod(ber_idx, PRINT_INTERVAL) == 0 || ber_idx == num_ber_points - 1
            sr = acc_success / sample_count;
            ber_act = acc_flip / (sample_count * w_valid);
            fprintf('    BER_idx=%3d  target=%.3f%%  actual=%.4f%%  SR=%.4f\n', ...
                ber_idx, ber_target*100, ber_act*100, sr);
        end
    end
end
