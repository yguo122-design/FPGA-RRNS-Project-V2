// =============================================================================
// File: top_fault_tolerance_test.vh
// Description: Header file for Top-Level Fault Tolerance Test System.
//              Defines parameters, state encodings, register addresses, 
//              and port mappings for the top module and sub-modules.
// =============================================================================

`ifndef TOP_FAULT_TOLERANCE_TEST_VH
`define TOP_FAULT_TOLERANCE_TEST_VH

// -----------------------------------------------------------------------------
// 1. Global Parameters
// -----------------------------------------------------------------------------
`define SYS_CLK_FREQ      100000000  // 100 MHz System Clock
`define UART_BAUD_RATE    921600     // 921,600 bps (BAUD_DIV=109 @ 100MHz)

// -----------------------------------------------------------------------------
// 2. LED Debug Interface Definitions
// -----------------------------------------------------------------------------
// The top module exposes a 4-bit LED status bus mapped to FSM states.
// Active High logic.

`define LED_WIDTH         4

// LED Bit Index Mapping
`define LED_IDX_CFG_OK    0          // FSM State: WAIT_START
`define LED_IDX_RUNNING   1          // FSM State: RUN_TEST
`define LED_IDX_SENDING   2          // FSM State: SEND_REPORT
`define LED_IDX_ERROR     3          // FSM State: ERROR_STATE

// Optional: Reserved LEDs for future ILA triggers (LED[7:4])
`define LED_RESERVED_WIDTH 4

// -----------------------------------------------------------------------------
// 3. Main Scan FSM State Encodings
// -----------------------------------------------------------------------------
// These states directly drive the LED outputs defined above.
// Using One-Hot encoding for easier debugging and faster decoding.

`define FSM_STATE_IDLE      4'b0001
`define FSM_STATE_WAIT_START 4'b0010  // Maps to LED[0] (CFG_OK)
`define FSM_STATE_RUN_TEST   4'b0100  // Maps to LED[1] (RUNNING)
`define FSM_STATE_SEND_REPORT 4'b1000  // Maps to LED[2] (SENDING)
`define FSM_STATE_ERROR      4'b10000 // Maps to LED[3] (ERROR) - Requires 5 bits if one-hot, or use binary

// Alternative: Binary Encoding (if FSM uses binary counter for states)
// If using binary, the LED logic inside FSM will be:
// assign led_cfg_ok   = (state == 2'd0); 
// assign led_running  = (state == 2'd1);
// etc.
// For this design, we assume the FSM outputs explicit LED flags rather than raw state codes.

// -----------------------------------------------------------------------------
// 4. Control Register Bank Address Map
// -----------------------------------------------------------------------------
// Addresses for the Register Bank accessed via UART Protocol Parser.

`define REG_ADDR_CTRL     8'h00  // Control Register (Start, Algo, Burst Len)
`define REG_ADDR_SEED     8'h04  // Seed Register (Read-only: Current Locked Seed)
`define REG_ADDR_STATUS   8'h08  // Status Register (Busy, Done, Error Count MSB)
`define REG_ADDR_ERR_CNT  8'h0C  // Error Count Register (Full 32-bit)
`define REG_ADDR_MEM_BASE 8'h10  // Base address for Memory Window Readback

// Control Register Bit Definitions
`define CTRL_BIT_START    0      // Write 1 to trigger test start
`define CTRL_MSK_ALGO     2'h3   // Bits [5:4] for Algorithm ID
`define CTRL_SFT_ALGO     4
`define CTRL_MSK_BURST    4'hF   // Bits [9:6] for Burst Length
`define CTRL_SFT_BURST    6

// Status Register Bit Definitions
`define STAT_BIT_BUSY     0
`define STAT_BIT_DONE     1
`define STAT_BIT_ERROR    2

// -----------------------------------------------------------------------------
// 5. Data Bus Widths
// -----------------------------------------------------------------------------
`define DATA_BUS_WIDTH    32
`define ADDR_BUS_WIDTH    8
`define SEED_BUS_WIDTH    32

// -----------------------------------------------------------------------------
// 6. Protocol Parser Constants
// -----------------------------------------------------------------------------
`define UART_PKT_HEADER   8'hA5
`define UART_PKT_TAIL     8'h5A
`define CMD_WRITE         8'h01
`define CMD_READ          8'h02
`define CMD_START_TEST    8'h03

`endif // TOP_FAULT_TOLERANCE_TEST_VH