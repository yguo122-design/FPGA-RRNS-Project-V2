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
    output wire        rx_valid,       // Single-cycle pulse when byte received
    output wire [7:0]  rx_data,        // Received byte (valid when rx_valid=1)
    output wire        rx_error,       // Framing error: stop bit was not HIGH
    input  wire        uart_rx_pin     // From FPGA IO
);
// Note: 1x center-sampling implementation (v1.1, rewritten 2026-03-16).
//       BAUD_DIV=109 @ 100MHz, HALF_BIT=54 for start-bit center alignment.
//       On start-bit falling edge: wait HALF_BIT cycles → sample center of
//       start bit → then sample every BAUD_DIV cycles for D0~D7 and STOP.
//       Two-stage FF synchronizer on uart_rx_pin prevents metastability.
//       (16x oversampling was removed in v1.1: the original sample_pulse was
//        generated every BAUD_DIV cycles instead of every BAUD_DIV/16 cycles,
//        making it a 1x signal that caused complete receive failure at 921600bps.)
endmodule

*/

`endif