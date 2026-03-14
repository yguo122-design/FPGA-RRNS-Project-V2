// =============================================================================
// File: seed_lock_unit.vh
// Description: Interface and Parameter Definitions for Seed Lock Unit
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Corresponds to Section 2.3.2.1 of Top-Level Design (v1.61)
// Version: v1.0
// =============================================================================

`ifndef SEED_LOCK_UNIT_VH
`define SEED_LOCK_UNIT_VH

// -----------------------------------------------------------------------------
// 1. LFSR / Counter Parameters 
// -----------------------------------------------------------------------------
// The system uses a 32-bit free-running counter/LFSR as the entropy source.
// Width must match the internal free-running generator.
`define SEED_WIDTH 32

// Safe non-zero default seed to prevent lock-up if capture happens at 0
// Although the logic should handle zero, this provides a hardware safety net.
`define SEED_SAFE_DEFAULT 32'hDEADBEEF

// -----------------------------------------------------------------------------
// 2. Module Port Definition 
// -----------------------------------------------------------------------------
// Usage: 
// module seed_lock_unit (
//     `SEED_LOCK_UNIT_PORTS
// );

`define SEED_LOCK_UNIT_PORTS \
    /* Global Clock & Reset */ \
    input  wire        clk,                   \
    input  wire        rst_n,                 \
    \
    /* Control Inputs (From Main Scan FSM) */ \
    input  wire        lock_en,               \
    /* lock_en: High during the entire 91-point scan task (INIT -> DONE). \
       Enables the capturing mechanism. */ \
    \
    input  wire        capture_pulse,         \
    /* capture_pulse: Single cycle pulse when config is received (cfg_update_pulse). \
       Triggers the actual latching of the seed ONLY if lock_en is high. */ \
    \
    /* Entropy Source Input */ \
    input  wire [`SEED_WIDTH-1:0] free_cnt_val, \
    /* free_cnt_val: The current value of the internal free-running counter/LFSR. */ \
    \
    /* Output: Locked Seed for Downstream Modules */ \
    output reg  [`SEED_WIDTH-1:0] seed_locked, \
    /* seed_locked: Stable seed value used for the entire 91-point BER scan. */ \
    \
    output wire        seed_valid             \
    /* seed_valid: High when seed_locked contains a valid, non-zero seed. */

// -----------------------------------------------------------------------------
// 3. Implementation Notes 
// -----------------------------------------------------------------------------
// 1. Zero-Seed Handling: If free_cnt_val is 0 at the moment of capture, 
//    force seed_locked to SEED_SAFE_DEFAULT to prevent LFSR lock-up.
// 2. Task-Level Logic: 
//    - When lock_en=0, seed_locked holds its previous value (or resets).
//    - When lock_en=1 AND capture_pulse=1, latch free_cnt_val.
//    - When lock_en=1 AND capture_pulse=0, hold seed_locked stable.
// 3. Async Reset: Clear seed_locked and seed_valid on rst_n.

`endif // SEED_LOCK_UNIT_VH