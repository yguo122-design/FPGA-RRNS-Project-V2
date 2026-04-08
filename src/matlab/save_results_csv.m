function save_results_csv(results, algo_id, algo_name, mode_str, ...
                          burst_len, sample_count, filename)
% SAVE_RESULTS_CSV  Save BER sweep results to CSV (FPGA-compatible format).
%
%   The output CSV format matches the FPGA result CSV files, enabling
%   direct use with compare_ber_curves.py for comparison plots.
%
%   Enc/Dec clock counts are filled with FPGA-measured reference values
%   (from Table 4.2 of the dissertation) so that the CSV is fully
%   compatible with the FPGA result format and latency comparison scripts.
%   This follows Gemini's "Hardware-Equivalent Simulation" recommendation:
%   MATLAB validates BER performance; FPGA reference latencies provide the
%   hardware timing dimension for a complete multi-dimensional comparison.

    % FPGA-measured reference latencies (cycles at 50 MHz, from Table 4.2)
    % Format: algo_id → [enc_cycles, dec_cycles]
    enc_ref = containers.Map({6,1,2,3,4,5}, {7, 5, 5, 5, 5, 4});
    dec_ref = containers.Map({6,1,2,3,4,5}, {24, 844, 928, 9, 7, 137});

    if isKey(enc_ref, algo_id)
        enc_cyc = enc_ref(algo_id);
        dec_cyc = dec_ref(algo_id);
    else
        enc_cyc = 0;
        dec_cyc = 0;
    end

    fid = fopen(filename, 'w');
    if fid == -1
        error('save_results_csv: cannot open file: %s', filename);
    end

    % Header metadata (matches FPGA CSV format)
    fprintf(fid, '"Test Report (MATLAB Simulation — FPGA-Consistent Fault Injection)"\n');
    fprintf(fid, 'Timestamp,%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Algorithm,%s\n', algo_name);
    fprintf(fid, 'Error Mode,%s\n', mode_str);
    fprintf(fid, 'Burst_Length,%d\n', burst_len);
    fprintf(fid, 'Total Points,%d\n', length(results.ber_idx));
    fprintf(fid, '\n');

    % Column headers (matches FPGA CSV format)
    fprintf(fid, 'BER_Index,BER_Value,Success_Count,Fail_Count,Total_Trials,');
    fprintf(fid, 'Success_Rate,Flip_Count,BER_Value_Act,');
    fprintf(fid, 'Clk_Count,Avg_Clk_Per_Trial,');
    fprintf(fid, 'Enc_Clk_Count,Avg_Enc_Clk_Per_Trial,');
    fprintf(fid, 'Dec_Clk_Count,Avg_Dec_Clk_Per_Trial\n');

    % Data rows
    % Enc/Dec clock counts use FPGA reference values (per-trial × total_trials)
    % This allows direct comparison with FPGA latency data in the same CSV format.
    enc_total = enc_cyc * sample_count;
    dec_total = dec_cyc * sample_count;
    total_clk = (enc_cyc + dec_cyc) * sample_count;

    for i = 1:length(results.ber_idx)
        total_trials = sample_count;
        success_rate = results.success_count(i) / total_trials;

        fprintf(fid, '%d,%.3f,%d,%d,%d,%.3f,%d,%.6f,%d,%d,%d,%d,%d,%d\n', ...
            results.ber_idx(i), ...
            results.ber_value(i), ...
            results.success_count(i), ...
            results.fail_count(i), ...
            total_trials, ...
            success_rate, ...
            results.flip_count(i), ...
            results.ber_value_act(i), ...
            total_clk, enc_cyc + dec_cyc, ...
            enc_total, enc_cyc, ...
            dec_total, dec_cyc);
    end

    fclose(fid);
end
