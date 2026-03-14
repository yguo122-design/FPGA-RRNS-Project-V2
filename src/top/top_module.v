// top_module.v
// FPGA Multi-Algorithm Fault Tolerance Test System
// Design Ref: v1.63 Section 2.2
// Target: Artix-7 100T

// Interface definitions
// `include "../interfaces/top_ports.vh"
// `include "../interfaces/decoder_wrapper_ports.vh"
// `include "../interfaces/uart_interface.vh"

// Note: reset_sync.v and button_debounce.v should be added as separate source files
// in Vivado project, not included here

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
    input  wire [3:0]  btn,           // [0]:Global Reset, [1]:Single-Shot Decode
    output wire [3:0]  gpio           // Direct connection to LED for debug
);

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam DEBOUNCE_COUNT = 32'd1600000;  // 16ms @ 100MHz
    localparam WATCHDOG_COUNT = 32'd1000000;  // 10ms @ 100MHz
    
    // =========================================================================
    // Internal Signals
    // =========================================================================
    wire        sys_rst_n;          // Synchronized system reset
    wire        btn0_debounced;     // Debounced global reset button
    wire        btn1_debounced;     // Debounced decoder trigger
    reg  [15:0] valid_mask;         // Algorithm enable mask
    
    // UART signals
    reg         tx_en;              // TX enable control
    reg  [7:0]  tx_data;           // TX data to send
    wire        tx_busy;            // TX module busy flag
    wire        rx_valid;           // RX data valid flag
    wire [7:0]  rx_data;           // RX received data
    wire        rx_error;           // RX error indicator
    
    // Decoder signals
    wire        decoder_start;      // Start decoding trigger
    wire        decoder_busy;       // Decoder busy status
    wire        decoder_done;       // Decode completion flag
    wire        decode_success;     // Decode success indicator
    reg  [63:0] data_in;           // Input data for decoder
    reg  [63:0] error_pattern;     // Error injection pattern
    wire [63:0] data_out;          // Decoded output data
    
    // Unused signals handling
    wire [1:0]  unused_btn;        // Explicitly mark unused buttons
    assign unused_btn = btn[3:2];  // Buttons 2 and 3 are unused
    
    // =========================================================================
    // Reset Synchronizer
    // =========================================================================
    // Generate button reset signal (active low when button is pressed)
    wire btn_rst_n;
    assign btn_rst_n = btn0_debounced;  // btn0_debounced is already active-low (1=released, 0=pressed)
    
    // Synchronize combined reset (external AND button)
    reset_sync u_reset_sync (
        .clk_100m    (clk_100m),
        .rst_n_i     (rst_n_i & btn_rst_n),  // Combine resets before sync
        .sys_rst_n   (sys_rst_n)             // Final synchronized system reset
    );
    
    // =========================================================================
    // Button Debouncer
    // =========================================================================
    button_debounce #(
        .COUNT_MAX   (DEBOUNCE_COUNT)
    ) u_btn0_debounce (
        .clk_100m    (clk_100m),
        .sys_rst_n   (rst_n_i),     // Fix: Use external reset to avoid circular dependency
        .btn_in      (btn[0]),
        .btn_out     (btn0_debounced)
    );
    
    button_debounce #(
        .COUNT_MAX   (DEBOUNCE_COUNT)
    ) u_btn1_debounce (
        .clk_100m    (clk_100m),
        .sys_rst_n   (sys_rst_n),
        .btn_in      (btn[1]),
        .btn_out     (btn1_debounced)
    );
    
    // =========================================================================
    // UART Modules
    // =========================================================================
    uart_tx_module u_uart_tx (
        .clk_100m    (clk_100m),
        .sys_rst_n   (sys_rst_n),
        .tx_en       (tx_en),
        .tx_data     (tx_data),
        .tx_busy     (tx_busy),
        .uart_tx_pin (uart_tx_pin)
    );
    
    uart_rx_module u_uart_rx (
        .clk_100m    (clk_100m),
        .sys_rst_n   (sys_rst_n),
        .rx_valid    (rx_valid),
        .rx_data     (rx_data),
        .rx_error    (rx_error),
        .uart_rx_pin (uart_rx_pin)
    );
    
    // =========================================================================
    // Decoder Wrapper
    // =========================================================================
    decoder_wrapper u_decoder (
        .clk_100m      (clk_100m),
        .sys_rst_n     (sys_rst_n),
        .start_pulse   (btn1_debounced),  // Trigger from button 1
        .busy          (decoder_busy),
        .done_pulse    (decoder_done),
        .decode_success(decode_success),
        .data_in       (data_in),
        .error_pattern (error_pattern),
        .data_out      (data_out),
        .algo_id       (3'b000),          // Default to first algorithm
        .valid_mask    (valid_mask)
    );
    
    // =========================================================================
    // Valid Mask Reset Logic
    // =========================================================================
    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            valid_mask <= 16'hFFFF;  // All algorithms enabled on reset
            data_in <= 64'd0;        // Clear decoder input
            error_pattern <= 64'd0;  // No error injection by default
            tx_en <= 1'b0;           // Disable TX
            tx_data <= 8'd0;         // Clear TX data
        end else begin
            // Connect UART RX to decoder input when data is valid
            if (rx_valid) begin
                data_in <= {data_in[55:0], rx_data};  // Shift in new byte
            end
            
            // Handle decoder completion
            if (decoder_done) begin
                tx_en <= 1'b1;                        // Enable TX
                tx_data <= data_out[7:0];             // Send first byte
            end else if (tx_busy) begin
                tx_en <= 1'b0;                        // Clear TX enable after busy
            end
        end
    end
    
    // =========================================================================
    // Debug Output Connections
    // =========================================================================
    assign gpio = led;  // Direct connection as specified
    

    // Connect decoder control signals
    assign decoder_start = rx_valid;  // Start decoding on UART receive
    
    // LED status mapping
    assign led[0] = ~sys_rst_n;      // Config OK (active when not in reset)
    assign led[1] = decoder_busy;     // Running
    assign led[2] = decode_success;   // Last decode was successful
    assign led[3] = rx_error;         // UART receive error
endmodule
