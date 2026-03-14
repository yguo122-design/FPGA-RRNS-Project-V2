// 0303: fix a bug, the original version doesn't calculate the M9
`timescale 1ns / 1ps

module encoder_3nrm (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,          
    input  wire [15:0] data_in,       
    
    // 保持 64-bit 接口，方便与现有系统对接
    // 有效数据 48 位，低 16 位保留/补零
    // [63:48] : Valid 48-bit Codeword
    // [47:32] : (Part of Valid if mapped differently, see logic below)
    // Let's map strictly:
    // [63:16] : 48 Bits Valid Data (Compact)
    // [15:0]  : Unused (0)
    output reg [63:0] residues_out,   
    
    output reg        done            
);

    // --- 1. 模数定义 ---
    localparam M1 = 7'd64;
    localparam M2 = 7'd63;
    localparam M3 = 7'd65; // ... 所有模数参数都改为 7 位或更大，以容纳模数本身
    localparam M4 = 7'd31;
    localparam M5 = 7'd29;
    localparam M6 = 7'd23;
    localparam M7 = 7'd19;
    localparam M8 = 7'd17;
    localparam M9 = 7'd11;  // [关键修复] 新增模数 11

    // --- 2. 余数计算 ---
    wire [5:0] r1 = data_in % M1;
    wire [5:0] r2 = data_in % M2;
    wire [6:0] r3 = data_in % M3;
    wire [4:0] r4 = data_in % M4;
    wire [4:0] r5 = data_in % M5;
    wire [4:0] r6 = data_in % M6;
    wire [4:0] r7 = data_in % M7;
    wire [4:0] r8 = data_in % M8;
    wire [3:0] r9 = data_in % M9; // [关键修复] 新增 4-bit 余数

    // --- 3. 打包逻辑 (48 位有效数据) ---
    // 策略：将 48 位数据放在高 48 位 [63:16]，低 16 位补 0
    // 这样既满足了 48 位算法需求，又保持了 64 位接口整洁
    wire [47:0] valid_codeword;
    assign valid_codeword = {
        r1, r2, r3,       // 19 bits (NR)
        r4, r5, r6, r7, r8, r9 // 29 bits (RRNS, 包含 r9)
    }; // 总计 48 位

    // --- 4. 寄存器输出 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            residues_out <= 64'd0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                // 将 48 位有效数据左移 16 位，放入 [63:16]
                residues_out <= { valid_codeword, 16'd0 };
                done <= 1'b1;
            end
        end
    end

endmodule