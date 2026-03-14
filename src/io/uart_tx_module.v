// uart_tx_module.v
// FPGA Multi-Algorithm Fault Tolerance Test System
// Design Ref: v1.63 Section 2.3.1
// Baud Rate: 921,600 (Divider=109, 100MHz Clock)

module uart_tx_module (
    input  wire        clk_100m,     // 100MHz system clock
    input  wire        sys_rst_n,    // Synchronized system reset
    input  wire        tx_en,        // Pulse to send one byte
    input  wire [7:0]  tx_data,      // Byte to send
    output wire        tx_busy,      // High when shifting
    output reg         uart_tx_pin   // To FPGA IO
);

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam BAUD_DIV   = 7'd109;  // 100MHz / 921,600 baud = 109 (rounded)
    localparam TOTAL_BITS = 4'd10;   // Start(1) + Data(8) + Stop(1)
    
    // =========================================================================
    // State Machine
    // =========================================================================
    localparam [1:0] 
        IDLE  = 2'b00,
        START = 2'b01,
        SHIFT = 2'b10,
        STOP  = 2'b11;
    
    reg [1:0]  state;
    reg [7:0]  shift_reg;    // Data shift register
    reg [6:0]  div_count;    // Baud rate divider counter
    reg [3:0]  bit_count;    // Bit counter (0-9)
    
    // State and busy flag
    assign tx_busy = (state != IDLE);
    
    // Main state machine
    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state <= IDLE;
            shift_reg <= 8'h00;
            div_count <= 7'd0;
            bit_count <= 4'd0;
            uart_tx_pin <= 1'b1;  // Idle high
        end else begin
            case (state)
                IDLE: begin
                    uart_tx_pin <= 1'b1;  // Keep line high
                    div_count <= 7'd0;
                    if (tx_en) begin
                        state <= START;
                        shift_reg <= tx_data;
                    end
                end
                
                START: begin
                    uart_tx_pin <= 1'b0;  // Start bit
                    if (div_count == BAUD_DIV - 1) begin
                        state <= SHIFT;
                        div_count <= 7'd0;
                        bit_count <= 4'd0;
                    end else begin
                        div_count <= div_count + 7'd1;
                    end
                end
                
                SHIFT: begin
                    uart_tx_pin <= shift_reg[0];  // LSB first
                    if (div_count == BAUD_DIV - 1) begin
                        div_count <= 7'd0;
                        if (bit_count == 4'd7) begin
                            state <= STOP;
                        end else begin
                            bit_count <= bit_count + 4'd1;
                            shift_reg <= {1'b0, shift_reg[7:1]};  // Right shift
                        end
                    end else begin
                        div_count <= div_count + 7'd1;
                    end
                end
                
                STOP: begin
                    uart_tx_pin <= 1'b1;  // Stop bit
                    if (div_count == BAUD_DIV - 1) begin
                        state <= IDLE;
                        div_count <= 7'd0;
                    end else begin
                        div_count <= div_count + 7'd1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule