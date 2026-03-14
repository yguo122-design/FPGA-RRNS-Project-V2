// =============================================================================
// File: ctrl_register_bank.vh
// Description: Interface and Parameter Definitions for Control Register Bank
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Corresponds to Section 2.2.4 of Top-Level Design
// Version: v1.0
// =============================================================================

`ifndef CTRL_REGISTER_BANK_VH
`define CTRL_REGISTER_BANK_VH

// -----------------------------------------------------------------------------
// 1. Module Port Definition 
// -----------------------------------------------------------------------------
// Usage: 
// module ctrl_register_bank (
//     `CTRL_REGISTER_BANK_PORTS
// );

`define CTRL_REGISTER_BANK_PORTS \
    /* Global Clock & Reset */ \
    input  wire        clk,                   \
    input  wire        rst_n,                 \
    \
    /* Configuration Input Interface (from protocol_parser) */ \
    input  wire        cfg_update_pulse,      \
    input  wire [7:0]  cfg_algo_id_in,        \
    input  wire [7:0]  cfg_burst_len_in,      \
    input  wire [7:0]  cfg_error_mode_in,     \
    input  wire [31:0] cfg_sample_count_in,   \
    \
    /* Runtime Status Inputs */ \
    input  wire        test_done_flag,        \
    input  wire        tx_busy,               \
    \
    /* Control Outputs (To Top Level / State Machine) */ \
    output reg         test_active,           \
    output reg         config_locked,         \
    \
    /* Registered Configuration Outputs (To Algorithm Modules) */ \
    output reg  [7:0]  reg_algo_id,           \
    output reg  [7:0]  reg_burst_len,         \
    output reg  [7:0]  reg_error_mode,        \
    output reg  [31:0] reg_sample_count

// -----------------------------------------------------------------------------
// 2. Internal State Definition 
// -----------------------------------------------------------------------------
// Although this module is primarily a register set, a simple internal state enum can be defined for debugging purposes.  
// If a more complex state machine is needed, it can be extended here, but currently, it mainly relies on the test_active flag.

`define DEFINE_CTRL_STATES \
typedef enum logic [1:0] { \
    CTRL_IDLE       = 2'd0, \
    CTRL_LOCKED     = 2'd1, \
    CTRL_RUNNING    = 2'd2, \
    CTRL_PROTECTED  = 2'd3  \
} ctrl_state_t;

// -----------------------------------------------------------------------------
// 3. Timing & Safety Constants
// -----------------------------------------------------------------------------
// No special constants, logic mainly relies on input pulses and flags


`endif // CTRL_REGISTER_BANK_VH