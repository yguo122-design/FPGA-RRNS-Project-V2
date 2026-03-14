// =============================================================================
// File: mem_stats_array.v
// Description: BER Statistics RAM - 91-Entry Direct-Addressed Dual-Port RAM
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc v1.7 Section 2.3.3.5
// Version: v2.0 (Architectural Refactor - BER Statistical Aggregator)
//
// REFACTOR SUMMARY (v1.0 → v2.0):
//   v1.0: 64-bit Circular Buffer (1024 entries), internal auto-increment write
//         pointer, Circular/Stop-on-Fail/Once modes. Designed as a generic
//         "Single-Event Logger" — architectural mismatch vs Spec v1.7.
//   v2.0: 176-bit Direct-Addressed RAM (91 entries), external wr_addr driven
//         by FSM ber_idx. Simple dual-port behavior. Spec-compliant.
//
// DATA FORMAT (176-bit = 22 Bytes per entry, Big-Endian field order):
//   [175:168] BER_Index         (8-bit,  Uint8)
//   [167:136] Success_Count     (32-bit, Uint32)
//   [135:104] Fail_Count        (32-bit, Uint32)
//   [103:72]  Actual_Flip_Count (32-bit, Uint32)
//   [71:8]    Clk_Count         (64-bit, Uint64)
//   [7:0]     Reserved          (8-bit,  0x00)
//
// BRAM MAPPING:
//   91 × 176 bits = 16,016 bits < 18 Kbits (RAMB18E1)
//   Vivado infers as Block RAM via (* ram_style = "block" *).
// =============================================================================

`include "mem_stats_array.vh"
`timescale 1ns / 1ps

module mem_stats_array (
    input  wire                             clk,
    input  wire                             rst_n,

    // -------------------------------------------------------------------------
    // Write Port A (From Main Scan FSM — one write per BER point)
    // -------------------------------------------------------------------------
    input  wire                             we_a,
    // we_a: Write enable. When HIGH for one cycle, din_a is written to
    // mem[wr_addr_a]. The FSM asserts this once per BER point in SAVE_RES state.

    input  wire [`STATS_MEM_ADDR_WIDTH-1:0] wr_addr_a,
    // wr_addr_a: Write address = ber_idx (0~90). Driven directly by FSM.
    // No internal pointer — the FSM owns the address.

    input  wire [`STATS_DATA_WIDTH-1:0]     din_a,
    // din_a: 176-bit packed statistics entry.
    // Format: {BER_Index[7:0], Success[31:0], Fail[31:0],
    //           Flip[31:0], Clk[63:0], Reserved[7:0]}

    // -------------------------------------------------------------------------
    // Read Port B (From TX Packet Assembler — sequential readback)
    // -------------------------------------------------------------------------
    input  wire [`STATS_MEM_ADDR_WIDTH-1:0] rd_addr_b,
    // rd_addr_b: Read address (0~90). Driven by tx_packet_assembler.

    output reg  [`STATS_DATA_WIDTH-1:0]     dout_b
    // dout_b: 176-bit data output. Registered (1-cycle latency after rd_addr_b).
    // tx_packet_assembler must account for this 1-cycle read latency.
);

    // =========================================================================
    // Memory Array Declaration
    // =========================================================================
    // 91 entries × 176 bits = 16,016 bits
    // (* ram_style = "block" *) forces Vivado to infer BRAM (not LUTRAM).
    // Without this attribute, Vivado might choose distributed RAM for small
    // arrays, which wastes LUTs and may not meet timing at 100MHz.

    (* ram_style = "block" *)
    reg [`STATS_DATA_WIDTH-1:0] mem [0:`STATS_MEM_DEPTH-1];

    // =========================================================================
    // Write Port A: Synchronous Write
    // =========================================================================
    // Simple registered write: on rising edge, if we_a=1, store din_a at wr_addr_a.
    // No mode logic, no pointer management — the FSM controls everything.
    //
    // Reset behavior: mem contents are NOT cleared on reset (saves reset time).
    // The FSM always writes all 91 entries before reading, so stale data from
    // a previous run is always overwritten before the assembler reads it.

    always @(posedge clk) begin
        if (we_a) begin
            mem[wr_addr_a] <= din_a;
        end
    end

    // =========================================================================
    // Read Port B: Synchronous Read (1-cycle latency)
    // =========================================================================
    // Registered read: dout_b is valid 1 clock cycle after rd_addr_b is presented.
    // This matches BRAM read-first behavior and ensures timing closure at 100MHz.
    //
    // tx_packet_assembler must issue rd_addr_b one cycle before it needs dout_b.
    // The assembler's READ_WAIT sub-state handles this latency.
    //
    // Reset: dout_b cleared to 0 on rst_n to prevent X-propagation in simulation.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_b <= {`STATS_DATA_WIDTH{1'b0}};
        end else begin
            dout_b <= mem[rd_addr_b];
        end
    end

endmodule
