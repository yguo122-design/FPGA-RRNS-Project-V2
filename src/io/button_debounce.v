// button_debounce.v
// FPGA Multi-Algorithm Fault Tolerance Test System
// Design Ref: v1.63 Section 2.2
// Target: Artix-7 100T

module button_debounce #(
    parameter COUNT_MAX = 1600000  // 16ms @ 100MHz
) (
    input  wire clk_100m,    // 100MHz system clock
    input  wire sys_rst_n,   // Synchronized system reset (active low)
    input  wire btn_in,      // Raw button input
    output reg  btn_out      // Debounced button output
);
    // Internal signals
    reg [20:0] count;        // Counter for debounce period (21 bits for up to 2M cycles)
    (* ASYNC_REG = "TRUE" *) // Xilinx specific attribute for input sync
    reg btn_in_ff1;          // First stage synchronizer
    reg btn_in_ff2;          // Second stage synchronizer
    
    // Two-stage input synchronizer to prevent metastability
    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            btn_in_ff1 <= 1'b1;  // Initialize to released state
            btn_in_ff2 <= 1'b1;  // Initialize to released state
        end else begin
            btn_in_ff1 <= btn_in;
            btn_in_ff2 <= btn_in_ff1;
        end
    end
    
    // Debounce counter logic (Active-Low Detection)
    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            count <= 21'd0;
            btn_out <= 1'b1; // Reset to released state (high), break potential deadlock
        end else begin
            if (btn_in_ff2 == 1'b0) begin 
                // Low level detected (button pressed)
                if (count < COUNT_MAX) begin
                    count <= count + 21'd1;
                end else begin
                    count <= COUNT_MAX; // Hold at max
                end
                
                // Only assert button press after stable low for debounce period
                if (count >= COUNT_MAX - 1) begin
                    btn_out <= 1'b0;
                end
            end else begin 
                // High level detected (button released)
                count <= 21'd0;       // Reset counter immediately
                btn_out <= 1'b1;      // Release immediately
            end
        end
    end

endmodule