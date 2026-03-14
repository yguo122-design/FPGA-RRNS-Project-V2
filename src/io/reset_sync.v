// reset_sync.v
// FPGA Multi-Algorithm Fault Tolerance Test System
// Design Ref: v1.63 Section 2.2
// Target: Artix-7 100T

module reset_sync (
    input  wire clk_100m,    // 100MHz system clock
    input  wire rst_n_i,     // Asynchronous reset input (active low)
    output reg  sys_rst_n    // Synchronized reset output (active low)
);
    // Metastability protection stage
    (* ASYNC_REG = "TRUE" *)  // Xilinx specific attribute for reset sync
    reg rst_n_meta;
    
    // Two-stage synchronizer implementation
    always @(posedge clk_100m or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rst_n_meta <= 1'b0;
            sys_rst_n  <= 1'b0;
        end else begin
            rst_n_meta <= 1'b1;
            sys_rst_n  <= rst_n_meta;
        end
    end

endmodule