// =============================================================================
// File: top_fault_tolerance_test.v
// Description: Top-Level Fault Tolerance Test System
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.1.3.2
// Version: v1.1 (Plan B: True 50MHz operation via MMCM for functional verification)
//
// CLOCK ARCHITECTURE (v1.1):
//   clk_sys (100MHz board oscillator) → MMCM → clk_50mhz (50MHz)
//   All logic runs on clk_50mhz.
//   UART BAUD_DIV updated to 54 (50MHz / 921,600 ≈ 54.25 → 54).
//   XDC clock constraint: 20ns (50MHz).
//   This ensures hardware truly runs at 50MHz with no timing violations,
//   allowing clean functional verification without WNS-induced errors.
//   After functional verification, revert to 100MHz by removing MMCM.
//
// UART BAUD RATE: 921,600 bps (BAUD_DIV=54 @ 50MHz)
//   50,000,000 / 921,600 = 54.25 → 54 (rounded)
//   Actual baud rate = 50,000,000 / 54 = 925,926 bps
//   Error = 0.47% (within UART ±3% tolerance)
// =============================================================================

`include "top_fault_tolerance_test.vh"
`include "main_scan_fsm.vh"
`timescale 1ns / 1ps

module top_fault_tolerance_test (
    // -------------------------------------------------------------------------
    // Global Clock & Reset
    // -------------------------------------------------------------------------
    input  wire        clk_sys,
    // clk_sys: 100 MHz system clock from board oscillator.
    // MMCM divides this to 50MHz for all internal logic.

    input  wire        rst_n,
    // rst_n: Active-low asynchronous reset (from board reset button / SW0).

    // -------------------------------------------------------------------------
    // UART Interface
    // -------------------------------------------------------------------------
    input  wire        uart_rx,
    output wire        uart_tx,

    // -------------------------------------------------------------------------
    // Abort Button
    // -------------------------------------------------------------------------
    input  wire        btn_abort,

    // -------------------------------------------------------------------------
    // LED Debug Interface (Active High)
    // -------------------------------------------------------------------------
    output wire [`LED_WIDTH-1:0] led_status,
    output wire [`LED_RESERVED_WIDTH-1:0] led_reserved
);

    // =========================================================================
    // 0. Reserved LEDs: Grounded
    // =========================================================================
    assign led_reserved = {`LED_RESERVED_WIDTH{1'b0}};

    // =========================================================================
    // 1. MMCM: Generate 50MHz from 100MHz input clock
    //    MMCME2_BASE configuration:
    //      Input:  100MHz (CLKIN1_PERIOD = 10.0ns)
    //      VCO:    100MHz × 10 = 1000MHz (CLKFBOUT_MULT_F = 10.0)
    //      Output: 1000MHz / 20 = 50MHz  (CLKOUT0_DIVIDE_F = 20.0)
    //    VCO frequency 1000MHz is within Artix-7 MMCM VCO range (600-1200MHz).
    // =========================================================================
    wire clk_50mhz;       // 50MHz output clock for all logic
    wire mmcm_clkfb;      // MMCM feedback clock
    wire mmcm_locked;     // MMCM lock indicator

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (10.0),     // VCO = 100MHz × 10 = 1000MHz
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (10.0),     // Input clock period = 10ns (100MHz)
        .CLKOUT0_DIVIDE_F   (20.0),     // Output = 1000MHz / 20 = 50MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT4_CASCADE    ("FALSE"),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.0),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKIN1   (clk_sys),        // 100MHz input
        .CLKFBIN  (mmcm_clkfb),     // Feedback input
        .CLKOUT0  (clk_50mhz),      // 50MHz output (unbuffered)
        .CLKFBOUT (mmcm_clkfb),     // Feedback output
        .LOCKED   (mmcm_locked),    // Lock indicator
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );

    // =========================================================================
    // 2. Synchronized Reset (using 50MHz clock)
    //    rst_n_sync is asserted until MMCM is locked AND rst_n is HIGH.
    // =========================================================================
    wire rst_n_sync;

    reset_sync u_rst_sync (
        .clk_100m (clk_50mhz),      // Use 50MHz clock for reset sync
        .rst_n_i  (rst_n & mmcm_locked),  // Hold reset until MMCM locked
        .sys_rst_n(rst_n_sync)
    );

    // =========================================================================
    // 3. Abort Button Debounce (16ms @ 50MHz = 800,000 cycles)
    //    At 50MHz: 800,000 cycles × 20ns = 16ms
    // =========================================================================
    localparam ABORT_DEBOUNCE_COUNT = 32'd800000; // 16ms @ 50MHz

    wire btn_abort_debounced;

    button_debounce #(
        .COUNT_MAX (ABORT_DEBOUNCE_COUNT)
    ) u_btn_abort_debounce (
        .clk_100m  (clk_50mhz),     // Use 50MHz clock
        .sys_rst_n (rst_n_sync),
        .btn_in    (btn_abort),
        .btn_out   (btn_abort_debounced)
    );

    wire sys_abort_w;
    assign sys_abort_w = btn_abort_debounced;

    // =========================================================================
    // 4. Free-Running Counter (Entropy Source)
    // =========================================================================
    reg [31:0] free_counter;

    always @(posedge clk_50mhz or negedge rst_n_sync) begin
        if (!rst_n_sync) free_counter <= 32'd1;
        else             free_counter <= free_counter + 1'b1;
    end

    // =========================================================================
    // 5. UART RX Module (50MHz clock, BAUD_DIV=54 in uart_rx_module.v)
    // =========================================================================
    wire       rx_valid;
    wire [7:0] rx_byte;
    wire       rx_error;

    uart_rx_module u_uart_rx (
        .clk_100m   (clk_50mhz),    // Use 50MHz clock
        .sys_rst_n  (rst_n_sync),
        .rx_valid   (rx_valid),
        .rx_data    (rx_byte),
        .rx_error   (rx_error),
        .uart_rx_pin(uart_rx)
    );

    // =========================================================================
    // 6. Protocol Parser
    // =========================================================================
    wire        cfg_update_pulse;
    wire [7:0]  cfg_algo_id;
    wire [7:0]  cfg_burst_len;
    wire [7:0]  cfg_error_mode;
    wire [31:0] cfg_sample_count;
    wire [2:0]  parser_state_dbg;
    wire        checksum_error;

    protocol_parser u_parser (
        .clk             (clk_50mhz),   // Use 50MHz clock
        .rst_n           (rst_n_sync),
        .rx_byte         (rx_byte),
        .rx_valid        (rx_valid),
        .cfg_update_pulse(cfg_update_pulse),
        .cfg_algo_id     (cfg_algo_id),
        .cfg_burst_len   (cfg_burst_len),
        .cfg_error_mode  (cfg_error_mode),
        .cfg_sample_count(cfg_sample_count),
        .state_dbg       (parser_state_dbg),
        .checksum_error  (checksum_error)
    );

    // =========================================================================
    // 7. Control Register Bank
    // =========================================================================
    wire        fsm_busy;
    wire        fsm_done;
    wire        tx_busy_w;
    wire        test_active;
    wire        config_locked;
    wire [7:0]  reg_algo_id;
    wire [7:0]  reg_burst_len;
    wire [7:0]  reg_error_mode;
    wire [31:0] reg_sample_count;

    ctrl_register_bank u_reg_bank (
        .clk              (clk_50mhz),  // Use 50MHz clock
        .rst_n            (rst_n_sync),
        .cfg_update_pulse (cfg_update_pulse),
        .cfg_algo_id_in   (cfg_algo_id),
        .cfg_burst_len_in (cfg_burst_len),
        .cfg_error_mode_in(cfg_error_mode),
        .cfg_sample_count_in(cfg_sample_count),
        .test_done_flag   (fsm_done),
        .tx_busy          (tx_busy_w),
        .test_active      (test_active),
        .config_locked    (config_locked),
        .reg_algo_id      (reg_algo_id),
        .reg_burst_len    (reg_burst_len),
        .reg_error_mode   (reg_error_mode),
        .reg_sample_count (reg_sample_count)
    );

    // =========================================================================
    // 8. cfg_update_pulse Delay Register (1-cycle delay for seed_lock_unit)
    // =========================================================================
    reg cfg_update_pulse_d1;
    always @(posedge clk_50mhz or negedge rst_n_sync) begin
        if (!rst_n_sync) cfg_update_pulse_d1 <= 1'b0;
        else             cfg_update_pulse_d1 <= cfg_update_pulse;
    end

    // =========================================================================
    // 9. Seed Lock Unit
    // =========================================================================
    wire [31:0] seed_locked;
    wire        seed_valid;

    seed_lock_unit u_seed_lock (
        .clk          (clk_50mhz),  // Use 50MHz clock
        .rst_n        (rst_n_sync),
        .lock_en      (config_locked),
        .capture_pulse(cfg_update_pulse_d1),
        .free_cnt_val (free_counter),
        .seed_locked  (seed_locked),
        .seed_valid   (seed_valid)
    );

    // =========================================================================
    // 10. Main Scan FSM
    // =========================================================================
    wire        fsm_tx_valid;
    wire [7:0]  fsm_tx_data;
    wire [1:0]  fsm_status;
    wire [6:0]  fsm_ber_cnt;
    wire        led_cfg_ok_w;
    wire        led_running_w;
    wire        led_sending_w;
    wire        led_error_w;

    main_scan_fsm u_fsm (
        .clk          (clk_50mhz),  // Use 50MHz clock
        .rst_n        (rst_n_sync),
        .sys_start    (test_active),
        .sys_abort    (sys_abort_w),
        .sample_count (reg_sample_count),
        .mode_id      (reg_error_mode[1:0]),
        .burst_len    (reg_burst_len[3:0]),
        .seed_in      (seed_locked),
        .load_seed    (cfg_update_pulse),
        .busy         (fsm_busy),
        .done         (fsm_done),
        .status       (fsm_status),
        .ber_cnt_out  (fsm_ber_cnt),
        .tx_valid     (fsm_tx_valid),
        .tx_data      (fsm_tx_data),
        .tx_ready     (~tx_busy_w),
        .led_cfg_ok   (led_cfg_ok_w),
        .led_running  (led_running_w),
        .led_sending  (led_sending_w),
        .led_error    (led_error_w)
    );

    // =========================================================================
    // 11. UART TX Module (50MHz clock, BAUD_DIV=54 in uart_tx_module.v)
    // =========================================================================
    uart_tx_module u_uart_tx (
        .clk_100m   (clk_50mhz),    // Use 50MHz clock
        .sys_rst_n  (rst_n_sync),
        .tx_en      (fsm_tx_valid),
        .tx_data    (fsm_tx_data),
        .tx_busy    (tx_busy_w),
        .uart_tx_pin(uart_tx)
    );

    // =========================================================================
    // 12. LED Status Assignment
    // =========================================================================
    assign led_status[`LED_IDX_CFG_OK]  = led_cfg_ok_w;
    assign led_status[`LED_IDX_RUNNING] = led_running_w;
    assign led_status[`LED_IDX_SENDING] = led_sending_w;
    assign led_status[`LED_IDX_ERROR]   = led_error_w;

endmodule
