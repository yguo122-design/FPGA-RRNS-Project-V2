// =============================================================================
// File: error_injector_unit.v
// Description: ROM-Based Error Injector Unit
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.2.5 (ROM Look-Up Table Strategy)
// Version: v1.0
//
// ─────────────────────────────────────────────────────────────────────────────
// DESIGN PHILOSOPHY (Section 2.3.2.5):
//   This module implements the "ROM Pre-calculated Error Pattern" strategy.
//   The ROM stores 64-bit error patterns pre-computed by the PC-side gen_rom.py
//   script. Each entry encodes a contiguous burst of flipped bits at a specific
//   offset within the valid codeword region.
//
//   Key properties:
//   1. ZERO boundary check logic in FPGA hardware — all boundary safety is
//      guaranteed by the PC-side ROM generation script. Invalid address
//      combinations (offset > W_valid - L) are pre-filled with 64'h0,
//      resulting in "no injection" behavior automatically.
//   2. SINGLE-CYCLE lookup latency — ROM read is registered, output appears
//      one clock cycle after inject_en is asserted.
//   3. ALGORITHM-AGNOSTIC — the module has no knowledge of specific ECC
//      algorithms. The algo_id field simply selects the correct ROM partition.
//
// ADDRESS MAPPING (Section 2.3.2.5):
//   12-bit address = {algo_id[1:0], (burst_len-1)[3:0], random_offset[5:0]}
//   - bits[11:10]: algo_id    (0=2NRM, 1=3NRM, 2=C-RRNS, 3=RS)
//                  NOTE: Matches gen_rom.py ALGORITHMS dict order exactly.
//                  Previous comment had C-RRNS and RS swapped — now corrected.
//   - bits[9:6]:   burst_len-1 (0~14, corresponding to L=1~15)
//   - bits[5:0]:   random_offset (0~63, from LFSR output)
//   ROM depth: 2^12 = 4096 entries, each 64 bits wide.
//
// INJECTION LOGIC:
//   data_out = inject_en ? (data_in XOR error_pattern) : data_in
//   flip_count = inject_en ? $countones(error_pattern) : 0
//   Both outputs are registered (1-cycle latency after inject_en).
//
// FLIP COUNT:
//   Uses $countones() system function, which Vivado synthesizes as an
//   efficient adder tree (popcount circuit). Reports the exact number of
//   bits flipped in this injection event for BER statistics.
// =============================================================================

`include "error_injector_unit.vh"

module error_injector_unit (
    // -------------------------------------------------------------------------
    // Global Clock & Reset
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Control
    // -------------------------------------------------------------------------
    input  wire        inject_en,
    // inject_en=1: Perform error injection using ROM lookup
    // inject_en=0: Pass data_in through unchanged (no injection)

    // -------------------------------------------------------------------------
    // Address Inputs (Section 2.3.2.5 Address Mapping)
    // -------------------------------------------------------------------------
    input  wire [`INJ_ALGO_ID_WIDTH-1:0]   algo_id,
    // Algorithm selector: 0=2NRM, 1=3NRM, 2=C-RRNS, 3=RS
    // Matches gen_rom.py ALGORITHMS dict. Selects the correct 1024-entry ROM partition.

    input  wire [`INJ_BURST_LEN_WIDTH-1:0] burst_len,
    // Burst length L (1~15). Value 0 is invalid (undefined behavior).
    // Address uses (burst_len - 1), mapping L=1->0, L=15->14.

    input  wire [`INJ_OFFSET_WIDTH-1:0]    random_offset,
    // 6-bit random offset from LFSR output (0~63).
    // PC script ensures offsets beyond (W_valid - L) map to 0 in ROM.

    // -------------------------------------------------------------------------
    // Data Path
    // -------------------------------------------------------------------------
    input  wire [`INJ_ROM_DATA_WIDTH-1:0]  data_in,
    // Input codeword (64-bit, right-aligned, high bits are zero-padding)

    output reg  [`INJ_ROM_DATA_WIDTH-1:0]  data_out,
    // Output: data_in XOR error_pattern (inject_en=1), or data_in (inject_en=0)
    // Registered output: valid 1 clock cycle after inject_en

    output reg  [5:0]                      flip_count
    // Number of bits flipped in this cycle (0 if inject_en=0)
    // Registered output: valid 1 clock cycle after inject_en
);

    // =========================================================================
    // ROM Declaration and Initialization (Section 2.3.2.5)
    // =========================================================================
    // Synthesis attribute to force Vivado to infer this as Block RAM or
    // Distributed ROM (not registers). The 'rom' style hint ensures the
    // tool treats this as read-only memory.
    (* ram_style = "block" *)
    reg [`INJ_ROM_DATA_WIDTH-1:0] rom_mem [0:`INJ_ROM_DEPTH-1];

    // Load ROM contents from COE file generated by gen_rom.py
    // The COE file contains 4096 entries of 64-bit hex values.
    // Invalid address entries (boundary violations) are pre-filled with 0.
    initial begin
        $readmemh(`INJ_ROM_COE_FILE, rom_mem);
    end

    // =========================================================================
    // Address Generation (Section 2.3.2.5 Formula)
    // =========================================================================
    // Address = {algo_id[1:0], (burst_len-1)[3:0], random_offset[5:0]}
    //
    // burst_len input range: 1~15 (4-bit)
    // (burst_len - 1) range: 0~14 (4-bit, never underflows since min input is 1)
    //
    // FIX S2: burst_len=0 underflow protection
    // -----------------------------------------------------------------
    // PROBLEM: If burst_len=0 is passed (e.g., at power-on before the first
    //   config frame arrives, when ctrl_register_bank resets reg_burst_len=0),
    //   the subtraction (0 - 1) wraps to 4'b1111 (=15), selecting the L=15
    //   ROM partition and potentially injecting 15 consecutive bit errors.
    //   This is far beyond the intended injection level and could corrupt
    //   the first test point's statistics.
    //
    // FIX: Clamp burst_len to minimum 1 before subtraction using a
    //   combinational guard. burst_len_safe is 1 when burst_len=0,
    //   and equals burst_len for all valid values (1~15).
    //   This adds zero logic depth (single MUX, absorbed into address path).
    // -----------------------------------------------------------------
    wire [`INJ_BURST_LEN_WIDTH-1:0] burst_len_safe;
    assign burst_len_safe = (burst_len == {`INJ_BURST_LEN_WIDTH{1'b0}}) ?
                             {{(`INJ_BURST_LEN_WIDTH-1){1'b0}}, 1'b1} : // 0 → clamp to 1
                             burst_len;                                   // 1~15 → pass through

    // Total address width: 2 + 4 + 6 = 12 bits = INJ_ROM_ADDR_WIDTH ✓
    wire [`INJ_ROM_ADDR_WIDTH-1:0] rom_addr;
    assign rom_addr = {
        algo_id,                                              // bits[11:10]: algo partition
        burst_len_safe - {{(`INJ_BURST_LEN_WIDTH-1){1'b0}}, 1'b1}, // bits[9:6]: burst index (L-1), safe
        random_offset                                         // bits[5:0]:   random position
    };

    // =========================================================================
    // ROM Lookup (Combinational)
    // =========================================================================
    // Read the pre-calculated 64-bit error pattern from ROM.
    // If rom_addr points to an invalid combination (e.g., offset > W_valid - L),
    // the ROM content at that address is 64'h0 (no bits to flip) — guaranteed
    // by the PC-side gen_rom.py script. No hardware boundary check needed.

    wire [`INJ_ROM_DATA_WIDTH-1:0] error_pattern;
    assign error_pattern = rom_mem[rom_addr];

    // =========================================================================
    // Registered Output Stage (1-cycle latency for timing closure)
    // =========================================================================
    // Registering the output after ROM lookup ensures:
    //   1. The ROM read path (address decode + BRAM access) meets timing at 100MHz
    //   2. data_out and flip_count are stable for the downstream pipeline
    //
    // Timing: inject_en asserted at cycle N → data_out valid at cycle N+1

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // -----------------------------------------------------------------
            // Asynchronous Reset: Clear all outputs
            // -----------------------------------------------------------------
            data_out   <= {`INJ_ROM_DATA_WIDTH{1'b0}};
            flip_count <= 6'd0;

        end else begin

            if (inject_en) begin
                // -------------------------------------------------------------
                // Injection Mode:
                //   XOR data_in with the ROM-fetched error_pattern.
                //   Only bits where error_pattern=1 are flipped.
                //   Since ROM guarantees pattern stays within W_valid bits,
                //   zero-padding bits are never affected (Section 2.3.2.5).
                // -------------------------------------------------------------
                data_out   <= data_in ^ error_pattern;

                // Count the number of bits flipped using popcount.
                // $countones() is synthesized by Vivado as an adder tree,
                // which is more efficient than a manual loop.
                // Result is at most 15 (max burst_len), fits in 6 bits.
                flip_count <= $countones(error_pattern);

            end else begin
                // -------------------------------------------------------------
                // Pass-Through Mode:
                //   No injection. Output equals input exactly.
                //   flip_count = 0 (no bits were flipped this cycle).
                // -------------------------------------------------------------
                data_out   <= data_in;
                flip_count <= 6'd0;
            end

        end
    end

endmodule
