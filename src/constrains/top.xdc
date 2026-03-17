## --------------------------------------------------------------------
## XDC Constraints for FPGA Multi-Algorithm Fault Tolerance Test System
## Target Board: Digilent Arty A7-100 (Rev. D/E)
## Top Module  : top_fault_tolerance_test
## Clock       : 100MHz
## Last Updated: 2026-03-16 (Fixed port name mismatches)
## --------------------------------------------------------------------

## 1. Clock Signal (100MHz)
## Verilog port: clk_sys
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { clk_sys }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_sys }]

## 2. Global Reset (Active Low)
## Verilog port: rst_n  ->  Mapped to SW0 (A8)
set_property -dict { PACKAGE_PIN A8 IOSTANDARD LVCMOS33 } [get_ports { rst_n }]

## 3. Abort Button (Active High)
## Verilog port: btn_abort  ->  Left Button (B9)
## When pressed, main_scan_fsm immediately returns to IDLE from any state.
set_property -dict { PACKAGE_PIN B9  IOSTANDARD LVCMOS33 } [get_ports { btn_abort }]

## 4. LED Status Bus (Active High, 4-bit)
## Verilog port: led_status[3:0]
##   led_status[0] -> cfg_ok  (FSM IDLE / config received)  -> LD0 (H5)
##   led_status[1] -> running (FSM RUN_TEST)                 -> LD1 (J5)
##   led_status[2] -> sending (FSM DO_UPLOAD)                -> LD2 (T9)
##   led_status[3] -> error   (FSM unexpected state)         -> LD3 (T10)
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led_status[0] }]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led_status[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led_status[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led_status[3] }]

## 5. Reserved LED Bus (Grounded in RTL, 4-bit)
## Verilog port: led_reserved[3:0]
## RTL: assign led_reserved = 4'b0000 (all tied to GND)
## Mapped to RGB LED channels (LD4 R/G, LD5 R/G) - will not illuminate
##   led_reserved[0] -> LD4 Red  (G6)
##   led_reserved[1] -> LD4 Green(F6)
##   led_reserved[2] -> LD5 Red  (E1)
##   led_reserved[3] -> LD5 Green(F1)
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports { led_reserved[0] }]
set_property -dict { PACKAGE_PIN F6  IOSTANDARD LVCMOS33 } [get_ports { led_reserved[1] }]
set_property -dict { PACKAGE_PIN E1  IOSTANDARD LVCMOS33 } [get_ports { led_reserved[2] }]
set_property -dict { PACKAGE_PIN F1  IOSTANDARD LVCMOS33 } [get_ports { led_reserved[3] }]

## 6. USB-UART Interface
## Verilog port: uart_tx  ->  D10 (JD1, FPGA TX -> FTDI RX)
## Verilog port: uart_rx  ->  A9  (JD2, FPGA RX <- FTDI TX)
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]

## --------------------------------------------------------------------
## Timing Constraints
## --------------------------------------------------------------------

## False path on asynchronous reset (active-low, from SW0)
set_false_path -from [get_ports { rst_n }]

## False path on abort button (debounced in RTL, no timing constraint needed)
set_false_path -from [get_ports { btn_abort }]

## Input/Output delay constraints for UART pins (relaxed, UART is slow at 921600 bps)
set_input_delay  -clock sys_clk_pin -max 2.0 [get_ports { uart_rx }]
set_input_delay  -clock sys_clk_pin -min 0.5 [get_ports { uart_rx }]
set_output_delay -clock sys_clk_pin -max 2.0 [get_ports { uart_tx }]
set_output_delay -clock sys_clk_pin -min 0.5 [get_ports { uart_tx }]

## --------------------------------------------------------------------
## Decoder Pipeline Fanout Constraints (v2.4 -- Moved to Verilog Attributes)
## --------------------------------------------------------------------
## NOTE: set_max_fanout is NOT supported in XDC constraint files.
##   Vivado reports [Designutils 20-1307] when these commands are present.
##   The fanout constraints have been moved to decoder_2nrm.v as in-code
##   Verilog attributes on the affected registers:
##
##   (* dont_touch = "true", max_fanout = 4 *) reg [17:0] diff_mod_s1b;
##   (* dont_touch = "true", max_fanout = 4 *) reg [35:0] coeff_raw_s1c;
##   (* dont_touch = "true", max_fanout = 4 *) reg [17:0] coeff_mod_s1d;
##
##   This is the correct method for Vivado 2023.x and forces register
##   replication during synthesis, reducing Net Delay from ~6ns to <2ns.
