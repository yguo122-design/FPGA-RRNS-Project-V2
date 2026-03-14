`timescale 1ns / 1ps

module encoder_2nrm (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [15:0] data_in,
    output reg [63:0] residues_out,
    output reg        done
);

    // --- 1. Function to calculate modulo using subtraction (No '%' operator) ---
    // This forces the simulator to execute logic step-by-step, avoiding optimizer bugs
    function [31:0] safe_mod;
        input [31:0] val;
        input [31:0] mod;
        reg [31:0] temp;
        begin
            temp = val;
            // For small moduli and 16-bit input, this loop is very fast in simulation
            while (temp >= mod) begin
                temp = temp - mod;
            end
            safe_mod = temp;
        end
    endfunction

    // --- 2. Intermediate Wires ---
    wire [31:0] r1, r2, r3, r4, r5, r6;

    // --- 3. Calculate Residues using the safe function ---
    assign r1 = safe_mod(data_in, 32'd257);
    assign r2 = safe_mod(data_in, 32'd256);
    assign r3 = safe_mod(data_in, 32'd61);
    assign r4 = safe_mod(data_in, 32'd59);
    assign r5 = safe_mod(data_in, 32'd55);
    assign r6 = safe_mod(data_in, 32'd53);

    // --- 4. Packing Logic ---
    wire [63:0] packed_data;
    assign packed_data = {
        9'd0,
        r1[8:0],
        r2[7:0],
        r3[5:0],
        r4[5:0],
        r5[5:0],
        r6[5:0],
        14'd0
    };

    // --- 5. Sequential Output ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            residues_out <= 64'd0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                residues_out <= packed_data;
                done <= 1'b1;
            end
        end
    end

endmodule