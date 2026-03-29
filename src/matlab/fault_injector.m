function [codeword_out, flip_count] = fault_injector(codeword_in, w_valid, burst_len, p_trigger)
% FAULT_INJECTOR  Inject burst errors into a codeword (FPGA-consistent model).
%
%   [codeword_out, flip_count] = fault_injector(codeword_in, w_valid,
%                                                burst_len, p_trigger)
%
%   Two injection models depending on burst_len, matching FPGA hardware:
%
%   --- burst_len == 1 (Random Single Bit, Bit-Scan LFSR model) ---
%     Replicates the FPGA's 32-bit Galois LFSR (polynomial x^32+x^22+x^2+x+1).
%     For each bit position 0..(w_valid-1), the LFSR is advanced one step and
%     compared against threshold_val (uint32). If lfsr < threshold_val, that
%     bit is flipped. This matches the FPGA auto_scan_engine.v bit-scan path
%     exactly, including the LFSR correlation structure (error clustering).
%     p_trigger = BER_target  (= threshold_val / (2^32-1), no clamping)
%
%   --- burst_len > 1 (Cluster Burst, single-injection model) ---
%     FPGA-consistent: each trial makes ONE binary inject/no-inject decision.
%     With probability p_trigger, inject exactly ONE burst of burst_len
%     consecutive bits at a random position within [0, w_valid - burst_len].
%     p_trigger = BER_target * w_valid / burst_len  (clamped to [0,1])
%     actual BER upper limit = burst_len / w_valid (same as FPGA hardware).
%
%   Inputs:
%     codeword_in  - uint64 packed codeword (right-aligned, bits [w_valid-1:0])
%     w_valid      - Number of valid codeword bits
%     burst_len    - Number of consecutive bits to flip (1 = single-bit)
%     p_trigger    - Injection probability/mean (see model description above)
%
%   Outputs:
%     codeword_out - uint64 codeword after injection
%     flip_count   - Number of bits actually flipped

    codeword_out = codeword_in;
    flip_count   = 0;

    % Boundary check: burst must fit within valid bits
    if burst_len > w_valid
        return;
    end

    if burst_len == 1
        % ─────────────────────────────────────────────────────────────────
        % Bit-Scan LFSR model (burst_len=1, Random Single Bit)
        % Matches FPGA auto_scan_engine.v bit-scan path exactly.
        %
        % FPGA LFSR specification (from auto_scan_engine.v):
        %   32-bit Galois LFSR, right-shift, polynomial x^32+x^22+x^2+x+1
        %   Feedback bit: inj_lfsr[0] (LSB)
        %   Taps (0-indexed from LSB): [31, 21, 1, 0]
        %   Next state when fb=1: XOR with mask 0x80200003
        %     bit 31 ← fb (= 1)
        %     bit 21 ← bit 22 XOR fb  (tap at output bit 21)
        %     bit 1  ← bit 2  XOR fb  (tap at output bit 1)
        %     bit 0  ← bit 1  XOR fb  (tap at output bit 0)
        %   Next state when fb=0: simple right-shift
        %
        % Threshold comparison: if (inj_lfsr < threshold_val) → flip bit
        % threshold_val = round(BER_target * (2^32 - 1))  [from ROM]
        %
        % LFSR seed: random per trial (matches FPGA random seed behavior)
        % ─────────────────────────────────────────────────────────────────

        % Convert p_trigger (BER_target) to uint32 threshold
        % threshold_val = round(p_trigger * (2^32 - 1))
        threshold_u32 = uint32(round(p_trigger * double(intmax('uint32'))));

        % Initialize LFSR with a random non-zero seed (matches FPGA behavior)
        lfsr = uint32(randi([1, intmax('uint32')]));

        % LFSR XOR mask: bits [31, 21, 1, 0] set (0-indexed from LSB)
        % Derived from FPGA inj_lfsr_next concatenation:
        %   bit31 ← inj_fb (=1)
        %   bit21 ← inj_lfsr[22] XOR inj_fb  → tap at output bit 21
        %   bit1  ← inj_lfsr[2]  XOR inj_fb  → tap at output bit 1
        %   bit0  ← inj_lfsr[1]  XOR inj_fb  → tap at output bit 0
        % When fb=1: lfsr_next = (lfsr >> 1) XOR 0x80200003
        % Verification: 2^31 + 2^21 + 2^1 + 2^0 = 0x80200003
        LFSR_MASK = uint32(hex2dec('80200003'));

        for bit_pos = 0:(w_valid - 1)
            % Advance LFSR one step (Galois right-shift)
            fb = bitand(lfsr, uint32(1));  % feedback bit = LSB
            lfsr = bitshift(lfsr, -1);     % right shift by 1
            if fb
                lfsr = bitxor(lfsr, LFSR_MASK);  % apply polynomial
            end

            % Compare LFSR output against threshold
            if lfsr < threshold_u32
                % Flip bit at position bit_pos
                mask = uint64(bitshift(uint64(1), bit_pos));
                codeword_out = bitxor(codeword_out, mask);
                flip_count   = flip_count + 1;
            end
        end

    else
        % ─────────────────────────────────────────────────────────────────
        % Single-injection model (burst_len>1, Cluster Burst)
        % Matches FPGA error_injector_unit ROM-based path.
        % p_trigger = BER_target * w_valid / burst_len (clamped to [0,1]).
        % Each trial: inject 0 or 1 burst (binary decision).
        % ─────────────────────────────────────────────────────────────────
        if rand() >= p_trigger
            return;  % No injection this trial
        end

        % Random start position: [0, w_valid - burst_len]
        max_offset = w_valid - burst_len;
        if max_offset == 0
            offset = 0;
        else
            offset = randi([1, max_offset + 1]) - 1;  % [0, max_offset]
        end

        % Build burst error mask: burst_len consecutive 1s starting at 'offset'
        mask = uint64(bitshift(uint64(2^burst_len - 1), offset));

        % Apply XOR
        codeword_out = bitxor(codeword_in, mask);
        flip_count   = burst_len;
    end
end
