// =============================================================================
// File: top_fault_tolerance_test.v
// Description: Top-Level Fault Tolerance Test System
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.1.3.2
// Version: v1.0
//
// ─────────────────────────────────────────────────────────────────────────────
// SYSTEM ARCHITECTURE:
//
//   ┌─────────────────────────────────────────────────────────────────────┐
//   │                    top_fault_tolerance_test                         │
//   │                                                                     │
//   │  uart_rx_pin ──► [uart_rx_module] ──► rx_byte/rx_valid             │
//   │                                           │                         │
//   │                                    [protocol_parser]                │
//   │                                           │ cfg_update_pulse        │
//   │                                           │ cfg_algo_id             │
//   │                                           │ cfg_burst_len           │
//   │                                           │ cfg_error_mode          │
//   │                                           │ cfg_sample_count        │
//   │                                           ▼                         │
//   │                                  [ctrl_register_bank]               │
//   │                                           │ test_active             │
//   │                                           │ reg_algo_id             │
//   │                                           │ reg_burst_len           │
//   │                                           ▼                         │
//   │  cfg_update_pulse ──────────────► [seed_lock_unit]                  │
//   │  free_counter ──────────────────►     │ seed_locked                 │
//   │                                       │ seed_valid                  │
//   │                                       ▼                             │
//   │                              [main_scan_fsm]                        │
//   │                                       │ tx_valid/tx_data            │
//   │                                       ▼                             │
//   │                              [uart_tx_module] ──► uart_tx_pin       │
//   │                                                                     │
//   │  LED[0] ◄── led_cfg_ok  (FSM IDLE state)                           │
//   │  LED[1] ◄── led_running (FSM RUN_TEST state)                        │
//   │  LED[2] ◄── led_sending (FSM DO_UPLOAD state)                       │
//   │  LED[3] ◄── led_error   (FSM unexpected state)                      │
//   └─────────────────────────────────────────────────────────────────────┘
//
// LED STATUS MAPPING (Active High, per top_fault_tolerance_test.vh):
//   led_status[`LED_IDX_CFG_OK]  = led_cfg_ok  → FSM IDLE (ready for start)
//   led_status[`LED_IDX_RUNNING] = led_running → FSM RUN_TEST (sweep active)
//   led_status[`LED_IDX_SENDING] = led_sending → FSM DO_UPLOAD (UART TX)
//   led_status[`LED_IDX_ERROR]   = led_error   → FSM error/unexpected state
//
// UART BAUD RATE: 921,600 bps (BAUD_DIV=109 @ 100MHz)
//
// SEED LOCK MECHANISM:
//   A free-running 32-bit counter provides entropy. When cfg_update_pulse
//   arrives (valid config received via UART), seed_lock_unit captures the
//   counter value as the PRBS seed for the entire 91-point sweep.
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

    input  wire        rst_n,
    // rst_n: Active-low asynchronous reset (from board reset button / SW0).

    // -------------------------------------------------------------------------
    // UART Interface
    // -------------------------------------------------------------------------
    input  wire        uart_rx,
    // uart_rx: UART receive pin (from USB-UART bridge).

    output wire        uart_tx,
    // uart_tx: UART transmit pin (to USB-UART bridge).

    // -------------------------------------------------------------------------
    // Abort Button (BUG FIX P5)
    // -------------------------------------------------------------------------
    input  wire        btn_abort,
    // btn_abort: Active-High board button for emergency FSM abort.
    //   Mapped to Arty A7 Left Button (B9) in top.xdc.
    //   When pressed (HIGH), immediately returns main_scan_fsm to IDLE,
    //   clearing all in-progress test state. Provides hardware recovery
    //   from any deadlock without requiring a full power cycle.
    //   Signal is debounced internally (16ms filter) before use.

    // -------------------------------------------------------------------------
    // LED Debug Interface (Active High)
    // -------------------------------------------------------------------------
    output wire [`LED_WIDTH-1:0] led_status,
    // led_status[0]: cfg_ok  — FSM in IDLE, config received, waiting for start
    // led_status[1]: running — FSM in RUN_TEST, BER sweep in progress
    // led_status[2]: sending — FSM in DO_UPLOAD, UART transmission in progress
    // led_status[3]: error   — FSM in unexpected/error state

    output wire [`LED_RESERVED_WIDTH-1:0] led_reserved
    // led_reserved: Grounded reserved LEDs [7:4] for future ILA triggers.
);

    // =========================================================================
    // 1. Reserved LEDs: Grounded
    // =========================================================================
    assign led_reserved = {`LED_RESERVED_WIDTH{1'b0}};

    // =========================================================================
    // 2. Synchronized Reset
    // =========================================================================
    // Two-stage synchronizer for rst_n to prevent metastability.
    // The reset_sync module (already in src/io/) handles this.
    wire rst_n_sync;

    reset_sync u_rst_sync (
        .clk_100m (clk_sys),
        .rst_n_i  (rst_n),
        .sys_rst_n(rst_n_sync)
    );

    // =========================================================================
    // 2b. Abort Button Debounce + Synchronization (BUG FIX P5)
    // =========================================================================
    // btn_abort is a raw board button (Arty A7 Left Button, B9, Active-High).
    // It must be debounced before use to prevent glitches from triggering
    // spurious aborts. The button_debounce module (src/io/button_debounce.v)
    // provides a 16ms filter (COUNT_MAX=1,600,000 @ 100MHz).
    //
    // ABORT SIGNAL POLARITY:
    //   btn_abort = 1 (button pressed)  → sys_abort = 1 → FSM returns to IDLE
    //   btn_abort = 0 (button released) → sys_abort = 0 → normal operation
    //
    // SAFETY NOTE: sys_abort is level-sensitive in main_scan_fsm (highest
    // priority, overrides all states). The debounce filter ensures the abort
    // pulse lasts at least 16ms, which is long enough for the FSM to see it
    // and return to IDLE, but short enough to not interfere with re-start.
    //
    // DEBOUNCE COUNT: 1,600,000 cycles = 16ms @ 100MHz (same as top_module.v)

    localparam ABORT_DEBOUNCE_COUNT = 32'd1600000; // 16ms @ 100MHz

    wire btn_abort_debounced; // Debounced, Active-High abort signal

    button_debounce #(
        .COUNT_MAX (ABORT_DEBOUNCE_COUNT)
    ) u_btn_abort_debounce (
        .clk_100m  (clk_sys),
        .sys_rst_n (rst_n_sync),
        .btn_in    (btn_abort),
        .btn_out   (btn_abort_debounced)
    );

    // sys_abort: Active-High, connected directly to main_scan_fsm.sys_abort.
    // When HIGH, main_scan_fsm immediately returns to IDLE from any state.
    // ctrl_register_bank is NOT notified of abort (test_active remains HIGH
    // until the next cfg_update_pulse or test_done_flag). This is intentional:
    // after abort, the user must re-send a config frame to restart the test,
    // which will naturally clear test_active via the normal flow.
    wire sys_abort_w;
    assign sys_abort_w = btn_abort_debounced;

    // =========================================================================
    // 3. Free-Running Counter (Entropy Source for Seed Lock Unit)
    // =========================================================================
    // A 32-bit counter that increments every clock cycle.
    // Provides pseudo-random entropy for seed capture.
    reg [31:0] free_counter;

    always @(posedge clk_sys or negedge rst_n_sync) begin
        if (!rst_n_sync) free_counter <= 32'd1; // Start at 1 (avoid zero)
        else             free_counter <= free_counter + 1'b1;
    end

    // =========================================================================
    // 4. UART RX Module
    // =========================================================================
    wire       rx_valid;
    wire [7:0] rx_byte;
    wire       rx_error; // Frame error (not used in top, but available for debug)

    uart_rx_module u_uart_rx (
        .clk_100m   (clk_sys),
        .sys_rst_n  (rst_n_sync),
        .rx_valid   (rx_valid),
        .rx_data    (rx_byte),
        .rx_error   (rx_error),
        .uart_rx_pin(uart_rx)
    );

    // =========================================================================
    // 5. Protocol Parser
    // =========================================================================
    // Parses incoming UART byte stream into configuration fields.
    // Frame format: [0xAA][0x55][CMD_ID][LEN][Payload...][Checksum]
    // On valid config frame: asserts cfg_update_pulse for one cycle.

    wire        cfg_update_pulse;
    wire [7:0]  cfg_algo_id;
    wire [7:0]  cfg_burst_len;
    wire [7:0]  cfg_error_mode;
    wire [31:0] cfg_sample_count;
    wire [2:0]  parser_state_dbg;  // Debug: parser FSM state
    wire        checksum_error;    // Debug: checksum mismatch indicator

    protocol_parser u_parser (
        .clk             (clk_sys),
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
    // 6. Control Register Bank
    // =========================================================================
    // Latches configuration from protocol_parser.
    // Outputs registered config values to main_scan_fsm.
    // test_active: asserted when a test is running (from FSM busy signal).

    wire        fsm_busy;   // From main_scan_fsm (connected below)
    wire        fsm_done;   // From main_scan_fsm (connected below)
    wire        tx_busy_w;  // From uart_tx_module (connected below)

    wire        test_active;    // From register bank → FSM start trigger
    wire        config_locked;  // From register bank → seed lock enable
    wire [7:0]  reg_algo_id;    // Registered algorithm ID
    wire [7:0]  reg_burst_len;  // Registered burst length
    wire [7:0]  reg_error_mode; // Registered error mode
    wire [31:0] reg_sample_count; // Registered sample count

    ctrl_register_bank u_reg_bank (
        .clk              (clk_sys),
        .rst_n            (rst_n_sync),
        // Configuration input from parser
        .cfg_update_pulse (cfg_update_pulse),
        .cfg_algo_id_in   (cfg_algo_id),
        .cfg_burst_len_in (cfg_burst_len),
        .cfg_error_mode_in(cfg_error_mode),
        .cfg_sample_count_in(cfg_sample_count),
        // Runtime status inputs
        .test_done_flag   (fsm_done),
        .tx_busy          (tx_busy_w),
        // Control outputs
        .test_active      (test_active),
        .config_locked    (config_locked),
        // Registered configuration outputs
        .reg_algo_id      (reg_algo_id),
        .reg_burst_len    (reg_burst_len),
        .reg_error_mode   (reg_error_mode),
        .reg_sample_count (reg_sample_count)
    );

    // =========================================================================
    // 6b. cfg_update_pulse Delay Register (1-cycle delay for seed_lock_unit)
    // =========================================================================
    // BUG FIX (P2): cfg_update_pulse and config_locked are generated in the
    // same clock cycle by ctrl_register_bank (non-blocking assignment).
    // At the rising edge when cfg_update_pulse=1, config_locked is still 0
    // (the new value takes effect on the NEXT cycle).
    //
    // seed_lock_unit requires: lock_en=1 AND capture_pulse=1 simultaneously.
    // If capture_pulse is connected directly to cfg_update_pulse, the condition
    // lock_en(=0) && capture_pulse(=1) is NEVER satisfied → seed never latched.
    //
    // Fix: Delay cfg_update_pulse by 1 cycle so it aligns with config_locked.
    //   T+0: cfg_update_pulse=1, config_locked←1 (NBA, not yet visible)
    //   T+1: cfg_update_pulse_d1=1, config_locked=1 → condition satisfied ✓
    reg cfg_update_pulse_d1;
    always @(posedge clk_sys or negedge rst_n_sync) begin
        if (!rst_n_sync) cfg_update_pulse_d1 <= 1'b0;
        else             cfg_update_pulse_d1 <= cfg_update_pulse;
    end

    // =========================================================================
    // 7. Seed Lock Unit (External to main_scan_fsm, per design requirement)
    // =========================================================================
    // Captures free_counter value when cfg_update_pulse_d1 arrives (1 cycle
    // after cfg_update_pulse), which is aligned with config_locked going HIGH.
    // lock_en: HIGH during the entire scan task (tied to config_locked).
    // capture_pulse: cfg_update_pulse_d1 (delayed 1 cycle to align with lock_en).

    wire [31:0] seed_locked;
    wire        seed_valid;

    seed_lock_unit u_seed_lock (
        .clk          (clk_sys),
        .rst_n        (rst_n_sync),
        .lock_en      (config_locked),
        .capture_pulse(cfg_update_pulse_d1), // FIX: use 1-cycle delayed pulse
        .free_cnt_val (free_counter),
        .seed_locked  (seed_locked),
        .seed_valid   (seed_valid)
    );

    // =========================================================================
    // 8. Main Scan FSM (Core Engine)
    // =========================================================================
    // Orchestrates the full 91-point BER sweep.
    // Outputs tx_valid/tx_data for UART transmission via uart_tx_module.
    // Outputs LED debug signals directly from internal FSM state.

    wire        fsm_tx_valid;
    wire [7:0]  fsm_tx_data;
    wire [1:0]  fsm_status;
    wire [6:0]  fsm_ber_cnt;

    // LED signals from FSM (directly driven by state register)
    wire        led_cfg_ok_w;
    wire        led_running_w;
    wire        led_sending_w;
    wire        led_error_w;

    main_scan_fsm u_fsm (
        .clk          (clk_sys),
        .rst_n        (rst_n_sync),
        // Control inputs
        .sys_start    (test_active),          // test_active from register bank
        .sys_abort    (sys_abort_w),          // FIX P5: connected to debounced btn_abort (B9)
        .sample_count (reg_sample_count),     // FIX Issue2: N trials per BER point
        .mode_id      (reg_error_mode[1:0]),  // FIX Issue1: error mode → Global Info
        .burst_len    (reg_burst_len[3:0]),   // Lower 4 bits of registered burst length
        .seed_in      (seed_locked),          // Locked seed from seed_lock_unit
        .load_seed    (cfg_update_pulse),     // Reload seed on new config
        // Status outputs
        .busy         (fsm_busy),
        .done         (fsm_done),
        .status       (fsm_status),
        .ber_cnt_out  (fsm_ber_cnt),
        // UART TX output (byte stream to uart_tx_module)
        .tx_valid     (fsm_tx_valid),
        .tx_data      (fsm_tx_data),
        .tx_ready     (~tx_busy_w),           // Ready when UART TX is not busy
        // LED debug outputs
        .led_cfg_ok   (led_cfg_ok_w),
        .led_running  (led_running_w),
        .led_sending  (led_sending_w),
        .led_error    (led_error_w)
    );

    // =========================================================================
    // 9. UART TX Module
    // =========================================================================
    // Serializes bytes from main_scan_fsm (via tx_packet_assembler) to UART.
    // tx_en: driven by fsm_tx_valid (byte available from assembler).
    // tx_busy: fed back to FSM as ~tx_ready.

    uart_tx_module u_uart_tx (
        .clk_100m   (clk_sys),
        .sys_rst_n  (rst_n_sync),
        .tx_en      (fsm_tx_valid),
        .tx_data    (fsm_tx_data),
        .tx_busy    (tx_busy_w),
        .uart_tx_pin(uart_tx)
    );

    // =========================================================================
    // 10. LED Status Assignment
    // =========================================================================
    // Map FSM LED signals to led_status bus using macros from .vh.
    // Active High. Each bit directly reflects the corresponding FSM state.
    //
    //   led_status[LED_IDX_CFG_OK=0]  ← led_cfg_ok  (FSM IDLE)
    //   led_status[LED_IDX_RUNNING=1] ← led_running (FSM RUN_TEST)
    //   led_status[LED_IDX_SENDING=2] ← led_sending (FSM DO_UPLOAD)
    //   led_status[LED_IDX_ERROR=3]   ← led_error   (FSM unexpected)

    assign led_status[`LED_IDX_CFG_OK]  = led_cfg_ok_w;
    assign led_status[`LED_IDX_RUNNING] = led_running_w;
    assign led_status[`LED_IDX_SENDING] = led_sending_w;
    assign led_status[`LED_IDX_ERROR]   = led_error_w;

endmodule
