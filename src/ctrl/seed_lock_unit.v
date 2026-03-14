// =============================================================================
// File: seed_lock_unit.v
// Description: Seed Lock Unit - Task-Level Seed Capture with Zero Protection
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Corresponds to Section 2.3.2.1 of Top-Level Design Document (v1.61)
// Version: v2.0 (Redesigned for task-level latch mechanism)
//
// Function Overview:
//   This module captures the value of an external free-running counter into a
//   stable output register (seed_locked) at the start of a test task. The
//   locked seed remains constant throughout the entire 91-point BER scan,
//   ensuring that all test points use the same random sequence origin for
//   statistical consistency.
//
// Task-Level Latch Mechanism (per Section 2.3.2.1):
//   - lock_en is asserted HIGH by the Main Scan FSM when it enters INIT state,
//     and remains HIGH for the entire 91-point scan (INIT -> ... -> DONE).
//   - capture_pulse is a single-cycle pulse generated when a valid config frame
//     is received (cfg_update_pulse from protocol_parser). It occurs exactly
//     ONCE per test task, at the very beginning.
//   - Latching condition: lock_en=1 AND capture_pulse=1 (single clock edge)
//   - After latching, seed_locked is frozen until the next reset or new task.
//
// Zero-Value Protection:
//   If free_cnt_val happens to be 0 at the capture moment (extremely rare),
//   the module substitutes SEED_SAFE_DEFAULT (0xDEADBEEF) instead. This
//   prevents the downstream LFSR from entering the all-zero lock-up state
//   where it would produce only zeros forever.
//
// seed_valid Output:
//   Combinationally asserted HIGH when seed_locked is non-zero, indicating
//   that a valid seed has been captured and is ready for use.
// =============================================================================

`include "seed_lock_unit.vh"

module seed_lock_unit (
    `SEED_LOCK_UNIT_PORTS
);

    // =========================================================================
    // Internal Register: Tracks whether a valid seed has been latched
    // =========================================================================
    // seed_locked is declared as 'output reg' in the port macro.
    // We use a separate flag to track validity state.
    reg seed_valid_reg;

    // =========================================================================
    // seed_valid: Combinational Output
    //   Asserted HIGH when seed_locked is non-zero (valid seed captured).
    //   This is a wire output per the port definition.
    // =========================================================================
    assign seed_valid = seed_valid_reg;

    // =========================================================================
    // Sequential Logic: Task-Level Seed Capture
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // -----------------------------------------------------------------
            // Asynchronous Reset:
            //   Clear seed_locked to 0 and deassert seed_valid.
            //   The downstream logic must check seed_valid before using
            //   seed_locked to avoid using a stale or zero seed.
            // -----------------------------------------------------------------
            seed_locked    <= `SEED_WIDTH'h0;
            seed_valid_reg <= 1'b0;

        end else begin

            // -----------------------------------------------------------------
            // FIX S1: seed_valid_reg stale across test runs
            // -----------------------------------------------------------------
            // PROBLEM: seed_valid_reg was never cleared after the first test.
            //   Once set to 1, it remained HIGH for the entire FPGA session.
            //   On the second test, lock_en goes HIGH before capture_pulse_d1
            //   arrives. During this 1-cycle window, seed_valid=1 but
            //   seed_locked still holds the PREVIOUS test's seed value.
            //   Any FSM logic that checks seed_valid before capture_pulse_d1
            //   arrives would see a stale (but "valid") seed.
            //
            // FIX: When lock_en deasserts (task ends, FSM returns to IDLE),
            //   clear both seed_locked and seed_valid_reg. This ensures that
            //   at the start of every new test, seed_valid=0 until the new
            //   capture_pulse_d1 arrives and latches a fresh seed.
            //
            // TIMING IMPACT: None. lock_en is driven by ctrl_register_bank's
            //   config_locked, which deasserts when test_done_flag is received
            //   (FSM FINISH state). By that time, all 91 BER points are done
            //   and the seed is no longer needed. Clearing it here is safe.
            // -----------------------------------------------------------------
            if (!lock_en) begin
                // Task ended (or not yet started): invalidate seed for next run
                seed_locked    <= `SEED_WIDTH'h0;
                seed_valid_reg <= 1'b0;

            end else if (capture_pulse) begin
                // -----------------------------------------------------------------
                // Task-Level Latch Logic (lock_en=1 implied by else-if structure):
                //   Condition: lock_en=1 (task is active/starting) AND
                //              capture_pulse=1 (config received, latch now)
                //
                //   lock_en acts as a gate: if the FSM is not in an active task
                //   (lock_en=0), any spurious capture_pulse is completely ignored
                //   by the !lock_en branch above (seed cleared, not latched).
                //
                //   In normal operation, capture_pulse occurs exactly ONCE per
                //   task (at the INIT state entry). After this single capture,
                //   seed_locked remains frozen for the entire 91-point scan.
                // -----------------------------------------------------------------

                // -------------------------------------------------------------
                // Zero-Value Protection:
                //   Check if free_cnt_val is zero at the capture moment.
                //   A zero seed would cause the downstream LFSR to lock up
                //   (all-zero state is a fixed point: 0 XOR 0 = 0 forever).
                //   In this extremely rare case, substitute SEED_SAFE_DEFAULT.
                // -------------------------------------------------------------
                if (free_cnt_val != `SEED_WIDTH'h0) begin
                    // Normal case: latch the free-running counter value
                    seed_locked <= free_cnt_val;
                end else begin
                    // Safety fallback: counter was zero, use safe default seed
                    seed_locked <= `SEED_SAFE_DEFAULT;
                end

                // Mark seed as valid (will be non-zero after this assignment)
                seed_valid_reg <= 1'b1;

            end
            // else: lock_en=1, capture_pulse=0 → hold seed_locked stable
            // (steady-state during the 91-point scan, seed must not change)

        end
    end

endmodule
