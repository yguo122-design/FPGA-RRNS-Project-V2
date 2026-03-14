// =============================================================================
// File: prbs_generator.vh
// Description: Interface and Parameter Definitions for PRBS Generator Module
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Corresponds to Section 2.3.2 of Top-Level Design Document
// Version: v1.2
// =============================================================================

`ifndef PRBS_GENERATOR_VH
`define PRBS_GENERATOR_VH

// -----------------------------------------------------------------------------
// 1. LFSR Parameters
// -----------------------------------------------------------------------------
// 32-bit Galois LFSR with polynomial: x^32 + x^22 + x^2 + x^1 + 1
// Taps (0-indexed): [31, 21, 1, 0]
// Maximal-length sequence: 2^32 - 1 states
`define PRBS_LFSR_WIDTH  32

// Safe non-zero seed to prevent LFSR lock-up if seed is zero
`define PRBS_SAFE_SEED   32'hDEADBEEF

// -----------------------------------------------------------------------------
// 2. Output Data Width Definition
// -----------------------------------------------------------------------------
// Each clock cycle produces one 32-bit output word containing TWO 16-bit test symbols:
//   prbs_out[31:16] = Symbol_A  (first  16-bit test data, range 0~65535)
//   prbs_out[15:0]  = Symbol_B  (second 16-bit test data, range 0~65535)
//
// Downstream usage:
//   - Symbol_A and Symbol_B are sent to the Encoder independently.
//   - The Decoder recovers two 16-bit values: Recovered_A and Recovered_B.
//   - The Comparator performs TWO checks per output word:
//       Recovered_A == Symbol_A ?
//       Recovered_B == Symbol_B ?
//   - Each 32-bit output word counts as 2 test trials (not 1).
`define PRBS_OUT_WIDTH   32
`define PRBS_SYM_WIDTH   16

// -----------------------------------------------------------------------------
// 3. Module Port Definition
// -----------------------------------------------------------------------------
// Usage:
// module prbs_generator (
//     `PRBS_GENERATOR_PORTS
// );

`define PRBS_GENERATOR_PORTS \
    /* Global Clock & Reset */ \
    input  wire        clk,                        \
    input  wire        rst_n,                      \
    \
    /* Seed Control */ \
    input  wire        load_seed,                  \
    /* load_seed: Single-cycle pulse to load seed_in into the LFSR. \
       When asserted, the LFSR is loaded with seed_in (with zero protection). \
       Takes priority over start_gen. */ \
    \
    input  wire [`PRBS_LFSR_WIDTH-1:0] seed_in,   \
    /* seed_in: The seed value to load (typically from seed_lock_unit). */ \
    \
    /* Generation Control */ \
    input  wire        start_gen,                  \
    /* start_gen: When HIGH, the LFSR advances each clock cycle and \
       prbs_out is updated. When LOW, the LFSR is frozen. */ \
    \
    /* Output */ \
    output reg  [`PRBS_OUT_WIDTH-1:0] prbs_out,   \
    /* prbs_out[31:16] = Symbol_A (first  16-bit test symbol) \
       prbs_out[15:0]  = Symbol_B (second 16-bit test symbol) */ \
    \
    output reg         prbs_valid                  \
    /* prbs_valid: HIGH for one cycle when prbs_out contains new valid data. \
       Asserted whenever start_gen=1 and LFSR advances. */

`endif // PRBS_GENERATOR_VH
