// src/interfaces/uart_interface.vh
// Design Ref: v1.63 Section 2.3.1
// Constraints: Baud=921600, Divider=109, 100MHz Clock

`ifndef UART_INTERFACE_VH
`define UART_INTERFACE_VH

/*
// UART TX Module Ports
module uart_tx_module (
    input  wire        clk_100m,
    input  wire        sys_rst_n,      // Synchronous release reset
    input  wire        tx_en,          // Pulse to send one byte
    input  wire [7:0]  tx_data,        // Byte to send
    output wire        tx_busy,        // High when shifting
    output wire        uart_tx_pin     // To FPGA IO
);
// Implementation details hidden. 
// Note: Internal divider is fixed to 109.
endmodule

// UART RX Module Ports
module uart_rx_module (
    input  wire        clk_100m,
    input  wire        sys_rst_n,
    output wire        rx_valid,       // Pulse when byte received
    output wire [7:0]  rx_data,        // Received byte
    output wire        rx_error,       // Framing/Parity error
    input  wire        uart_rx_pin     // From FPGA IO
);
// Note: 16x oversampling logic included.
endmodule

*/

`endif