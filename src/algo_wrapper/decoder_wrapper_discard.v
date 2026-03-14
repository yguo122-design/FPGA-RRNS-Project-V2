// decoder_wrapper.v
// FPGA Multi-Algorithm Fault Tolerance Test System
// Design Ref: v1.63 Section 2.4.3
// Target: Artix-7 100T

module decoder_wrapper (
    input  wire        clk_100m,       // 100MHz system clock
    input  wire        sys_rst_n,      // Synchronized system reset
    
    // Control Interface (AXI-Lite style)
    input  wire        start_pulse,    // Start decoding one codeword
    output reg         busy,           // High during decoding
    output reg         done_pulse,     // High when finished
    output reg         decode_success, // 1: Success, 0: Fail
    
    // Data Path (64-bit RRNS/RS bus)
    input  wire [63:0] data_in,        // Received codeword
    input  wire [63:0] error_pattern,  // From ROM Injector
    output reg  [63:0] data_out,       // Corrected codeword
    
    // Algorithm Selection
    input  wire [2:0]  algo_id,        // Selects internal core
    input  wire [15:0] valid_mask      // For RS or specific NRM variants
);

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam WATCHDOG_TIMEOUT = 32'd1000000;  // 10ms @ 100MHz
    
    // FSM States
    localparam [2:0] 
        IDLE      = 3'b000,
        SETUP     = 3'b001,
        DECODING  = 3'b010,
        COMPLETE  = 3'b011,
        TIMEOUT   = 3'b100;
    
    // =========================================================================
    // Internal Signals
    // =========================================================================
    reg  [2:0]  state;
    reg  [31:0] watchdog_counter;
    wire        watchdog_timeout;
    reg  [63:0] data_corrupted;     // data_in XOR error_pattern
    reg         algo_valid;         // Selected algorithm enabled check
    
    // Watchdog timeout detection
    assign watchdog_timeout = (watchdog_counter == WATCHDOG_TIMEOUT);
    
    // =========================================================================
    // Watchdog Counter
    // =========================================================================
    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            watchdog_counter <= 32'd0;
        end else begin
            if (state == IDLE || state == COMPLETE || state == TIMEOUT) begin
                watchdog_counter <= 32'd0;
            end else if (!watchdog_timeout) begin
                watchdog_counter <= watchdog_counter + 32'd1;
            end
        end
    end
    
    // =========================================================================
    // Algorithm Valid Check
    // =========================================================================
    always @(*) begin
        algo_valid = valid_mask[algo_id];  // Check if selected algorithm is enabled
    end
    
    // =========================================================================
    // Main State Machine
    // =========================================================================
    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state <= IDLE;
            busy <= 1'b0;
            done_pulse <= 1'b0;
            decode_success <= 1'b0;
            data_out <= 64'd0;
            data_corrupted <= 64'd0;
        end else begin
            // Default: clear single-cycle signals
            done_pulse <= 1'b0;
            
            case (state)
                IDLE: begin
                    if (start_pulse && algo_valid) begin
                        state <= SETUP;
                        busy <= 1'b1;
                        data_corrupted <= data_in ^ error_pattern;
                    end
                end
                
                SETUP: begin
                    // In real implementation: setup algorithm specific parameters
                    state <= DECODING;
                end
                
                DECODING: begin
                    if (watchdog_timeout) begin
                        state <= TIMEOUT;
                        busy <= 1'b0;
                        decode_success <= 1'b0;
                    end else begin
                        // Temporary: simulate successful decode after some cycles
                        if (watchdog_counter == 32'd100) begin  // Short delay for testing
                            state <= COMPLETE;
                            decode_success <= 1'b1;
                            data_out <= data_in;  // Echo input for connectivity test
                        end
                    end
                end
                
                COMPLETE: begin
                    state <= IDLE;
                    busy <= 1'b0;
                    done_pulse <= 1'b1;
                end
                
                TIMEOUT: begin
                    state <= IDLE;
                    done_pulse <= 1'b1;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    // =========================================================================
    // Algorithm Instance Placeholder
    // =========================================================================
    // Future: Add algorithm instantiation based on algo_id
    // Example:
    // case (algo_id)
    //     3'b000: decoder_2nrm_mld instance
    //     3'b001: decoder_3nrm_mld instance
    //     3'b010: c_rrns_decoder instance
    //     3'b011: rs_decoder instance
    //     default: pass-through
    // endcase

endmodule