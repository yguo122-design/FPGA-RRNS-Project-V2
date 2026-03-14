// =============================================================================
// File: protocol_parser.v
// Description: Protocol Parser Module (Optimized for Robustness)
// Version: v1.1
// =============================================================================

`include "protocol_parser.vh"

// Note: `DEFINE_PARSER_TYPES is now a no-op (kept for backward compatibility).
// State encoding uses `define macros (ST_IDLE, ST_WAIT_HDR_2, etc.) from protocol_parser.vh.
// State variables are plain reg [2:0] for Verilog-2001 compatibility.

// FIX: Removed duplicate 'output wire checksum_error' declaration.
// checksum_error is already included as the last port in `PROTOCOL_PARSER_PORTS macro.
// Adding it again here caused [Synth 8-87] "Port already declared" error.
module protocol_parser (
    `PROTOCOL_PARSER_PORTS
);

    // State machine declaration (Verilog-2001 compatible: reg [2:0] instead of typedef enum)
    reg [2:0] current_state, next_state;

    // Internal registers
    reg [7:0] checksum_calc;       // Renamed to avoid ambiguity
    reg [2:0] payload_byte_count;
    reg [31:0] sample_count_buffer;
    reg checksum_error_reg;

    // Assign debug output
    assign state_dbg = current_state;
    assign checksum_error = checksum_error_reg;

    // ---------------------------------------------------------
    // Combinational Logic: Next State Decision
    // ---------------------------------------------------------
    always @(*) begin
        next_state = current_state; // Default: Hold state
        case (current_state)
            `ST_IDLE:
                if (rx_valid && rx_byte == `FRAME_HEADER_BYTE1)
                    next_state = `ST_WAIT_HDR_2;

            `ST_WAIT_HDR_2:
                if (rx_valid) begin
                    if (rx_byte == `FRAME_HEADER_BYTE2)
                        next_state = `ST_READ_CMD;
                    else
                        next_state = `ST_IDLE; // Mismatch, restart
                end

            `ST_READ_CMD:
                if (rx_valid) begin
                    if (rx_byte == `CMD_ID_CONFIG)
                        next_state = `ST_READ_LEN;
                    else
                        next_state = `ST_IDLE; // Unknown command
                end

            `ST_READ_LEN:
                if (rx_valid) begin
                    if (rx_byte == `PAYLOAD_LEN_CONFIG)
                        next_state = `ST_READ_PAYLOAD;
                    else
                        next_state = `ST_IDLE; // Length mismatch
                end

            `ST_READ_PAYLOAD:
                // Only transition when we have received all 7 bytes (count 0~6)
                // payload_byte_count reaches 6 after receiving the 7th byte (index 6).
                // Once we receive the 7th byte, we move to CHECK_SUM.
                if (rx_valid && payload_byte_count == 3'd6)
                    next_state = `ST_CHECK_SUM;

            `ST_CHECK_SUM:
                if (rx_valid)
                    next_state = `ST_IDLE; // Always return to IDLE after checking

            default:
                next_state = `ST_IDLE;
        endcase
    end

    // ---------------------------------------------------------
    // Sequential Logic: State Register & Data Processing
    // ---------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= `ST_IDLE;
            checksum_calc <= 8'h0;
            payload_byte_count <= 3'd0;
            sample_count_buffer <= 32'd0;
            cfg_update_pulse <= 1'b0;
            cfg_algo_id <= 8'd0;
            cfg_burst_len <= 8'd0;
            cfg_error_mode <= 8'd0;
            cfg_sample_count <= 32'd0;
            checksum_error_reg <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // Default assignments
            cfg_update_pulse <= 1'b0;
            checksum_error_reg <= 1'b0;

            if (rx_valid) begin
                case (current_state)
                    `ST_IDLE: begin
                        // Start checksum with Header 1
                        checksum_calc <= rx_byte;
                    end

                    `ST_WAIT_HDR_2: begin
                        checksum_calc <= checksum_calc ^ rx_byte;
                    end

                    `ST_READ_CMD: begin
                        checksum_calc <= checksum_calc ^ rx_byte;
                    end

                    `ST_READ_LEN: begin
                        checksum_calc <= checksum_calc ^ rx_byte;
                        payload_byte_count <= 3'd0; // Reset counter for payload
                    end

                    `ST_READ_PAYLOAD: begin
                        checksum_calc <= checksum_calc ^ rx_byte;

                        // Capture Data based on current count (0 to 6)
                        case (payload_byte_count)
                            3'd0: cfg_burst_len <= rx_byte;
                            3'd1: cfg_algo_id   <= rx_byte;
                            3'd2: cfg_error_mode <= rx_byte;
                            3'd3: sample_count_buffer[31:24] <= rx_byte;
                            3'd4: sample_count_buffer[23:16] <= rx_byte;
                            3'd5: sample_count_buffer[15:8]  <= rx_byte;
                            3'd6: sample_count_buffer[7:0]   <= rx_byte;
                            default: ; // Should not happen
                        endcase

                        // Increment counter for next byte
                        if (payload_byte_count < 3'd6)
                            payload_byte_count <= payload_byte_count + 1'b1;
                        // When count reaches 6, next state is CHECK_SUM (no further increment needed)
                    end

                    `ST_CHECK_SUM: begin
                        if (checksum_calc == rx_byte) begin
                            // Checksum OK: latch sample_count and pulse cfg_update_pulse
                            cfg_update_pulse <= 1'b1;
                            cfg_sample_count <= sample_count_buffer;
                        end else begin
                            // Checksum Failed: signal error
                            checksum_error_reg <= 1'b1;
                        end
                    end

                    default: begin
                        checksum_calc      <= 8'h0;
                        payload_byte_count <= 3'd0;
                    end
                endcase
            end
        end
    end

endmodule