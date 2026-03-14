// uart_rx_module.v
// FPGA Multi-Algorithm Fault Tolerance Test System
// Design Ref: v1.63 Section 2.3.1
// Baud Rate: 921,600 (Divider=109, 100MHz Clock)
// Features: 16x Oversampling, Frame Error Detection

module uart_rx_module (
    input  wire        clk_100m,     // 100MHz system clock
    input  wire        sys_rst_n,    // Synchronized system reset
    output reg         rx_valid,     // Pulse when byte received
    output reg  [7:0]  rx_data,      // Received byte
    output reg         rx_error,     // Framing error detected
    input  wire        uart_rx_pin   // From FPGA IO
);

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam BAUD_DIV   = 7'd109;    // 100MHz / 921,600 baud = 109
    localparam SAMPLE_DIV = 4'd7;       // 16x oversampling (109/16 ≈ 7)
    localparam TOTAL_BITS = 4'd10;      // Start(1) + Data(8) + Stop(1)
    
    // =========================================================================
    // State Machine
    // =========================================================================
    localparam [2:0] 
        IDLE    = 3'b000,
        START   = 3'b001,
        DATA    = 3'b010,
        STOP    = 3'b011,
        CLEANUP = 3'b100;
    
    // =========================================================================
    // Internal Signals
    // =========================================================================
    reg  [2:0]  state;
    reg  [7:0]  shift_reg;      // Data shift register
    reg  [3:0]  sample_count;   // 16x oversampling counter
    reg  [3:0]  bit_count;      // Bit counter (0-7 for data)
    reg  [6:0]  div_count;      // Baud rate divider
    
    (* ASYNC_REG = "TRUE" *)    // Xilinx specific for input sync
    reg         rx_sync1;       // First stage synchronizer
    reg         rx_sync2;       // Second stage synchronizer
    reg         rx_filtered;    // Majority voted sample
    
    reg  [2:0]  sample_window;  // 3-bit sliding window for majority vote
    wire        sample_point;   // Indicates when to sample input
    wire        sample_pulse;   // 16x oversampling pulse
    
    // Generate sample pulse for 16x oversampling
    assign sample_pulse = (div_count == 7'd0);
    
    // Generate sample point (middle of bit)
    assign sample_point = (sample_count == 4'd7);  // Sample at middle (16/2 - 1)
    
    // Input synchronization and filtering
    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
            sample_window <= 3'b111;
            rx_filtered <= 1'b1;
        end else begin
            // Two-stage synchronizer
            rx_sync1 <= uart_rx_pin;
            rx_sync2 <= rx_sync1;
            
            // Majority voting over 3 samples
            if (sample_pulse) begin
                sample_window <= {sample_window[1:0], rx_sync2};
                rx_filtered <= (sample_window[2] + sample_window[1] + rx_sync2 >= 2'd2);
            end
        end
    end
    
    // Baud rate divider
    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            div_count <= 7'd0;
        end else begin
            if (div_count == BAUD_DIV - 1) begin
                div_count <= 7'd0;
            end else begin
                div_count <= div_count + 7'd1;
            end
        end
    end
    
    // Main state machine
    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state <= IDLE;
            rx_valid <= 1'b0;
            rx_error <= 1'b0;
            rx_data <= 8'h00;
            shift_reg <= 8'h00;
            sample_count <= 4'd0;
            bit_count <= 4'd0;
        end else begin
            // Default state for rx_valid (single cycle pulse)
            rx_valid <= 1'b0;
            
            if (sample_pulse) begin
                case (state)
                    IDLE: begin
                        rx_error <= 1'b0;
                        if (!rx_filtered) begin  // Start bit detected
                            state <= START;
                            sample_count <= 4'd0;
                        end
                    end
                    
                    START: begin
                        if (sample_count == 4'd15) begin
                            state <= DATA;
                            sample_count <= 4'd0;
                            bit_count <= 4'd0;
                        end else begin
                            sample_count <= sample_count + 4'd1;
                        end
                    end
                    
                    DATA: begin
                        if (sample_point) begin
                            shift_reg <= {rx_filtered, shift_reg[7:1]};  // LSB first
                        end
                        
                        if (sample_count == 4'd15) begin
                            sample_count <= 4'd0;
                            if (bit_count == 4'd7) begin
                                state <= STOP;
                            end else begin
                                bit_count <= bit_count + 4'd1;
                            end
                        end else begin
                            sample_count <= sample_count + 4'd1;
                        end
                    end
                    
                    STOP: begin
                        if (sample_point) begin
                            if (!rx_filtered) begin  // Stop bit should be 1
                                rx_error <= 1'b1;
                            end else begin
                                rx_data <= shift_reg;
                                rx_valid <= 1'b1;
                            end
                        end
                        
                        if (sample_count == 4'd15) begin
                            state <= CLEANUP;
                            sample_count <= 4'd0;
                        end else begin
                            sample_count <= sample_count + 4'd1;
                        end
                    end
                    
                    CLEANUP: begin
                        state <= IDLE;  // One extra cycle for cleanup
                    end
                    
                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule