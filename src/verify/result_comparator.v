// =============================================================================
// File: result_comparator.v
// Description: Result Comparator with FIFO Alignment and Latency Measurement
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.3.4
// Version: v1.0
//
// ─────────────────────────────────────────────────────────────────────────────
// DESIGN OVERVIEW (Section 2.3.3.4):
//   This module solves the pipeline alignment problem between the PRBS generator
//   and the decoder output. When 'start' is asserted, the original data
//   (data_orig) is pushed into a shallow FIFO. When the decoder asserts
//   'valid_in' (after its pipeline latency), the corresponding original data
//   is popped from the FIFO and compared against the recovered data.
//
// FIFO MECHANISM:
//   - Depth: COMP_FIFO_DEPTH = 16 (covers up to 16 cycles of decoder latency)
//   - Write: start=1 → push data_orig into FIFO
//   - Read:  valid_in=1 → pop cached_orig from FIFO, perform comparison
//   - Implemented as a circular buffer with wr_ptr and rd_ptr
//   - Overflow protection: write blocked when FIFO is full
//   - Underflow protection: if valid_in=1 but FIFO empty → force FAIL
//
// LATENCY MEASUREMENT:
//   - Counter starts on 'start' assertion
//   - Counter stops and captures value on 'valid_in' assertion
//   - Measures the actual pipeline latency in clock cycles
//
// SAFETY CHECK (Critical):
//   Even if the decoder reports success (valid_in=1), if data_orig != data_recov,
//   the result is forced to FAIL. This catches silent decoder errors.
//
// READY SIGNAL:
//   Asserted when FIFO is not full, indicating the comparator can accept
//   a new 'start' pulse. The upstream FSM should check 'ready' before
//   asserting 'start' to prevent FIFO overflow.
// =============================================================================

`include "result_comparator.vh"
`timescale 1ns / 1ps

module result_comparator (
    // -------------------------------------------------------------------------
    // Global Clock & Reset
    // -------------------------------------------------------------------------
    input  wire                          clk,
    input  wire                          rst_n,

    // -------------------------------------------------------------------------
    // Input: Original Data (from PRBS Generator, synchronized with 'start')
    // -------------------------------------------------------------------------
    input  wire                          start,
    // start: Single-cycle pulse when a new test begins.
    // Triggers: (1) push data_orig into FIFO, (2) reset latency counter.

    input  wire [`COMP_DATA_WIDTH-1:0]   data_orig,
    // data_orig: The original 16-bit test symbol from PRBS generator.
    // Must be stable when start=1.

    // -------------------------------------------------------------------------
    // Input: Recovered Data (from Decoder, delayed by pipeline latency)
    // -------------------------------------------------------------------------
    input  wire                          valid_in,
    // valid_in: Decoder's valid output signal.
    // Triggers: (1) pop from FIFO, (2) compare, (3) capture latency.

    input  wire [`COMP_DATA_WIDTH-1:0]   data_recov,
    // data_recov: The 16-bit data recovered by the decoder.
    // Must be stable when valid_in=1.

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    output reg                           test_result,
    // test_result: 1=PASS, 0=FAIL.
    // Updated when valid_in=1. Holds value until next valid_in.

    output reg  [`COMP_LATENCY_WIDTH-1:0] current_latency,
    // current_latency: Measured pipeline latency in clock cycles.
    // Captured when valid_in=1. Holds value until next measurement.

    output wire                          ready
    // ready: HIGH when FIFO is not full (safe to assert start).
    // The upstream FSM should check this before sending a new test.
);

    // =========================================================================
    // 1. FIFO Implementation (Circular Buffer, Depth=16)
    // =========================================================================
    // The FIFO stores original data words while waiting for the decoder.
    // Write pointer (wr_ptr) advances on 'start'.
    // Read pointer (rd_ptr) advances on 'valid_in'.
    // FIFO count = wr_ptr - rd_ptr (modulo FIFO_DEPTH).

    // FIFO storage: 16 entries of 16-bit data
    reg [`COMP_DATA_WIDTH-1:0] fifo_mem [0:`COMP_FIFO_DEPTH-1];

    // FIFO pointers (one extra bit for full/empty distinction)
    // Using (ADDR_WIDTH+1)-bit pointers: MSB is the wrap-around flag
    reg [`COMP_FIFO_ADDR_WIDTH:0] wr_ptr; // Write pointer (5-bit: [4]=wrap, [3:0]=addr)
    reg [`COMP_FIFO_ADDR_WIDTH:0] rd_ptr; // Read pointer  (5-bit: [4]=wrap, [3:0]=addr)

    // FIFO status signals
    wire [`COMP_FIFO_ADDR_WIDTH:0] fifo_count;
    wire fifo_full;
    wire fifo_empty;

    assign fifo_count = wr_ptr - rd_ptr;
    assign fifo_full  = (fifo_count == `COMP_FIFO_DEPTH);
    assign fifo_empty = (fifo_count == 0);

    // ready: FIFO not full → safe to accept new start
    assign ready = !fifo_full;

    // FIFO write: push data_orig when start=1 and FIFO not full
    // FIFO read:  pop cached_orig when valid_in=1 and FIFO not empty
    wire fifo_wr_en = start    && !fifo_full;
    wire fifo_rd_en = valid_in && !fifo_empty;

    // -------------------------------------------------------------------------
    // FIFO Memory Write: SYNCHRONOUS ONLY (no async reset)
    // KEY CHANGE: Separating memory write into a pure posedge-clk block allows
    // Vivado to infer Distributed RAM (LUT-RAM) instead of 256 Flip-Flops.
    // Memory content is undefined after reset, but pointer reset (below)
    // ensures fifo_empty=1, so no uninitialized location is ever read.
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (fifo_wr_en) begin
            fifo_mem[wr_ptr[`COMP_FIFO_ADDR_WIDTH-1:0]] <= data_orig;
        end
    end

    // FIFO Read: Combinational (Distributed RAM supports async read)
    // fifo_rd_data is valid in the same cycle as rd_ptr, no extra latency.
    wire [`COMP_DATA_WIDTH-1:0] fifo_rd_data;
    assign fifo_rd_data = fifo_mem[rd_ptr[`COMP_FIFO_ADDR_WIDTH-1:0]];

    // -------------------------------------------------------------------------
    // FIFO Pointer Control: Async reset retained (plain registers, not RAM)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {(`COMP_FIFO_ADDR_WIDTH+1){1'b0}};
            rd_ptr <= {(`COMP_FIFO_ADDR_WIDTH+1){1'b0}};
        end else begin
            // Advance write pointer when data is pushed
            if (fifo_wr_en) begin
                wr_ptr <= wr_ptr + 1'b1;
            end
            // Advance read pointer when data is popped
            if (fifo_rd_en) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    // =========================================================================
    // 2. Latency Counter
    // =========================================================================
    // Counts clock cycles from 'start' to 'valid_in'.
    // Resets on each new 'start' pulse.
    // Captures value on 'valid_in'.

    reg [`COMP_LATENCY_WIDTH-1:0] lat_counter;
    reg                           lat_counting; // HIGH while counting

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lat_counter     <= {`COMP_LATENCY_WIDTH{1'b0}};
            lat_counting    <= 1'b0;
            current_latency <= {`COMP_LATENCY_WIDTH{1'b0}};
        end else begin
            if (start) begin
                // New test begins: reset and start counting
                lat_counter  <= {`COMP_LATENCY_WIDTH{1'b0}};
                lat_counting <= 1'b1;
            end else if (lat_counting) begin
                // Increment counter while waiting for decoder
                if (lat_counter < {`COMP_LATENCY_WIDTH{1'b1}}) begin
                    // Prevent overflow (saturate at max value)
                    lat_counter <= lat_counter + 1'b1;
                end
            end

            if (valid_in) begin
                // Decoder responded: capture latency and stop counting
                current_latency <= lat_counter;
                lat_counting    <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 3. Core Comparison Logic with Safety Check
    // =========================================================================
    // Triggered when valid_in=1.
    // Pops cached original data from FIFO and compares with recovered data.
    //
    // SAFETY CHECK (Section 2.3.3.4):
    //   The decoder may claim success (valid_in=1) but produce wrong data
    //   (e.g., miscorrection — correcting to a wrong codeword). This module
    //   performs an independent bit-exact comparison and forces FAIL if
    //   data_orig != data_recov, regardless of decoder's internal status.
    //
    // UNDERFLOW PROTECTION:
    //   If valid_in=1 but FIFO is empty (timing mismatch / system error),
    //   the result is forced to FAIL to prevent false PASS reporting.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            test_result <= 1'b0; // Default: FAIL (safe default)
        end else begin
            if (valid_in) begin
                if (fifo_empty) begin
                    // -------------------------------------------------------
                    // UNDERFLOW ERROR: valid_in arrived but no cached data.
                    // This indicates a timing mismatch (more valid_in pulses
                    // than start pulses). Force FAIL as a safety measure.
                    // -------------------------------------------------------
                    test_result <= 1'b0; // FAIL
                end else begin
                    // -------------------------------------------------------
                    // NORMAL COMPARISON:
                    //   cached_orig = fifo_rd_data (popped from FIFO)
                    //   is_match = (cached_orig == data_recov)
                    //
                    // SAFETY CHECK: Only PASS if bit-exact match.
                    // Even if decoder reports success, wrong data → FAIL.
                    // -------------------------------------------------------
                    test_result <= (fifo_rd_data == data_recov) ? 1'b1 : 1'b0;
                end
            end
            // else: hold test_result stable until next valid_in
        end
    end

endmodule
