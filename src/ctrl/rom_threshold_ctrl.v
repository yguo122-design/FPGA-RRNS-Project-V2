// =============================================================================
// File: rom_threshold_ctrl.v
// Description: BER Threshold ROM Controller
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.2.4 (ROM Threshold Lookup)
// Version: v2.0  (Migrated from $readmemh to Vivado Block Memory Generator IP)
//
// ─────────────────────────────────────────────────────────────────────────────
// DESIGN OVERVIEW (Section 2.3.2.4):
//   This module provides the LFSR comparison threshold for each BER test point.
//   The threshold table is pre-computed by gen_rom.py and stored in Block RAM.
//   The Main Scan FSM queries this module at the start of each BER point to
//   obtain the 32-bit threshold integer used for error injection probability.
//
// ROM IP CORE (blk_mem_gen_0):
//   - Component:  blk_mem_gen_0  (Vivado Block Memory Generator v8.4)
//   - COE File:   src/ROM/threshold_table.coe
//   - Data Width: 32 bits
//   - Depth:      5460 entries  (4 * 91 * 15)
//   - Addr Width: 13 bits       (ceil(log2(5460)) = 13)
//   - Read Mode:  WRITE_FIRST with output register enabled
//   - Read Latency: 1 clock cycle (BRAM primitive register)
//   - ENA Pin:    Present (Use_ENA_Pin = true)
//   - WEA Pin:    Present but tied to 0 (ROM mode)
//   - DINA Pin:   Present but tied to 0 (ROM mode)
//   - No RSTA pin (reset not used)
//
// ADDRESS MAPPING (Must match gen_rom.py exactly):
//   Python formula:
//     addr = (algo_id * BER_POINTS * NUM_BURST_STEPS) + (ber_idx * NUM_BURST_STEPS) + (burst_len - 1)
//          = (algo_id * 91 * 15) + (ber_idx * 15) + (burst_len - 1)
//          = (algo_id * 1365)    + (ber_idx * 15)  + (burst_len - 1)
//
//   This is a LINEAR PACKED structure — NOT bit-concatenation.
//   Verilog must implement this arithmetic to match the Python script.
//
//   Address range: 0 ~ 5459 (4 * 91 * 15 = 5460 valid entries)
//   Physical ROM depth: 5460 (IP core configured exactly to this depth)
//
// TIMING (Request-Valid Handshake):
//   Cycle N:   req=1, address inputs stable → ena=1 sent to BRAM
//   Cycle N+1: valid=1, threshold_val contains the looked-up value
//   This single-cycle latency matches BRAM read characteristics at 100MHz.
//   (The IP core has "Register_PortA_Output_of_Memory_Primitives = true",
//    which adds exactly 1 register stage inside the BRAM primitive.)
//
// SAFETY GUARD:
//   If ber_idx >= 91 or burst_len == 0, threshold_val is forced to 0.
//   This prevents accidental injection from out-of-range inputs.
// =============================================================================

`include "rom_threshold_ctrl.vh"

module rom_threshold_ctrl (
    // -------------------------------------------------------------------------
    // Global Clock & Reset
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Request-Valid Handshake
    // -------------------------------------------------------------------------
    input  wire        req,
    // req=1: Address inputs are valid, perform ROM lookup.
    // Result appears on threshold_val one clock cycle later (valid=1).

    // -------------------------------------------------------------------------
    // Address Inputs (From Main Scan FSM)
    // -------------------------------------------------------------------------
    input  wire [`THRESH_ALGO_BITS-1:0]  algo_id,
    // Algorithm selector: 0=2NRM, 1=3NRM, 2=C-RRNS, 3=RS
    // Selects the correct 1365-entry ROM partition

    input  wire [`THRESH_BER_BITS-1:0]   ber_idx,
    // BER point index: 0~90 (maps to BER 1%~10% in steps of 0.1%)
    // Values >= 91 are treated as invalid (threshold forced to 0)

    input  wire [`THRESH_LEN_BITS-1:0]   burst_len,
    // Burst length L: 1~15. Value 0 is invalid (threshold forced to 0).
    // Address uses (burst_len - 1), mapping L=1->0, L=15->14.

    // -------------------------------------------------------------------------
    // Output
    // -------------------------------------------------------------------------
    output reg  [`THRESH_ROM_DATA_WIDTH-1:0] threshold_val,
    // 32-bit LFSR comparison threshold.
    // Valid one clock cycle after req=1.
    // Usage: if (lfsr_out < threshold_val) → trigger error injection

    output reg         valid
    // Asserted HIGH for one clock cycle when threshold_val is valid.
    // Deasserted when req=0 or after the valid cycle.
);

    // =========================================================================
    // Address Calculation (Linear Packed — Must Match gen_rom.py)
    // =========================================================================
    // Python: addr = (algo_id * 1365) + (ber_idx * 15) + (burst_len - 1)
    //
    // Verilog implementation uses arithmetic (not bit-concatenation) because
    // BER_POINTS=91 and BURST_STEPS=15 are not powers of 2.
    //
    // Intermediate widths:
    //   algo_id * 1365: max = 3 * 1365 = 4095 → needs 12 bits
    //   ber_idx * 15:   max = 90 * 15  = 1350 → needs 11 bits
    //   burst_len - 1:  max = 14       → needs 4 bits
    //   Total max addr: 4095 + 1350 + 14 = 5459 → needs 13 bits ✓

    // Constants matching gen_rom.py
    localparam ALGO_STRIDE = `THRESH_BER_POINTS * `THRESH_LEN_STEPS; // 101 * 15 = 1515
    localparam BER_STRIDE  = `THRESH_LEN_STEPS;                       // 15

    // Combinational address computation
    wire [`THRESH_ROM_ADDR_WIDTH-1:0] rom_addr_comb;
    wire addr_valid; // Asserted when all inputs are within legal range

    // Input validity check (Safety Guard):
    //   ber_idx must be 0~90 (< 91)
    //   burst_len must be 1~15 (non-zero)
    assign addr_valid = (ber_idx < `THRESH_BER_POINTS) && (burst_len != 4'd0);

    // Linear address calculation matching gen_rom.py formula:
    //   addr = (algo_id * 1365) + (ber_idx * 15) + (burst_len - 1)
    assign rom_addr_comb = addr_valid ?
        (({11'b0, algo_id} * ALGO_STRIDE) +
         ({6'b0, ber_idx}  * BER_STRIDE)  +
         ({9'b0, burst_len} - 13'd1))
        : 13'd0;

    // =========================================================================
    // TIMING FIX: Register the address before sending to BRAM
    // =========================================================================
    // ROOT CAUSE OF WNS = -29.805ns:
    //   The combinational address calculation involves two multiplications:
    //     algo_id * 1365  (ALGO_STRIDE)
    //     ber_idx  * 15   (BER_STRIDE)
    //   These multiplications synthesize to multi-level LUT chains with
    //   ~30ns propagation delay, which directly violates the 10ns clock period
    //   when the result is fed straight into the BRAM addra port.
    //
    // FIX: Insert one pipeline register stage between the combinational address
    //   calculation and the BRAM address input. This breaks the long path into:
    //   - Stage 1 (Cycle N):   Compute rom_addr_comb (combinational, ~30ns)
    //                          Register result into rom_addr_reg
    //   - Stage 2 (Cycle N+1): BRAM reads from rom_addr_reg (stable, <1ns)
    //                          BRAM output appears at Cycle N+2 (1-cycle BRAM latency)
    //   - Stage 3 (Cycle N+2): Output registered to threshold_val / valid
    //
    // TOTAL LATENCY CHANGE: 1 cycle → 2 cycles (req → valid)
    // FSM IMPACT: main_scan_fsm INIT_CFG state already waits for thresh_valid,
    //   so the extra cycle is absorbed transparently. No FSM changes needed.
    //
    // TIMING BUDGET PER STAGE (100MHz = 10ns period):
    //   Stage 1: LUT multiplication + adder tree ≈ 8~9ns → meets 10ns ✓
    //   Stage 2: BRAM address setup + read ≈ 1ns → meets 10ns ✓
    //   Stage 3: BRAM output register → output FF ≈ 1ns → meets 10ns ✓

    // Pipeline register: registered address and control signals
    reg [`THRESH_ROM_ADDR_WIDTH-1:0] rom_addr_reg;   // Registered address (Stage 1 output)
    reg                              req_reg;         // req delayed 1 cycle (aligns with addr_reg)
    reg                              addr_valid_reg;  // addr_valid delayed 1 cycle

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rom_addr_reg   <= {`THRESH_ROM_ADDR_WIDTH{1'b0}};
            req_reg        <= 1'b0;
            addr_valid_reg <= 1'b0;
        end else begin
            rom_addr_reg   <= rom_addr_comb;   // Register the computed address
            req_reg        <= req;
            addr_valid_reg <= addr_valid;
        end
    end

    // =========================================================================
    // BRAM IP Core Enable Signal
    // =========================================================================
    // Drive ena from the REGISTERED req (req_reg), not the raw req.
    // This ensures the address (rom_addr_reg) and enable (req_reg) are
    // both registered and arrive at the BRAM in the same cycle.
    //
    // NOTE: The IP core has 1-cycle read latency (output register enabled).
    //       ena must be asserted in the same cycle as the address.
    wire bram_ena;
    assign bram_ena = req_reg; // Use registered req to match registered address

    // =========================================================================
    // BRAM Output Wire
    // =========================================================================
    wire [`THRESH_ROM_DATA_WIDTH-1:0] bram_dout;

    // =========================================================================
    // blk_mem_gen_0 Instantiation (threshold_table ROM)
    // =========================================================================
    // Port mapping:
    //   clka  ← clk              (system clock, 100MHz)
    //   ena   ← bram_ena         (registered read enable)
    //   wea   ← 1'b0             (ROM mode: write always disabled)
    //   addra ← rom_addr_reg     (REGISTERED 13-bit address — TIMING FIX)
    //   dina  ← 32'h0            (ROM mode: write data unused)
    //   douta → bram_dout        (32-bit threshold value, 1-cycle BRAM latency)
    //
    // Read latency: 2 clock cycles total (1 addr pipeline + 1 BRAM register)
    //   Cycle N:   req=1, rom_addr_comb computed (combinational)
    //   Cycle N+1: rom_addr_reg stable → BRAM reads (ena=req_reg=1)
    //   Cycle N+2: bram_dout valid (BRAM output register)
    blk_mem_gen_0 u_thresh_rom (
        .clka  (clk),
        .ena   (bram_ena),
        .wea   (1'b0),
        .addra (rom_addr_reg),        // TIMING FIX: use registered address
        .dina  (32'h0000_0000),
        .douta (bram_dout)
    );

    // =========================================================================
    // Registered Control Path (Request-Valid Handshake, 2-cycle total latency)
    // =========================================================================
    // Pipeline alignment (all signals relative to original req):
    //   Cycle N:   req=1, addr_valid=X  (original inputs)
    //   Cycle N+1: req_reg=1, addr_valid_reg=X, rom_addr_reg stable → BRAM reads
    //   Cycle N+2: bram_dout valid → req_d2=1, addr_valid_d2=X → output here
    //
    // We need req and addr_valid delayed by 2 cycles to align with bram_dout.

    reg req_d2;        // req delayed by 2 cycles (aligns with BRAM output)
    reg addr_valid_d2; // addr_valid delayed by 2 cycles

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_d2        <= 1'b0;
            addr_valid_d2 <= 1'b0;
        end else begin
            req_d2        <= req_reg;        // Stage 2: req_reg → req_d2
            addr_valid_d2 <= addr_valid_reg; // Stage 2: addr_valid_reg → addr_valid_d2
        end
    end

    // =========================================================================
    // Output Assignment
    // =========================================================================
    // Combine BRAM output with safety guard:
    //   - If req_d2=1 and addr_valid_d2=1: output BRAM data (normal lookup)
    //   - If req_d2=1 and addr_valid_d2=0: output 0 (safety guard)
    //   - If req_d2=0: deassert valid, hold threshold_val

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            threshold_val <= `THRESH_ROM_DATA_WIDTH'h0;
            valid         <= 1'b0;

        end else begin

            if (req_d2 && addr_valid_d2) begin
                // Valid Request: Output BRAM data
                // bram_dout is valid at this point (2-cycle total latency)
                threshold_val <= bram_dout;
                valid         <= 1'b1;

            end else if (req_d2 && !addr_valid_d2) begin
                // Invalid Request (Safety Guard):
                // ber_idx >= 91 or burst_len == 0 → force threshold to 0.
                threshold_val <= `THRESH_ROM_DATA_WIDTH'h0;
                valid         <= 1'b1;

            end else begin
                // No Request: Deassert valid, hold threshold_val
                valid <= 1'b0;
            end

        end
    end

endmodule
