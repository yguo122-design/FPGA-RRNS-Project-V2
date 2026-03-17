// =============================================================================
// File: uart_rx_module.v
// Description: UART Receiver Module - 1x Center Sampling
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Design Ref: v1.63 Section 2.3.1
// Version: v1.1 (Rewrote oversampling logic - fixed critical bug)
//
// ─────────────────────────────────────────────────────────────────────────────
// BAUD RATE: 921,600 bps @ 100 MHz
//   BAUD_DIV = 100,000,000 / 921,600 = 108.5 → 109 (rounded)
//   Actual baud rate = 100,000,000 / 109 = 917,431 bps
//   Error = 0.45% (well within UART ±3% tolerance)
//
// SAMPLING STRATEGY: 1x Center Sampling
//   - On detecting the falling edge of the start bit, wait HALF_BIT (54)
//     clock cycles to align to the CENTER of the start bit.
//   - Then sample every BAUD_DIV (109) clock cycles to hit the center of
//     each subsequent data bit and the stop bit.
//   - This is the standard, most reliable UART RX implementation.
//   - No oversampling or majority voting needed at this baud rate.
//
// BUG FIX (v1.0 → v1.1):
//   v1.0 used a 16x oversampling architecture but the sample_pulse was
//   generated every BAUD_DIV (109) cycles instead of every BAUD_DIV/16 (~7)
//   cycles. This made sample_pulse a 1x signal, causing:
//     - START state to wait 16 full bit periods (instead of 0.5)
//     - DATA sampling to occur at wrong bit boundaries
//     - Complete receive failure at 921,600 bps
//   v1.1 removes the broken oversampling logic and uses correct 1x center
//   sampling with a half-bit alignment on start bit detection.
//
// FRAME FORMAT: 8N1 (8 data bits, no parity, 1 stop bit)
//   Total bits per frame: 1 start + 8 data + 1 stop = 10 bits
//   Bit order: LSB first
//
// INPUT SYNCHRONIZATION:
//   Two-stage flip-flop synchronizer on uart_rx_pin to prevent metastability.
// =============================================================================

`timescale 1ns / 1ps

module uart_rx_module (
    input  wire        clk_100m,     // 100 MHz system clock
    input  wire        sys_rst_n,    // Synchronized active-low reset
    output reg         rx_valid,     // Single-cycle pulse when a byte is received
    output reg  [7:0]  rx_data,      // Received byte (valid when rx_valid=1)
    output reg         rx_error,     // Framing error: stop bit was not HIGH
    input  wire        uart_rx_pin   // UART RX pin from board IO
);

    // =========================================================================
    // Parameters
    // =========================================================================
    // BAUD_DIV: number of clock cycles per bit period
    // 100,000,000 / 921,600 = 108.5 → rounded to 109
    localparam [6:0] BAUD_DIV  = 7'd109;

    // HALF_BIT: half a bit period, used to align sampling to bit center
    // after detecting the start bit falling edge.
    // 109 / 2 = 54 (integer division, slightly before center — acceptable)
    localparam [6:0] HALF_BIT  = 7'd54;

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    localparam [2:0]
        ST_IDLE    = 3'd0,   // Waiting for start bit (line HIGH)
        ST_START   = 3'd1,   // Start bit detected, aligning to bit center
        ST_DATA    = 3'd2,   // Receiving 8 data bits
        ST_STOP    = 3'd3,   // Receiving stop bit
        ST_CLEANUP = 3'd4;   // One-cycle cleanup before returning to IDLE

    // =========================================================================
    // Internal Signals
    // =========================================================================

    // Two-stage synchronizer for metastability protection
    (* ASYNC_REG = "TRUE" *)
    reg rx_sync1;
    reg rx_sync2;   // Synchronized RX signal (use this for logic)

    // FSM state register
    reg [2:0] state;

    // Baud rate counter: counts clock cycles within each bit period
    reg [6:0] baud_cnt;

    // Data shift register and bit counter
    reg [7:0] shift_reg;    // Shift register (LSB first)
    reg [2:0] bit_cnt;      // Counts received data bits (0~7)

    // =========================================================================
    // 1. Input Synchronizer (Two-Stage FF)
    // =========================================================================
    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rx_sync1 <= 1'b1;   // UART idle = HIGH
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= uart_rx_pin;
            rx_sync2 <= rx_sync1;
        end
    end

    // =========================================================================
    // 2. Main FSM: 1x Center Sampling
    // =========================================================================
    // Timing diagram for one byte (8N1):
    //
    //  Line: ─────┐ START │  D0  │  D1  │ ... │  D7  │ STOP │─────
    //             └───────┘      │      │     │      │      │
    //
    //  baud_cnt resets to 0 at each state transition.
    //
    //  ST_START: Wait HALF_BIT (54) cycles → sample at center of start bit
    //            (verify it's still LOW, then transition to ST_DATA)
    //
    //  ST_DATA:  Wait BAUD_DIV (109) cycles → sample at center of each data bit
    //            Repeat 8 times (bit_cnt 0~7)
    //
    //  ST_STOP:  Wait BAUD_DIV (109) cycles → sample at center of stop bit
    //            If HIGH → valid frame, assert rx_valid
    //            If LOW  → framing error, assert rx_error

    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state     <= ST_IDLE;
            baud_cnt  <= 7'd0;
            bit_cnt   <= 3'd0;
            shift_reg <= 8'd0;
            rx_valid  <= 1'b0;
            rx_data   <= 8'd0;
            rx_error  <= 1'b0;
        end else begin
            // Default: deassert single-cycle outputs
            rx_valid <= 1'b0;
            rx_error <= 1'b0;

            case (state)

                // =============================================================
                // IDLE: Wait for start bit (falling edge on rx_sync2)
                // Line is HIGH when idle. Start bit is LOW.
                // =============================================================
                ST_IDLE: begin
                    if (!rx_sync2) begin
                        // Falling edge detected → start bit beginning
                        // Reset baud counter and move to START alignment
                        baud_cnt <= 7'd0;
                        state    <= ST_START;
                    end
                end

                // =============================================================
                // START: Align to center of start bit
                // Wait HALF_BIT cycles, then verify start bit is still LOW.
                // If LOW  → valid start bit, begin data reception
                // If HIGH → false trigger (glitch), return to IDLE
                // =============================================================
                ST_START: begin
                    if (baud_cnt == HALF_BIT - 1'b1) begin
                        // Reached center of start bit
                        if (!rx_sync2) begin
                            // Confirmed LOW → valid start bit
                            // Reset counter for first data bit
                            baud_cnt <= 7'd0;
                            bit_cnt  <= 3'd0;
                            state    <= ST_DATA;
                        end else begin
                            // Line went HIGH → glitch, not a real start bit
                            state <= ST_IDLE;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 7'd1;
                    end
                end

                // =============================================================
                // DATA: Sample 8 data bits at center of each bit period
                // Wait BAUD_DIV cycles between samples.
                // Data is shifted in LSB first (standard UART).
                // =============================================================
                ST_DATA: begin
                    if (baud_cnt == BAUD_DIV - 1'b1) begin
                        // Center of current data bit → sample it
                        // Shift in from MSB side (LSB-first protocol):
                        // shift_reg[0] will hold bit0 after 8 shifts
                        shift_reg <= {rx_sync2, shift_reg[7:1]};
                        baud_cnt  <= 7'd0;

                        if (bit_cnt == 3'd7) begin
                            // All 8 data bits received → move to stop bit
                            state <= ST_STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 7'd1;
                    end
                end

                // =============================================================
                // STOP: Sample stop bit at center of stop bit period
                // Stop bit must be HIGH (1) for a valid frame.
                // =============================================================
                ST_STOP: begin
                    if (baud_cnt == BAUD_DIV - 1'b1) begin
                        if (rx_sync2) begin
                            // Valid stop bit (HIGH) → output received byte
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;
                        end else begin
                            // Framing error: stop bit is LOW
                            rx_error <= 1'b1;
                        end
                        baud_cnt <= 7'd0;
                        state    <= ST_CLEANUP;
                    end else begin
                        baud_cnt <= baud_cnt + 7'd1;
                    end
                end

                // =============================================================
                // CLEANUP: One extra cycle before returning to IDLE
                // Ensures rx_valid/rx_error are seen for exactly one cycle,
                // and prevents false re-triggering on the stop bit's trailing edge.
                // =============================================================
                ST_CLEANUP: begin
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule
