// =============================================================================
// File: ctrl_register_bank.v
// Description: Control Register Bank Module
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Corresponds to Section 2.2.4 of Top-Level Design Document
// Version: v1.1 (Explicit port list for Verilog-2001 compatibility)
//
// Function Overview:
//   This module acts as the isolation wall between PC configuration and FPGA
//   business logic. It atomically latches all configuration parameters upon
//   receiving a valid configuration pulse, and automatically triggers the
//   test engine. It also handles auto-stop when the test completes.
//
// Key Behaviors:
//   1. Configuration Latching: On cfg_update_pulse (when tx_busy=0),
//      latch all cfg_*_in inputs to reg_* outputs atomically.
//   2. Test Activation: Simultaneously assert test_active and config_locked.
//   3. TX_BUSY Protection: If tx_busy=1, cfg_update_pulse is completely ignored.
//   4. Auto Stop: When test_done_flag is asserted, deassert test_active and
//      config_locked, returning system to idle state.
//   5. Async Reset: All outputs cleared on rst_n assertion.
//
// Port Naming Convention:
//   cfg_*_in  : Raw configuration inputs from protocol_parser (unregistered)
//   reg_*     : Registered/latched configuration outputs to FSM (stable)
// =============================================================================

`include "ctrl_register_bank.vh"
`timescale 1ns / 1ps

module ctrl_register_bank (
    // -------------------------------------------------------------------------
    // Global Clock & Reset
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Configuration Input Interface (from protocol_parser)
    // -------------------------------------------------------------------------
    input  wire        cfg_update_pulse,
    // cfg_update_pulse: Single-cycle pulse from protocol_parser when a valid
    // configuration frame has been received and checksum verified.

    input  wire [7:0]  cfg_algo_id_in,
    // cfg_algo_id_in: Algorithm ID from parser (0=2NRM, 1=3NRM, 2=C-RRNS, 3=RS).

    input  wire [7:0]  cfg_burst_len_in,
    // cfg_burst_len_in: Error burst length from parser (1~15, in 8-bit field).

    input  wire [7:0]  cfg_error_mode_in,
    // cfg_error_mode_in: Error injection mode from parser (reserved for future use).

    input  wire [31:0] cfg_sample_count_in,
    // cfg_sample_count_in: Number of test samples from parser (reserved).

    // -------------------------------------------------------------------------
    // Runtime Status Inputs
    // -------------------------------------------------------------------------
    input  wire        test_done_flag,
    // test_done_flag: Single-cycle pulse from main_scan_fsm when all 91 BER
    // points have been tested and results uploaded. Triggers auto-stop.

    input  wire        tx_busy,
    // tx_busy: HIGH when uart_tx_module is actively transmitting.
    // Prevents configuration updates during UART transmission.

    // -------------------------------------------------------------------------
    // Control Outputs (To Top Level / Main Scan FSM)
    // -------------------------------------------------------------------------
    output reg         test_active,
    // test_active: HIGH when a test is in progress. Connected to sys_start
    // of main_scan_fsm. Asserted on cfg_update_pulse, cleared on test_done_flag.

    output reg         config_locked,
    // config_locked: HIGH when configuration is locked (test running).
    // Connected to seed_lock_unit.lock_en. Prevents seed re-capture during test.

    // -------------------------------------------------------------------------
    // Registered Configuration Outputs (To Algorithm Modules / FSM)
    // -------------------------------------------------------------------------
    output reg  [7:0]  reg_algo_id,
    // reg_algo_id: Latched algorithm ID. Stable for entire test duration.

    output reg  [7:0]  reg_burst_len,
    // reg_burst_len: Latched burst length [7:0]. FSM uses lower 4 bits [3:0].

    output reg  [7:0]  reg_error_mode,
    // reg_error_mode: Latched error mode (reserved for future use).

    output reg  [31:0] reg_sample_count
    // reg_sample_count: Latched sample count (reserved for future use).
);

    // =========================================================================
    // Sequential Logic: Configuration Latching, Test Control, and Auto Stop
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // -----------------------------------------------------------------
            // Asynchronous Reset: Clear all outputs immediately
            // -----------------------------------------------------------------
            test_active      <= 1'b0;
            config_locked    <= 1'b0;
            reg_algo_id      <= 8'd0;
            reg_burst_len    <= 8'd0;
            reg_error_mode   <= 8'd0;
            reg_sample_count <= 32'd0;

        end else begin

            // -----------------------------------------------------------------
            // TX_BUSY Protection Logic:
            //   When uart_tx_module is actively sending a report frame
            //   (~20ms at 921600 bps), any incoming cfg_update_pulse must be
            //   completely ignored to prevent data stream corruption or FSM
            //   state confusion. Only when tx_busy=0 (UART TX is idle) is it
            //   safe to accept a new configuration.
            // -----------------------------------------------------------------
            // -----------------------------------------------------------------
            // Priority: test_done_flag FIRST (highest priority).
            //   Reason: When FSM asserts done=1 and returns to IDLE in the
            //   same clock cycle, test_active must be cleared on the NEXT
            //   cycle before FSM can sample it again. If cfg_update_pulse
            //   were higher priority, a simultaneous pulse could prevent
            //   the clear and cause the FSM to immediately re-trigger.
            // -----------------------------------------------------------------
            if (test_done_flag) begin
                // -------------------------------------------------------------
                // Auto Stop Logic (Highest Priority):
                //   When the Main Scan FSM signals completion (test_done_flag=1),
                //   immediately deassert test_active and config_locked.
                //   This prevents the FSM from re-triggering when it returns
                //   to IDLE in the same clock cycle as done is asserted.
                //   The reg_* values are preserved for post-test inspection.
                // -------------------------------------------------------------
                test_active   <= 1'b0;
                config_locked <= 1'b0;

            end else if (cfg_update_pulse && !tx_busy) begin
                // -------------------------------------------------------------
                // Configuration Latching + Test Activation (Atomic Operation):
                //   Only accepted when: (1) no test is completing this cycle,
                //   and (2) UART TX is not busy transmitting a report.
                //   All four parameters are latched in the same clock cycle
                //   as test_active is asserted, guaranteeing that the
                //   downstream FSM always sees a consistent parameter set.
                // -------------------------------------------------------------
                reg_algo_id      <= cfg_algo_id_in;
                reg_burst_len    <= cfg_burst_len_in;
                reg_error_mode   <= cfg_error_mode_in;
                reg_sample_count <= cfg_sample_count_in;

                // Assert control flags: config is now locked and test starts
                config_locked    <= 1'b1;
                test_active      <= 1'b1;
            end
            // If neither condition is true, all registers hold their values.

        end
    end

endmodule
