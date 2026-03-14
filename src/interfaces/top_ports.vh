// src/interfaces/top_ports.vh
// Design Ref: v1.63 Section 2.2
// Target: Artix-7 100T

`ifndef TOP_PORTS_VH
`define TOP_PORTS_VH

/*
module top_top (
    // Clock & Reset
    input  wire        clk_100m,       // 100 MHz system clock
    input  wire        rst_n_i,        // Active Low, Asynchronous Input
    
    // UART Interface (Physical)
    input  wire        uart_rx_pin,
    output wire        uart_tx_pin,
    
    // Debug / Status
    output wire [3:0]  led,            // [0]:ConfigOK, [1]:Running, [2]:Sending, [3]:Error
    
    // Reserved for JTAG/Expansion
    input  wire [3:0]  btn,           // Optional
    output wire [3:0]  gpio           // Optional
);
// Internal logic instantiates reset_sync, fsm, uart, mem, decoder_wrapper.
endmodule
*/

`endif