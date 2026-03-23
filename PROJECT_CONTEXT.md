

---

# PROJECT_CONTEXT.md - FPGA Multi-Algorithm Fault Tolerance Test System

## 1. Project Overview
*   **Goal**: Implement and compare 4 ECC algorithms (**2NRM-RRNS, 3NRM-RRNS, C-RRNS, RS**) on Xilinx Artix-7 (Arty A7-100T) to validate storage efficiency, error correction capability, and resource consumption.
*   **Target Frequency**: **100 MHz** (Single Clock Domain).
*   **Design Philosophy**: "Cache-and-Burst" mode (FPGA runs 91 BER points autonomously, then uploads full results), ROM-based error injection for timing closure, and Single-Algorithm-Build for precise resource reporting.
*   **Current Status**: Design Specification **v1.61/v1.63 Finalized**. Ready for Coding.

## 2. Critical Design Constraints (MUST FOLLOW)
*   **Reset Strategy**: **Asynchronous Reset, Synchronous Release**.
    *   Input: `rst_n_i` (Async).
    *   Internal: `sys_rst_n` (2-stage synchronizer output).
    *   All logic must use `sys_rst_n`.
*   **Clock Domain**: Single 100MHz clock. No CDC/FIFOs needed between internal modules. UART uses clock enable (`clk_en_16x`).
*   **UART Baud Rate**: **921,600 bps**.
    *   **Divider**: Fixed integer **109** (Resulting error: -0.45%, within ±2.5% tolerance).
    *   **Frame**: Big-Endian multi-byte fields.
*   **Memory Alignment**: Statistics BRAM width must be **176 bits (22 Bytes)** per point (21 Bytes data + 1 Byte reserved) to fit Artix-7 BRAM efficiently.
*   **Error Injection**: **ROM Look-Up Table (LUT)** strategy ONLY.
    *   NO dynamic shifters or modulo operators in FPGA.
    *   Boundary safety (W_valid) is guaranteed by PC-side `gen_rom.py` script pre-filling illegal addresses with 0.
*   **Build Mode**: **Single-Algorithm-Build**. Use `` `define `` macros to instantiate only ONE decoder core per synthesis run for accurate $F_{max}$ and resource reporting.

## 3. System Architecture & Data Flow
1.  **PC -> FPGA (Config)**: 12-Byte Binary Frame.
    *   Triggers seed locking and auto-starts 91-point BER scan.
    *   Params: `Algo_ID`, `Burst_Len` (1-15), `Error_Mode`, `Sample_Count`.
2.  **FPGA Internal (Auto-Scan)**:
    *   Locks random seed once per task (91 points).
    *   Loops 91 BER points (1% ~ 10%).
    *   Writes stats to Dual-Port BRAM (`mem_stats_array`).
    *   **TX_BUSY Lock**: Blocks new config writes during report transmission.
3.  **FPGA -> PC (Report)**: 2011-Byte Binary Frame (一次性大包).
    *   Header + Global Info (3B) + 91 Points × 22B + Checksum.
    *   Sent only after all 91 points complete.

## 4. Key Module Specifications

### 4.1 Top Level & Reset
*   **Module**: `top_top.v`
*   **Ports**: `clk_100m`, `rst_n_i`, `uart_rx`, `uart_tx`, `led[3:0]`.
*   **Reset Logic**: Instantiate `reset_sync` module to generate `sys_rst_n`.

### 4.2 UART Interface
*   **Modules**: `uart_rx_module`, `uart_tx_module`, `protocol_parser`.
*   **Config**: Divider = 109. 16x oversampling.
*   **Protocol**:
    *   Downlink Header: `0xAA 0x55`. Uplink Header: `0xBB 0x66`.
    *   Checksum: Byte-wise XOR of entire frame (Header to last data byte).

### 4.3 Control & FSM
*   **Module**: `ctrl_register_bank` & `main_fsm.v`.
*   **Atomicity**: `ctrl_register_bank` latches params on `cfg_update_pulse`.
*   **Protection**: Ignore new config if `tx_busy` is high.
*   **LED Mapping**:
    *   `led[0]`: Config OK (Wait Start).
    *   `led[1]`: Running (Scanning 0-90).
    *   `led[2]`: Sending Report.
    *   `led[3]`: Error (Watchdog/Deadlock).

### 4.4 Error Injection (ROM Based)
*   **Module**: `error_injector_unit`.
*   **ROM**: Depth 4096 (12-bit addr), Width 64-bit.
*   **Addr Gen**: `{algo_id[1:0], burst_len-1[3:0], random_offset[5:0]}`.
*   **Logic**: `data_out = data_in ^ rom_data[addr]`. No boundary checks needed in HW.

### 4.5 Statistics Memory
*   **Module**: `mem_stats_array`.
*   **Type**: Dual-Port Block RAM (`(* ram_style = "block" *)`).
*   **Width**: **176 bits** (22 Bytes).
*   **Depth**: 91 (Addr 0-90).
*   **Data Layout per Point**: `BER_Idx(1)` + `Success(4)` + `Fail(4)` + `Flip_Count(4)` + `Clk_Count(8)` + `Reserved(1)`.

### 4.6 Decoder Wrapper
*   **Module**: `decoder_wrapper`.
*   **Interface**: Standard AXI-Lite style (`start`, `busy`, `done`).
*   **Ports**: `algo_sel`, `valid_mask` (pass-through or ignored based on algo).
*   **Watchdog**: Reset decoder if `busy` stays high too long; signal FSM to skip point.

## 5. Existing Assets (Reference Only)
*   **Directory**: `src/algo_base/` contains verified Verilog for **2NRM-RRNS** and **3NRM-RRNS**.
*   **Usage**: Do NOT modify core algorithm logic unless fixing a bug. Use these as references for interface adaptation in `decoder_wrapper`.
*   **RS Algorithm**: Prefer Xilinx RS IP Core (with wrapper). Fallback to open-source core if IP unavailable.

## 6. Development Rules
1.  **No Hallucinated IPs**: When instantiating BRAM or FIFO, use Xilinx primitives (`RAMB18E1`) or XPM libraries with explicit parameters. Do not invent port names.
2.  **Bit-Width Strictness**: Always define parameters for widths (e.g., `localparam STATS_WIDTH = 176;`). Never hardcode magic numbers like `175` or `180`.
3.  **Timing Awareness**: If generating complex combinational logic (e.g., GF multiplication), explicitly ask: "Does this meet 100MHz? Should I add pipeline registers?"
4.  **File Structure**: Adhere strictly to the planned directory structure (`src/top`, `src/ctrl`, `src/io`, `src/mem`, `src/algo_wrapper`).
5.  **Verification**: After generating code, suggest a minimal Testbench scenario or Syntax Check command.

## 7. Immediate Action Plan
1.  **Setup**: Create project structure and `.xdc` constraints (100MHz clock, UART IOs, Reset false path).
2.  **Skeleton**: Generate `reset_sync`, `uart_tx/rx` (div=109), and `top_top` port map.
3.  **Core**: Implement `mem_stats_array` (176-bit) and `error_injector` (ROM placeholder).
4.  **FSM**: Code `main_fsm` with LED mapping and TX_BUSY lock.
5.  **Integration**: Wrap existing 2NRM/3NRM codes into `decoder_wrapper`.
6.  **Scripts**: Update `gen_rom.py` to output 22-byte aligned COE files.


## 8. Detailed Interface Definitions (External Files)
Do not guess port names or bit widths. Always refer to these specific files for exact signatures:
*   **Top Level Ports**: Read `@src/interfaces/top_ports.vh`
*   **UART Physical Layer**: Read `@src/interfaces/uart_interface.vh` (Note: Divider=109 is internal)
*   **Decoder Wrapper**: Read `@src/interfaces/decoder_wrapper_ports.vh`
*   **Memory Map**: See Section 4.5 (176-bit width, 91 depth).

**Rule**: When generating a module, first `@mention` the corresponding `.vh` file to ensure port matching.

---
