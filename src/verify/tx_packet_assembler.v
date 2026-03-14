// =============================================================================
// File: tx_packet_assembler.v
// Description: TX Packet Assembler - Frames 91-point BER stats into UART frame
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc v1.7 Section 2.1.3.2 & 2.3.3.5 (Part B)
// Version: v2.0 (Full Architectural Refactor - Spec v1.7 Compliant)
//
// ─────────────────────────────────────────────────────────────────────────────
// FRAME FORMAT (2011 Bytes Total, Big-Endian):
//   Byte  0:    Sync High  (0xBB)
//   Byte  1:    Sync Low   (0x66)
//   Byte  2:    CmdID      (0x81)
//   Byte  3:    Length Hi  (0x07)  ← 2005 = 0x07D5
//   Byte  4:    Length Lo  (0xD5)
//   Byte  5:    Total_Points (91 = 0x5B)
//   Byte  6:    Algo_Used  (0~3)
//   Byte  7:    Mode_Used  (0/1)
//   Bytes 8..2009: Per-Point Data (91 × 22 Bytes)
//     Each 22-byte entry (Big-Endian multi-byte fields):
//       +0:     BER_Index         (1 Byte, Uint8)
//       +1..+4: Success_Count     (4 Bytes, Uint32, MSB first)
//       +5..+8: Fail_Count        (4 Bytes, Uint32, MSB first)
//       +9..+12:Actual_Flip_Count (4 Bytes, Uint32, MSB first)
//       +13..+20:Clk_Count        (8 Bytes, Uint64, MSB first)
//       +21:    Reserved          (1 Byte, 0x00)
//   Byte 2010:  Checksum (1 Byte, XOR of all preceding bytes)
//
// CHECKSUM:
//   8-bit XOR reduction over ALL bytes from Byte 0 to Byte 2009 (inclusive).
//   Per Spec v1.7 Section 2.1.3.1: Checksum = Byte[0] ^ Byte[1] ^ ... ^ Byte[N-1]
//
// MEMORY INTERFACE:
//   mem_rd_addr: 7-bit address (0~90), driven by this module.
//   mem_rd_data: 176-bit data from mem_stats_array (1-cycle BRAM latency).
//   RD_WAIT state issues address, SEND_BYTES state reads latched data.
//
// FLOW CONTROL:
//   tx_valid=1 + tx_ready=1 → byte consumed, FSM advances.
//   tx_valid=1 + tx_ready=0 → byte held, FSM stalls (backpressure).
//
// 176-BIT DATA LAYOUT (from mem_stats_array, Big-Endian field order):
//   [175:168] BER_Index         (8-bit)
//   [167:136] Success_Count     (32-bit)
//   [135:104] Fail_Count        (32-bit)
//   [103:72]  Actual_Flip_Count (32-bit)
//   [71:8]    Clk_Count         (64-bit)
//   [7:0]     Reserved          (8-bit, 0x00)
// =============================================================================

`include "tx_packet_assembler.vh"
`include "mem_stats_array.vh"
`timescale 1ns / 1ps

module tx_packet_assembler (
    // -------------------------------------------------------------------------
    // Global Clock & Reset
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Control (From Main Scan FSM)
    // -------------------------------------------------------------------------
    input  wire        start,
    // start: Single-cycle pulse to begin packet assembly and transmission.
    // Ignored if busy=1.

    input  wire [1:0]  algo_id_in,
    // algo_id_in: Algorithm ID to embed in Global Info field (0~3).

    input  wire [1:0]  mode_id_in,
    // mode_id_in: Mode ID to embed in Global Info field (0/1).

    // -------------------------------------------------------------------------
    // Memory Read Interface (To mem_stats_array Port B)
    // -------------------------------------------------------------------------
    output reg  [`STATS_MEM_ADDR_WIDTH-1:0] mem_rd_addr,
    // mem_rd_addr: 7-bit read address (0~90). Driven by this module.

    input  wire [`STATS_DATA_WIDTH-1:0]     mem_rd_data,
    // mem_rd_data: 176-bit data from mem_stats_array.
    // Valid 1 clock cycle after mem_rd_addr is presented (BRAM latency).

    // -------------------------------------------------------------------------
    // TX Output (To UART TX Module, Valid/Ready Handshake)
    // -------------------------------------------------------------------------
    output reg         tx_valid,
    // tx_valid: HIGH when tx_data contains a valid byte to transmit.

    output reg  [7:0]  tx_data,
    // tx_data: Current byte to transmit. Stable while tx_valid=1.

    input  wire        tx_ready,
    // tx_ready: HIGH when UART TX module can accept a new byte.
    // Byte consumed only when tx_valid=1 AND tx_ready=1.

    // -------------------------------------------------------------------------
    // Status Outputs
    // -------------------------------------------------------------------------
    output wire        busy,
    // busy: HIGH when FSM is not in IDLE state.

    output reg         done
    // done: Single-cycle pulse when all 2011 bytes have been transmitted.
);

    // =========================================================================
    // 1. FSM State Register
    // =========================================================================
    reg [3:0] state;
    assign busy = (state != `ASM_STATE_IDLE);

    // =========================================================================
    // 2. Internal Registers
    // =========================================================================

    // Latched parameters (captured at start)
    reg [1:0] algo_id_latch;
    reg [1:0] mode_id_latch;

    // Point counter: 0~90 (current BER point being serialized)
    reg [6:0] point_cnt;

    // Byte counter within current 22-byte entry: 0~21
    reg [4:0] byte_cnt;

    // Global Info byte counter: 0~2
    reg [1:0] ginfo_cnt;

    // Sync byte index: 0=0xBB, 1=0x66
    reg       sync_idx;

    // Latched 176-bit entry from BRAM (held while serializing 22 bytes)
    reg [`STATS_DATA_WIDTH-1:0] entry_latch;

    // 8-bit XOR checksum accumulator
    reg [7:0] xor_chk;

    // =========================================================================
    // 3. Byte Selection from 176-bit Entry (Big-Endian serialization)
    // =========================================================================
    // 176-bit entry layout (MSB=bit175 → LSB=bit0):
    //   Byte  0 (sent first):  entry[175:168] = BER_Index
    //   Byte  1..4:            entry[167:136] = Success_Count (MSB first)
    //   Byte  5..8:            entry[135:104] = Fail_Count (MSB first)
    //   Byte  9..12:           entry[103:72]  = Actual_Flip_Count (MSB first)
    //   Byte 13..20:           entry[71:8]    = Clk_Count (MSB first)
    //   Byte 21 (sent last):   entry[7:0]     = Reserved (0x00)
    //
    // Formula: byte_cnt=0 → bits[175:168], byte_cnt=1 → bits[167:160], ...
    //          byte_cnt=k → bits[175-8k : 168-8k]
    //
    // Implemented as: entry_latch >> (8*(21-byte_cnt)) then take [7:0]

    // Big-Endian byte extraction: byte_cnt=0 → MSB (BER_Index), byte_cnt=21 → LSB (Reserved)
    // Use a registered mux to avoid variable part-select synthesis issues.
    // The 22-byte case statement maps directly to BRAM output bits.
    reg [7:0] current_entry_byte;
    always @(*) begin
        case (byte_cnt)
            5'd0:  current_entry_byte = entry_latch[175:168]; // BER_Index
            5'd1:  current_entry_byte = entry_latch[167:160]; // Success[31:24]
            5'd2:  current_entry_byte = entry_latch[159:152]; // Success[23:16]
            5'd3:  current_entry_byte = entry_latch[151:144]; // Success[15:8]
            5'd4:  current_entry_byte = entry_latch[143:136]; // Success[7:0]
            5'd5:  current_entry_byte = entry_latch[135:128]; // Fail[31:24]
            5'd6:  current_entry_byte = entry_latch[127:120]; // Fail[23:16]
            5'd7:  current_entry_byte = entry_latch[119:112]; // Fail[15:8]
            5'd8:  current_entry_byte = entry_latch[111:104]; // Fail[7:0]
            5'd9:  current_entry_byte = entry_latch[103:96];  // Flip[31:24]
            5'd10: current_entry_byte = entry_latch[95:88];   // Flip[23:16]
            5'd11: current_entry_byte = entry_latch[87:80];   // Flip[15:8]
            5'd12: current_entry_byte = entry_latch[79:72];   // Flip[7:0]
            5'd13: current_entry_byte = entry_latch[71:64];   // Clk[63:56]
            5'd14: current_entry_byte = entry_latch[63:56];   // Clk[55:48]
            5'd15: current_entry_byte = entry_latch[55:48];   // Clk[47:40]
            5'd16: current_entry_byte = entry_latch[47:40];   // Clk[39:32]
            5'd17: current_entry_byte = entry_latch[39:32];   // Clk[31:24]
            5'd18: current_entry_byte = entry_latch[31:24];   // Clk[23:16]
            5'd19: current_entry_byte = entry_latch[23:16];   // Clk[15:8]
            5'd20: current_entry_byte = entry_latch[15:8];    // Clk[7:0]
            5'd21: current_entry_byte = entry_latch[7:0];     // Reserved (0x00)
            default: current_entry_byte = 8'h00;
        endcase
    end

    // =========================================================================
    // 4. Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= `ASM_STATE_IDLE;
            tx_valid       <= 1'b0;
            tx_data        <= 8'h00;
            done           <= 1'b0;
            mem_rd_addr    <= {`STATS_MEM_ADDR_WIDTH{1'b0}};
            xor_chk        <= 8'h00;
            point_cnt      <= 7'd0;
            byte_cnt       <= 5'd0;
            ginfo_cnt      <= 2'd0;
            sync_idx       <= 1'b0;
            entry_latch    <= {`STATS_DATA_WIDTH{1'b0}};
            algo_id_latch  <= 2'd0;
            mode_id_latch  <= 2'd0;

        end else begin
            // Default: deassert single-cycle signals
            done <= 1'b0;

            case (state)

                // =============================================================
                // IDLE: Wait for start pulse
                // =============================================================
                `ASM_STATE_IDLE: begin
                    tx_valid <= 1'b0;
                    if (start) begin
                        algo_id_latch <= algo_id_in;
                        mode_id_latch <= mode_id_in;
                        xor_chk       <= 8'h00;
                        point_cnt     <= 7'd0;
                        byte_cnt      <= 5'd0;
                        ginfo_cnt     <= 2'd0;
                        sync_idx      <= 1'b0;
                        state         <= `ASM_STATE_SYNC;
                    end
                end

                // =============================================================
                // SYNC: Send 2-byte sync word (0xBB, 0x66)
                // =============================================================
                `ASM_STATE_SYNC: begin
                    tx_valid <= 1'b1;
                    tx_data  <= sync_idx ? `PKT_SYNC_LO : `PKT_SYNC_HI;

                    if (tx_valid && tx_ready) begin
                        xor_chk <= xor_chk ^ tx_data;
                        if (sync_idx) begin
                            sync_idx <= 1'b0;
                            state    <= `ASM_STATE_CMD;
                        end else begin
                            sync_idx <= 1'b1;
                        end
                    end
                end

                // =============================================================
                // CMD: Send CmdID (0x81)
                // =============================================================
                `ASM_STATE_CMD: begin
                    tx_valid <= 1'b1;
                    tx_data  <= `PKT_CMD_STATS;

                    if (tx_valid && tx_ready) begin
                        xor_chk <= xor_chk ^ tx_data;
                        state   <= `ASM_STATE_LEN_HI;
                    end
                end

                // =============================================================
                // LEN_HI: Send Length High Byte (0x07)
                // =============================================================
                `ASM_STATE_LEN_HI: begin
                    tx_valid <= 1'b1;
                    tx_data  <= `PKT_LENGTH_HI;

                    if (tx_valid && tx_ready) begin
                        xor_chk <= xor_chk ^ tx_data;
                        state   <= `ASM_STATE_LEN_LO;
                    end
                end

                // =============================================================
                // LEN_LO: Send Length Low Byte (0xD5)
                // =============================================================
                `ASM_STATE_LEN_LO: begin
                    tx_valid <= 1'b1;
                    tx_data  <= `PKT_LENGTH_LO;

                    if (tx_valid && tx_ready) begin
                        xor_chk <= xor_chk ^ tx_data;
                        state   <= `ASM_STATE_GINFO;
                    end
                end

                // =============================================================
                // GINFO: Send 3-byte Global Info
                //   Byte 0: Total_Points = 91 (0x5B)
                //   Byte 1: Algo_ID (0~3)
                //   Byte 2: Mode_ID (0/1)
                // =============================================================
                `ASM_STATE_GINFO: begin
                    tx_valid <= 1'b1;
                    case (ginfo_cnt)
                        2'd0: tx_data <= 8'd`PKT_TOTAL_POINTS; // 91 = 0x5B
                        2'd1: tx_data <= {6'd0, algo_id_latch};
                        2'd2: tx_data <= {6'd0, mode_id_latch};
                        default: tx_data <= 8'h00;
                    endcase

                    if (tx_valid && tx_ready) begin
                        xor_chk <= xor_chk ^ tx_data;
                        if (ginfo_cnt == 2'd2) begin
                            // All 3 Global Info bytes sent → start per-point data
                            ginfo_cnt   <= 2'd0;
                            mem_rd_addr <= 7'd0;   // Issue read for point 0
                            state       <= `ASM_STATE_RD_WAIT;
                        end else begin
                            ginfo_cnt <= ginfo_cnt + 2'd1;
                        end
                    end
                end

                // =============================================================
                // RD_WAIT: Wait 1 cycle for BRAM read latency
                //   mem_rd_addr was set in previous state/cycle.
                //   BRAM output (mem_rd_data) is valid this cycle.
                //   Latch it and proceed to SEND_BYTES.
                // =============================================================
                `ASM_STATE_RD_WAIT: begin
                    tx_valid    <= 1'b0;
                    entry_latch <= mem_rd_data; // Latch 176-bit BRAM output
                    byte_cnt    <= 5'd0;        // Start from byte 0 (BER_Index)
                    state       <= `ASM_STATE_SEND_BYTES;
                end

                // =============================================================
                // SEND_BYTES: Serialize 22 bytes of current entry (Big-Endian)
                //   byte_cnt=0  → entry[175:168] = BER_Index
                //   byte_cnt=1  → entry[167:160] = Success_Count[31:24]
                //   ...
                //   byte_cnt=21 → entry[7:0]     = Reserved (0x00)
                // =============================================================
                `ASM_STATE_SEND_BYTES: begin
                    tx_valid <= 1'b1;
                    tx_data  <= current_entry_byte;

                    if (tx_valid && tx_ready) begin
                        xor_chk <= xor_chk ^ tx_data;

                        if (byte_cnt == 5'd21) begin
                            // All 22 bytes of this entry sent
                            if (point_cnt == 7'd(`PKT_TOTAL_POINTS - 1)) begin
                                // All 91 points sent → send checksum
                                tx_valid <= 1'b0;
                                state    <= `ASM_STATE_CHECKSUM;
                            end else begin
                                // More points → advance address and read next
                                point_cnt   <= point_cnt + 7'd1;
                                mem_rd_addr <= point_cnt + 7'd1; // Next address
                                tx_valid    <= 1'b0;
                                state       <= `ASM_STATE_RD_WAIT;
                            end
                        end else begin
                            byte_cnt <= byte_cnt + 5'd1;
                        end
                    end
                end

                // =============================================================
                // CHECKSUM: Send 1-byte XOR checksum
                //   xor_chk = XOR of all bytes from Sync to last Reserved byte
                // =============================================================
                `ASM_STATE_CHECKSUM: begin
                    tx_valid <= 1'b1;
                    tx_data  <= xor_chk;
                    // Note: checksum byte itself is NOT included in XOR (per spec)

                    if (tx_valid && tx_ready) begin
                        tx_valid <= 1'b0;
                        state    <= `ASM_STATE_DONE;
                    end
                end

                // =============================================================
                // DONE: Assert done pulse, return to IDLE
                // =============================================================
                `ASM_STATE_DONE: begin
                    done  <= 1'b1; // Single-cycle pulse
                    state <= `ASM_STATE_IDLE;
                end

                // =============================================================
                // Default: Safety catch-all
                // =============================================================
                default: begin
                    state    <= `ASM_STATE_IDLE;
                    tx_valid <= 1'b0;
                end

            endcase
        end
    end

endmodule
