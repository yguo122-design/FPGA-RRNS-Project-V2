// src/interfaces/decoder_wrapper_ports.vh
// Design Ref: v1.63 Section 2.4.3
// Strategy: Single-Algorithm-Build via `define

`ifndef DECODER_WRAPPER_PORTS_VH
`define DECODER_WRAPPER_PORTS_VH

/*
module decoder_wrapper (
    input  wire        clk_100m,
    input  wire        sys_rst_n,
    
    // Control
    input  wire        start_pulse,    // Start decoding one codeword
    output wire        busy,           // High during decoding
    output wire        done_pulse,     // High when finished
    output wire        decode_success, // 1: Success, 0: Fail
    
    // Data Path (64-bit RRNS/RS bus)
    input  wire [63:0] data_in,        // Received codeword
    input  wire [63:0] error_pattern,  // From ROM Injector
    output wire [63:0] data_out,       // Corrected codeword
    
    // Algorithm Specific (Unused ports tied to 0 in wrapper)
    input  wire [2:0]  algo_id,        // Selects internal core if multi-core
    input  wire [15:0] valid_mask      // For RS or specific NRM variants
);
// Internal: Instantiates ONLY one algorithm based on `ALGO_TYPE macro.
// Includes Watchdog logic internally.
endmodule
*/

`endif