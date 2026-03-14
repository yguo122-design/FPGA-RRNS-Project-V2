// =============================================================================
// File: protocol_parser.vh
// Description: Interface and Parameter Definitions for Protocol Parser Module
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
// Version: v1.62 (Fixed for Macro Compatibility)
// =============================================================================

`ifndef PROTOCOL_PARSER_VH
`define PROTOCOL_PARSER_VH

// -----------------------------------------------------------------------------
// 1. Protocol Constants (协议常量定义) - 改为 `define 宏以匹配 .v 文件
// -----------------------------------------------------------------------------
// Frame Headers
`define FRAME_HEADER_BYTE1 8'hAA
`define FRAME_HEADER_BYTE2 8'h55

// Command IDs
`define CMD_ID_CONFIG      8'h01 // Configuration & Start Command

// Payload Lengths
`define PAYLOAD_LEN_CONFIG 8'd7  // Fixed payload length for Config Command

// Frame Offsets (for reference in parsing logic)
`define OFFSET_HEADER_1    0
`define OFFSET_HEADER_2    1
`define OFFSET_CMD_ID      2
`define OFFSET_LEN         3
`define OFFSET_PAYLOAD_START 4

// -----------------------------------------------------------------------------
// 2. State Machine Definition (状态机定义)
// -----------------------------------------------------------------------------
// 注意：Verilog 宏无法直接定义 enum 类型供外部模块直接使用而不包裹在 generate/interface 中。
// 最兼容的方法是在 .v 文件中直接定义 enum，或者在这里定义宏来展开 enum。
// 鉴于你的 .v 文件直接使用了 parser_state_t 类型，我们需要确保该类型在编译单元可见。

// 方案 A (推荐): 如果你的工具链支持 SystemVerilog (.sv 后缀或 mixed mode)，
// 可以直接在这里定义 typedef，前提是 .v 文件被当作 .sv 编译，或者使用 `include 在 module 外部。
// 但由于你的 .v 文件是 Verilog 风格，我们在 .v 文件的 include 之后，模块定义之前，需要类型可见。

// Verilog-2001 compatible state encoding (localparam style).
// Use `define macros so they are visible after `include in any .v file.
// The .v file uses reg [2:0] for state variables (no typedef needed).

`define ST_IDLE         3'd0
`define ST_WAIT_HDR_2   3'd1
`define ST_READ_CMD     3'd2
`define ST_READ_LEN     3'd3
`define ST_READ_PAYLOAD 3'd4
`define ST_CHECK_SUM    3'd5
`define ST_ERROR        3'd6

// Legacy macro kept as no-op for backward compatibility (safe to remove later)
`define DEFINE_PARSER_TYPES

// -----------------------------------------------------------------------------
// 3. Module Port Definition (模块端口定义)
// -----------------------------------------------------------------------------
// 修正：移除了 interface 定义（interface 只能在 SystemVerilog 顶层或 package 中使用，不能直接放在 .vh 中被普通 .v include）
// 保留宏定义用于端口列表

`define PROTOCOL_PARSER_PORTS \
    input  wire        clk,             \
    input  wire        rst_n,           \
    input  wire [7:0]  rx_byte,         \
    input  wire        rx_valid,        \
    output reg         cfg_update_pulse,\
    output reg  [7:0]  cfg_algo_id,     \
    output reg  [7:0]  cfg_burst_len,   \
    output reg  [7:0]  cfg_error_mode,  \
    output reg  [31:0] cfg_sample_count, \
    output wire [2:0]  state_dbg,       \
    output wire        checksum_error   // <--- 新增：别忘了加上这个新端口！

`endif // PROTOCOL_PARSER_VH