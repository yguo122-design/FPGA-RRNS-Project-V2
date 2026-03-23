// =============================================================================
// File: tx_packet_assembler.vh
// Description: Header for TX Packet Assembler Module
//              Complies with Design Doc v1.7 Section 2.1.3.2 & 2.3.3.5
//
// REFACTOR NOTE (v2.0):
//   Previous version (v1.0) used wrong sync word (0xA55A), wrong CmdID (0x01),
//   1-byte Length field (max 255), no Global Info, 8-byte per entry (64-bit),
//   and 16-bit additive checksum. All mismatched against Spec v1.7.
//
//   v2.0 changes (strict Spec v1.7 compliance):
//   - Sync Word:  0xA55A → 0xBB66
//   - CmdID:      0x01   → 0x81
//   - Length:     1-byte → 2-byte Big-Endian (value = 1914 = 0x077A)
//   - Global Info: added 3-byte field (Total_Points, Algo_ID, Mode_ID)
//   - Per-Point:  8 bytes (64-bit) → 22 bytes (176-bit)
//   - Total Frame: 70 bytes max → 2011 bytes fixed
//   - Checksum:   16-bit additive → 8-bit XOR (per Spec 2.1.3.1)
// =============================================================================

`ifndef TX_PACKET_ASSEMBLER_VH
`define TX_PACKET_ASSEMBLER_VH

// -----------------------------------------------------------------------------
// 1. Protocol Constants (Spec v1.7 Section 2.1.3.2)
// -----------------------------------------------------------------------------

// Sync Word: 2-byte header to identify start of response frame
`define PKT_SYNC_HI           8'hBB   // First byte
`define PKT_SYNC_LO           8'h66   // Second byte

// Command ID for statistics response
`define PKT_CMD_STATS         8'h81

// Frame structure sizes (bytes)
`define PKT_HEADER_BYTES      6    // Sync(2) + CmdID(1) + Length(2) + (implicit)
// Note: Header = Sync(2) + CmdID(1) + Length(2) = 5 bytes
// Then Global Info = 3 bytes → total fixed header = 8 bytes before per-point data

`define PKT_GLOBAL_INFO_BYTES 3    // Total_Points(1) + Algo_ID(1) + Mode_ID(1)
`define PKT_BYTES_PER_POINT   30   // 30 bytes per BER point (240-bit)
`define PKT_TOTAL_POINTS      101  // 101 BER test points (index 0~100, BER 0.000~0.100)
`define PKT_CHECKSUM_BYTES    1    // 1-byte XOR checksum at frame end

// Length field value = GlobalInfo(3) + PerPointData(101*30=3030) = 3033 = 0x0BD9
// (Excludes checksum per spec)
`define PKT_LENGTH_HI         8'h0B   // 3033 = 0x0BD9
`define PKT_LENGTH_LO         8'hD9

// Total frame size = Sync(2) + CmdID(1) + Length(2) + GlobalInfo(3) + 101*30 + Checksum(1)
//                 = 2 + 1 + 2 + 3 + 3030 + 1 = 3039 bytes
`define PKT_TOTAL_FRAME_BYTES 3039

// Byte width
`define PKT_BYTE_WIDTH        8

// -----------------------------------------------------------------------------
// 2. FSM States
// -----------------------------------------------------------------------------

`define ASM_STATE_IDLE        4'd0
`define ASM_STATE_SYNC        4'd1   // Send Sync Word (2 bytes: 0xBB, 0x66)
`define ASM_STATE_CMD         4'd2   // Send CmdID (1 byte: 0x81)
`define ASM_STATE_LEN_HI      4'd3   // Send Length High Byte (0x07)
`define ASM_STATE_LEN_LO      4'd4   // Send Length Low Byte (0xD5)
`define ASM_STATE_GINFO       4'd5   // Send Global Info (3 bytes)
`define ASM_STATE_RD_WAIT     4'd6   // Issue mem read, wait 1 cycle for BRAM latency
`define ASM_STATE_SEND_BYTES  4'd7   // Serialize 22 bytes of current entry
`define ASM_STATE_CHECKSUM    4'd8   // Send 1-byte XOR checksum
`define ASM_STATE_DONE        4'd9   // Pulse done, return to IDLE

// -----------------------------------------------------------------------------
// 3. Global Info Byte Indices (within 3-byte Global Info field)
// -----------------------------------------------------------------------------

`define GINFO_TOTAL_POINTS    0   // Byte 0: Total_Points = 91
`define GINFO_ALGO_ID         1   // Byte 1: Algo_Used (0~3)
`define GINFO_MODE_ID         2   // Byte 2: Mode_Used (0/1)

`endif // TX_PACKET_ASSEMBLER_VH
