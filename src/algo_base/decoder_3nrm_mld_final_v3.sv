`timescale 1ns / 1ps

module decoder_3nrm_mld_final_v3 (
    input wire clk,
    input wire rst_n,          
    input wire start,           
    input wire [63:0] residues_in, 
    
    output reg [15:0] data_out,   
    output reg valid,
    output reg uncorrectable      
);

    // ------------------------------------------------------------------
    // 1. 参数与余数提取
    // ------------------------------------------------------------------
    wire [6:0] r [0:8];
    assign r[0] = {1'b0, residues_in[63:58]}; 
    assign r[1] = {1'b0, residues_in[57:52]}; 
    assign r[2] =        residues_in[51:45];  
    assign r[3] = {2'b0, residues_in[44:40]}; 
    assign r[4] = {2'b0, residues_in[39:35]}; 
    assign r[5] = {2'b0, residues_in[34:30]}; 
    assign r[6] = {2'b0, residues_in[29:25]}; 
    assign r[7] = {2'b0, residues_in[24:20]}; 
    assign r[8] = {3'b0, residues_in[19:16]}; 

    // 模数常量 (供 MRC 使用)
    localparam logic [6:0] MODS [0:8] = '{7'd64, 7'd63, 7'd65, 7'd31, 7'd29, 7'd23, 7'd19, 7'd17, 7'd11};

    // ------------------------------------------------------------------
    // 2. 状态机定义 (两段式 FSM)
    // ------------------------------------------------------------------
    typedef enum logic [3:0] {
        ST_IDLE,      
        ST_LOAD,      
        ST_MRC,       
        ST_DIST_INIT, 
        ST_DIST_MOD,  // 计算 mod
        ST_DIST_LATCH,// 【新增】锁存 mod 结果 (关键！)
        ST_DIST_CMP,  // 比较并累加
        ST_UPDATE,    
        ST_NEXT,      
        ST_DONE       
    } state_t;

    state_t state, next_state;

    // 控制信号
    reg [6:0] combo_idx;      // 0-83
    reg [2:0] i_idx, j_idx, k_idx; 
    reg [4:0] dist_idx;       // 0-8
    
    // 数据寄存器
    reg [17:0] current_x_reg; 
    reg [6:0]  current_mod_res; // 【优化】寄存 mod 结果
    reg [3:0]  current_dist_acc; 
    reg [3:0]  min_dist_reg;   
    reg [17:0] best_val_reg;  
    
    wire [17:0] mrc_result;
    wire [6:0]  mod_result_wire;

    // ------------------------------------------------------------------
    // 3. 组合索引生成器 (纯组合逻辑，无循环，无 return)
    // ------------------------------------------------------------------
    // 根据 combo_idx (0-83) 计算 i, j, k
    // 逻辑：模拟三重循环的计数器行为
    always @(*) begin
        integer count, x, y, z;
        // 初始化
        x = 0; y = 1; z = 2;
        count = 0;
        
        // 这是一个纯组合的逻辑映射，综合器会将其优化为查找表或简单逻辑
        // 为了避免 large loop，我们手动展开逻辑或使用更聪明的算法
        // 这里使用一种确定性的数学映射方法 (或者简单的 if-else 链，因为 84 种情况不多)
        // 为了代码简洁且可综合，我们使用一个小的查找逻辑
        
        // 实际上，最安全的方法是直接用 if-else 或者 case 列举，但 84 行太长。
        // 我们可以复用之前的“计数器逻辑”但在组合块中用 while 循环 (某些工具支持) 
        // 或者最稳妥的：用三个临时变量模拟计数过程
        
        // 这里采用最稳健的“逆向推导”或“查表法”的简化版：
        // 由于 84 很小，我们用一个简化的迭代逻辑，综合器通常能处理好这种固定次数的组合迭代
        // 如果综合报错，请替换为 ROM 查找表
        
        // 【修正方案】：使用确定性逻辑生成 i,j,k
        // 这种方法不依赖循环，而是直接计算
        // 但为了代码可读性和避免复杂的数学公式，我们保留之前的逻辑结构
        // 但移除 return，改用标志位
        
        i_idx = 0; j_idx = 1; k_idx = 2; // Default
        
        // 注意：在组合逻辑中使用 for 循环是允许的，只要循环次数固定且不大。
        // 这里的 return 是非法的，我们改用 break 或标志位
        for(x=0; x<7; x=x+1) begin
            for(y=x+1; y<8; y=y+1) begin
                for(z=y+1; z<9; z=z+1) begin
                    if (count == combo_idx) begin
                        i_idx = x; 
                        j_idx = y; 
                        k_idx = z;
                        // 找到后不再继续，但 Verilog 组合逻辑无法直接 break 外层循环
                        // 我们可以通过给 count 赋一个大值来强制退出，或者依赖综合器优化
                        // 最安全的做法：不依赖 break，让逻辑跑完，因为只有一次匹配
                        // 为了防止后续覆盖，我们需要一个 found 标志
                    end
                    count = count + 1;
                end
            end
        end
        // 上面的逻辑有个问题：如果找到了，后面的循环还会执行吗？
        // 在组合逻辑 always @(*) 中，最后的赋值会生效。
        // 所以如果后面还有 count == combo_idx (不可能，因为 count 递增)，才会覆盖。
        // 所以这个逻辑是安全的！因为 count 是严格递增的，只有唯一一次匹配。
        // 唯一的隐患是综合器是否会展开成巨大电路。对于 84 次迭代，现代综合器完全没问题。
    end

    // ------------------------------------------------------------------
    // 4. 单通道 MRC 计算单元 (已去除 % 运算)
    // ------------------------------------------------------------------
    wire [6:0] m1 = MODS[i_idx];
    wire [6:0] m2 = MODS[j_idx];
    wire [6:0] m3 = MODS[k_idx];
    wire [6:0] r1 = r[i_idx];
    wire [6:0] r2 = r[j_idx];
    wire [6:0] r3 = r[k_idx];
    
    mrc_unit_optimized u_mrc_single (
        .r1(r1), .m1(m1),
        .r2(r2), .m2(m2),
        .r3(r3), .m3(m3),
        .x_out(mrc_result)
    );

    // ------------------------------------------------------------------
    // 5. 优化的模运算单元 (Mod Unit - 无除法)
    // ------------------------------------------------------------------
    mod_unit u_mod_calc (
        .x({14'd0, current_x_reg}), 
        .mod_sel(dist_idx),
        .mod_out(mod_result_wire)
    );

    // 距离比较逻辑
    wire [3:0] diff_step = (current_mod_res != r[dist_idx]) ? 4'd1 : 4'd0;
    wire [3:0] next_dist_acc = current_dist_acc + diff_step;

    // ------------------------------------------------------------------
    // 6. 状态寄存器 (Segment 1 of 2-State FSM)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // ------------------------------------------------------------------
    // 7. 次态逻辑与数据通路 (Segment 2 & Data Path) - [已优化时序]
    // ------------------------------------------------------------------
    
    // --- 组合逻辑：次态判断 ---
    always @(*) begin
        // 默认值：保持当前状态
        next_state = state;
        
        case (state)
            ST_IDLE: begin
                if (start) next_state = ST_LOAD;
            end
            
            ST_LOAD: begin
                next_state = ST_MRC;
            end
            
            ST_MRC: begin
                // MRC 是组合逻辑，结果立即可用，下一状态锁存
                next_state = ST_DIST_INIT;
            end
            
            ST_DIST_INIT: begin
                next_state = ST_DIST_MOD;
            end
            
            // 【修改】计算完成后，跳转到 LATCH 状态，而不是直接 CMP
            ST_DIST_MOD: begin
                next_state = ST_DIST_LATCH;
            end
            
            // 【新增】LATCH 状态完成后，跳转到 CMP 状态
            ST_DIST_LATCH: begin
                next_state = ST_DIST_CMP;
            end
            
            ST_DIST_CMP: begin
                if (dist_idx == 4'd8) begin
                    next_state = ST_UPDATE;
                end else begin
                    // 继续循环：回到 MOD 计算下一个距离
                    next_state = ST_DIST_MOD; 
                end
            end
            
            ST_UPDATE: begin
                next_state = ST_NEXT;
            end
            
            ST_NEXT: begin
                if (combo_idx == 7'd83) begin
                    next_state = ST_DONE;
                end else begin
                    next_state = ST_LOAD;
                end
            end
            
            ST_DONE: begin
                next_state = ST_IDLE;
            end
            
            default: next_state = ST_IDLE;
        endcase
    end

    // --- 时序逻辑：数据寄存器更新 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            combo_idx       <= 0;
            dist_idx        <= 0;
            current_x_reg   <= 0;
            current_mod_res <= 0;
            current_dist_acc<= 0;
            min_dist_reg    <= 4'd10;
            best_val_reg    <= 0;
            valid           <= 0;
            uncorrectable   <= 0;
            data_out        <= 0;
        end else begin
            // 默认清零输出信号
            valid         <= 0;
            uncorrectable <= 0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        combo_idx    <= 0;
                        min_dist_reg <= 4'd10; 
                        best_val_reg <= 0;
                    end
                end
                
                ST_MRC: begin
                    current_x_reg <= mrc_result;
                    // 注意：这里不需要重置 dist_idx 和 acc，因为 ST_DIST_INIT 会做
                end
                
                ST_DIST_INIT: begin
                    dist_idx        <= 0;
                    current_dist_acc<= 0;
                    current_mod_res <= 0;
                end

                // 【关键修改 1】ST_DIST_MOD：什么都不做！
                // 让 current_x_reg 和 dist_idx 保持不变，
                // 给 mod_unit 组合逻辑整整一个时钟周期去计算。
                ST_DIST_MOD: begin
                    // 空操作 (No Operation)
                    // 严禁在此处锁存数据，否则路径切不断
                end
                
                // 【关键修改 2】ST_DIST_LATCH：新增状态
                // 在此时钟沿，假设 mod_unit 已经计算完成并稳定，将其锁存到寄存器
                ST_DIST_LATCH: begin
                    current_mod_res <= mod_result_wire;
                    // dist_idx 和 current_x_reg 继续保持不变
                end
                
                // 【关键修改 3】ST_DIST_CMP：使用已锁存的数据
                // 此时 current_mod_res 是寄存器输出，比较器路径极短
                // 【优化版】ST_DIST_CMP
                ST_DIST_CMP: begin
                    // 直接在时序块内判断并更新，避免依赖外部复杂的 next_dist_acc 逻辑
                    if (current_mod_res != r[dist_idx]) begin
                        current_dist_acc <= current_dist_acc + 1;
                    end 
                    // else: 保持原值 (隐式)

                    if (dist_idx != 4'd8) begin
                        dist_idx <= dist_idx + 1;
                    end
                end
                
                ST_UPDATE: begin
                    if (current_dist_acc < min_dist_reg) begin
                        min_dist_reg <= current_dist_acc;
                        best_val_reg <= current_x_reg;
                    end
                end
                
                ST_NEXT: begin
                    if (combo_idx == 7'd83) begin
                        // Finish, do nothing to combo_idx
                    end else begin
                        combo_idx <= combo_idx + 1;
                    end
                end
                
                ST_DONE: begin
                    if (min_dist_reg <= 3 && best_val_reg < 18'd65536) begin
                        data_out <= best_val_reg[15:0];
                        valid <= 1;
                    end else begin
                        uncorrectable <= 1;
                        valid <= 1;
                        data_out <= 0;
                    end
                end
                
                default: begin
                    // 安全默认值
                end
            endcase
        end
    end

    // ------------------------------------------------------------------
    // 8. MRC 子模块 (优化版：无 % 运算，使用二进制减法链)
    // ------------------------------------------------------------------
    module mrc_unit_optimized (
        input wire [6:0] r1, m1,
        input wire [6:0] r2, m2,
        input wire [6:0] r3, m3,
        output wire [17:0] x_out
    );
        wire [6:0] a1 = r1;
        wire [6:0] a2, a3;
        
        // --- 计算 a2 ---
        wire [6:0] inv_12 = get_mod_inv(m1, m2);
        wire [7:0] diff2 = (r2 >= a1) ? (r2 - a1) : (r2 + m2 - a1);
        wire [13:0] prod2 = diff2 * inv_12;
        
        // 使用 fast_mod_safe 替代 % 运算
        assign a2 = fast_mod_safe(prod2, m2);
        
        // --- 计算 a3 ---
        wire [6:0] inv_13 = get_mod_inv(m1, m3);
        wire [6:0] inv_23 = get_mod_inv(m2, m3);
        
        wire [8:0] diff3_raw = (r3 >= a1) ? (r3 - a1) : (r3 + m3 - a1);
        wire [14:0] term1 = diff3_raw * inv_13;
        wire [6:0] term1_mod = fast_mod_safe(term1, m3);
        
        wire [8:0] diff3_final = (term1_mod >= a2) ? (term1_mod - a2) : (term1_mod + m3 - a2);
        wire [14:0] term2 = diff3_final * inv_23;
        
        assign a3 = fast_mod_safe(term2, m3);
        
        // --- 合成 X ---
        assign x_out = a1 + (a2 * m1) + (a3 * m1 * m2);

        // ================================================================
        // 【核心功能】快速取模函数 (二进制减法链)
        // 输入 val 最大约 8192 (13-14 位), m 最大 65
        // 通过减去 m*512, m*256...m*1 实现取模，无循环，纯组合逻辑
        // ================================================================
        function automatic [6:0] fast_mod_safe(input [15:0] val, input [6:0] m);
            reg [15:0] t;
            begin
                t = val;
                // 从大到小依次尝试减去 m * 2^n
                // 512 * 65 = 33280 (fits in 15 bits? 32768 is max unsigned 15-bit. 
                // Wait, 15 bits unsigned max is 32767. 33280 needs 16 bits.
                // Let's use 16-bit register for safety inside function)
                
                // Re-declare t as 16-bit internally to avoid overflow during subtraction check
                // Actually, input val is [15:0], so max 65535. 
                // m * 512 can be 65 * 512 = 33280. This fits in 16 bits.
                
                if (t >= (m * 16'd512)) t = t - (m * 16'd512);
                if (t >= (m * 16'd256)) t = t - (m * 16'd256);
                if (t >= (m * 16'd128)) t = t - (m * 16'd128);
                if (t >= (m * 16'd64))  t = t - (m * 16'd64);
                if (t >= (m * 16'd32))  t = t - (m * 16'd32);
                if (t >= (m * 16'd16))  t = t - (m * 16'd16);
                if (t >= (m * 16'd8))   t = t - (m * 16'd8);
                if (t >= (m * 16'd4))   t = t - (m * 16'd4);
                if (t >= (m * 16'd2))   t = t - (m * 16'd2);
                if (t >= m)             t = t - m;
                
                // Final safety check (though binary decomp should cover it)
                if (t >= m) t = t - m;
                
                fast_mod_safe = t[6:0];
            end
        endfunction

        // ================================================================
        // 【辅助功能】模逆查找表 (请确保填入完整的 72 项)
        // ================================================================
        function automatic [6:0] get_mod_inv(input [6:0] mx, input [6:0] my);
            begin
                case ({mx, my})
                    // --- 必须补全所有 72 项 ---
                    {7'd64, 7'd63}: return 7'd1;   {7'd64, 7'd65}: return 7'd64;
                    {7'd64, 7'd31}: return 7'd16;  {7'd64, 7'd29}: return 7'd5;
                    {7'd64, 7'd23}: return 7'd9;   {7'd64, 7'd19}: return 7'd11;
                    {7'd64, 7'd17}: return 7'd4;   {7'd64, 7'd11}: return 7'd5;
                    
                    {7'd63, 7'd64}: return 7'd63;  {7'd63, 7'd65}: return 7'd32;
                    {7'd63, 7'd31}: return 7'd1;   {7'd63, 7'd29}: return 7'd6;
                    {7'd63, 7'd23}: return 7'd19;  {7'd63, 7'd19}: return 7'd16;
                    {7'd63, 7'd17}: return 7'd10;  {7'd63, 7'd11}: return 7'd7;
                    
                    {7'd65, 7'd64}: return 7'd1;   {7'd65, 7'd63}: return 7'd32;
                    {7'd65, 7'd31}: return 7'd21;  {7'd65, 7'd29}: return 7'd25;
                    {7'd65, 7'd23}: return 7'd17;  {7'd65, 7'd19}: return 7'd12;
                    {7'd65, 7'd17}: return 7'd11;  {7'd65, 7'd11}: return 7'd10;
                    
                    {7'd31, 7'd64}: return 7'd39;  {7'd31, 7'd63}: return 7'd47;
                    {7'd31, 7'd65}: return 7'd44;  {7'd31, 7'd29}: return 7'd15;
                    {7'd31, 7'd23}: return 7'd3;   {7'd31, 7'd19}: return 7'd8;
                    {7'd31, 7'd17}: return 7'd11;  {7'd31, 7'd11}: return 7'd5;
                    
                    {7'd29, 7'd64}: return 7'd55;  {7'd29, 7'd63}: return 7'd58;
                    {7'd29, 7'd65}: return 7'd56;  {7'd29, 7'd31}: return 7'd15;
                    {7'd29, 7'd23}: return 7'd4;   {7'd29, 7'd19}: return 7'd2;
                    {7'd29, 7'd17}: return 7'd10;  {7'd29, 7'd11}: return 7'd8;
                    
                    {7'd23, 7'd64}: return 7'd47;  {7'd23, 7'd63}: return 7'd44;
                    {7'd23, 7'd65}: return 7'd47;  {7'd23, 7'd31}: return 7'd27;
                    {7'd23, 7'd29}: return 7'd24;  {7'd23, 7'd19}: return 7'd5;
                    {7'd23, 7'd17}: return 7'd3;   {7'd23, 7'd11}: return 7'd1;
                    
                    {7'd19, 7'd64}: return 7'd51;  {7'd19, 7'd63}: return 7'd10;
                    {7'd19, 7'd65}: return 7'd51;  {7'd19, 7'd31}: return 7'd18;
                    {7'd19, 7'd29}: return 7'd26;  {7'd19, 7'd23}: return 7'd17;
                    {7'd19, 7'd17}: return 7'd9;   {7'd19, 7'd11}: return 7'd7;
                    
                    {7'd17, 7'd64}: return 7'd49;  {7'd17, 7'd63}: return 7'd26;
                    {7'd17, 7'd65}: return 7'd38;  {7'd17, 7'd31}: return 7'd11;
                    {7'd17, 7'd29}: return 7'd12;  {7'd17, 7'd23}: return 7'd19;
                    {7'd17, 7'd19}: return 7'd9;   {7'd17, 7'd11}: return 7'd2;
                    
                    {7'd11, 7'd64}: return 7'd35;  {7'd11, 7'd63}: return 7'd23;
                    {7'd11, 7'd65}: return 7'd6;   {7'd11, 7'd31}: return 7'd17;
                    {7'd11, 7'd29}: return 7'd8;   {7'd11, 7'd23}: return 7'd21;
                    {7'd11, 7'd19}: return 7'd7;   {7'd11, 7'd17}: return 7'd14;
                    
                    default: return 7'd1;
                endcase
            end
        endfunction
    endmodule

// ------------------------------------------------------------------
// 9. 优化的模运算单元 (Mod Unit - 无除法)
// ------------------------------------------------------------------
    module mod_unit (
        input  logic [31:0] x,
        input  logic [3:0]  mod_sel,   // 0~8
        output logic [6:0]  mod_out
    );
    
        // --- 内部函数声明 (基于 ChatGPT 优化版) ---

        function automatic [6:0] mod64(input logic [31:0] x);
            begin mod64 = x[5:0]; end
        endfunction

        function automatic [6:0] mod63(input logic [31:0] x);
            logic [11:0] sum1;
            logic [6:0]  sum2;
            begin
                sum1 = x[5:0]+x[11:6]+x[17:12]+x[23:18]+x[29:24]+{4'b0,x[31:30]};
                sum2 = sum1[5:0] + sum1[11:6];
                if (sum2 >= 63) mod63 = sum2 - 63;
                else            mod63 = sum2;
            end
        endfunction

        function automatic [6:0] mod65(input logic [31:0] x);
            logic signed [12:0] sum1;
            logic signed [7:0]  sum2;
            begin
                sum1 =  x[5:0] - x[11:6] + x[17:12]
                      - x[23:18] + x[29:24] - {4'b0,x[31:30]};
                sum2 = sum1[5:0] - sum1[11:6];
                if (sum2 < 0)    sum2 = sum2 + 65;
                if (sum2 >= 65)  mod65 = sum2 - 65;
                else             mod65 = sum2[6:0];
            end
        endfunction

        function automatic [5:0] mod31(input logic [31:0] x);
            logic [11:0] sum1;
            logic [5:0]  sum2;
            begin
                sum1 = x[4:0]+x[9:5]+x[14:10]+x[19:15]+
                       x[24:20]+x[29:25]+{3'b0,x[31:30]};
                sum2 = sum1[4:0] + sum1[9:5];
                if (sum2 >= 31) mod31 = sum2 - 31;
                else            mod31 = sum2;
            end
        endfunction

        function automatic [5:0] mod29(input logic [31:0] x);
            logic [10:0] temp;
            logic [6:0]  t2;
            begin
                temp = x[4:0] + 3*x[9:5] + 9*x[14:10] +
                       27*x[19:15] + 23*x[24:20] +
                       11*x[29:25] + 4*x[31:30];
                t2 = temp[6:0] + temp[10:7];
                if (t2 >= 29) t2 = t2 - 29;
                if (t2 >= 29) t2 = t2 - 29;
                mod29 = t2;
            end
        endfunction

        function automatic [5:0] mod23(input logic [31:0] x);
            logic [10:0] temp;
            logic [6:0]  t2;
            begin
                temp = x[4:0] + 9*x[9:5] + 12*x[14:10] +
                       16*x[19:15] + 6*x[24:20] +
                       8*x[29:25] + 3*x[31:30];
                t2 = temp[6:0] + temp[10:7];
                if (t2 >= 23) t2 = t2 - 23;
                if (t2 >= 23) t2 = t2 - 23;
                mod23 = t2;
            end
        endfunction

        function automatic [5:0] mod19(input logic [31:0] x);
            logic [10:0] temp;
            logic [6:0]  t2;
            begin
                temp = x[4:0] + 13*x[9:5] + 17*x[14:10] +
                       12*x[19:15] + 4*x[24:20] +
                       14*x[29:25] + 11*x[31:30];
                t2 = temp[6:0] + temp[10:7];
                if (t2 >= 19) t2 = t2 - 19;
                if (t2 >= 19) t2 = t2 - 19;
                mod19 = t2;
            end
        endfunction

        function automatic [4:0] mod17(input logic [31:0] x);
            logic signed [8:0] temp;
            begin
                temp = x[3:0] - x[7:4] + x[11:8] -
                       x[15:12] + x[19:16] -
                       x[23:20] + x[27:24] -
                       x[31:28];
                if (temp < 0) temp = temp + 17;
                if (temp >= 17) temp = temp - 17;
                mod17 = temp[4:0];
            end
        endfunction

        function automatic [3:0] mod11(input logic [31:0] x);
            logic signed [7:0] temp;
            begin
                temp = x[4:0]-x[9:5]+x[14:10]-x[19:15]
                      +x[24:20]-x[29:25]+x[31:30]; // 注意这里最高位处理，x[31:30] 可能需调整，但 x 只有 18 位有效，高位为 0，所以没问题
                if (temp < 0) temp = temp + 11;
                if (temp >= 11) temp = temp - 11;
                mod11 = temp[3:0];
            end
        endfunction

        // --- 主选择逻辑 ---
        always_comb begin
            case (mod_sel)
                4'd0: mod_out = {1'b0, mod64(x)};       // 输出 7 位，实际有效 6 位
                4'd1: mod_out = mod63(x);
                4'd2: mod_out = mod65(x);
                4'd3: mod_out = {1'b0, mod31(x)};       // 输出 7 位，实际有效 5 位
                4'd4: mod_out = {1'b0, mod29(x)};
                4'd5: mod_out = {1'b0, mod23(x)};
                4'd6: mod_out = {1'b0, mod19(x)};
                4'd7: mod_out = {2'b0, mod17(x)};       // 输出 7 位，实际有效 4 位
                4'd8: mod_out = {3'b0, mod11(x)};       // 输出 7 位，实际有效 4 位
                default: mod_out = 7'd0;
            endcase
        end
    endmodule

endmodule