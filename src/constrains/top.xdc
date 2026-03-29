## --------------------------------------------------------------------
## XDC Constraints for FPGA Multi-Algorithm Fault Tolerance Test System
## Target Board: Digilent Arty A7-100 (Rev. D/E)
## Top Module  : top_fault_tolerance_test
## Clock       : 100MHz
## Last Updated: 2026-03-19 (v2.21 Bug #42 fix - removed wrong multicycle paths)
## --------------------------------------------------------------------

## 1. Clock Signal (100MHz)
## Verilog port: clk_sys
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk_sys]
## Plan B (50MHz functional verification via MMCM):
## The board oscillator is still 100MHz, but MMCM divides it to 50MHz.
## The XDC constraint must match the INPUT clock (100MHz = 10ns period).
## Vivado will automatically derive the 50MHz constraint for the MMCM output.
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk_sys]

## 2. Global Reset (Active Low)
## Verilog port: rst_n  ->  Mapped to SW0 (A8)
set_property -dict {PACKAGE_PIN A8 IOSTANDARD LVCMOS33} [get_ports rst_n]

## 3. Abort Button (Active High)
## Verilog port: btn_abort  ->  Left Button (B9)
## When pressed, main_scan_fsm immediately returns to IDLE from any state.
set_property -dict {PACKAGE_PIN B9 IOSTANDARD LVCMOS33} [get_ports btn_abort]

## 4. LED Status Bus (Active High, 4-bit)
## Verilog port: led_status[3:0]
##   led_status[0] -> cfg_ok  (FSM IDLE / config received)  -> LD0 (H5)
##   led_status[1] -> running (FSM RUN_TEST)                 -> LD1 (J5)
##   led_status[2] -> sending (FSM DO_UPLOAD)                -> LD2 (T9)
##   led_status[3] -> error   (FSM unexpected state)         -> LD3 (T10)
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {led_status[0]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {led_status[1]}]
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports {led_status[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led_status[3]}]

## 5. Reserved LED Bus (Grounded in RTL, 4-bit)
## Verilog port: led_reserved[3:0]
## RTL: assign led_reserved = 4'b0000 (all tied to GND)
## Mapped to RGB LED channels (LD4 R/G, LD5 R/G) - will not illuminate
##   led_reserved[0] -> LD4 Red  (G6)
##   led_reserved[1] -> LD4 Green(F6)
##   led_reserved[2] -> LD5 Red  (E1)
##   led_reserved[3] -> LD5 Green(F1)
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS33} [get_ports {led_reserved[0]}]
set_property -dict {PACKAGE_PIN F6 IOSTANDARD LVCMOS33} [get_ports {led_reserved[1]}]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports {led_reserved[2]}]
set_property -dict {PACKAGE_PIN F1 IOSTANDARD LVCMOS33} [get_ports {led_reserved[3]}]

## 6. USB-UART Interface
## Verilog port: uart_tx  ->  D10 (JD1, FPGA TX -> FTDI RX)
## Verilog port: uart_rx  ->  A9  (JD2, FPGA RX <- FTDI TX)
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_tx]
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33} [get_ports uart_rx]

## --------------------------------------------------------------------
## Timing Constraints
## --------------------------------------------------------------------

## False path on asynchronous reset (active-low, from SW0)
set_false_path -from [get_ports rst_n]

## False path on abort button (debounced in RTL, no timing constraint needed)
set_false_path -from [get_ports btn_abort]

## --------------------------------------------------------------------
## BUG #42 FIX: All multicycle path constraints REMOVED (2026-03-19)
## --------------------------------------------------------------------
## ROOT CAUSE: The multicycle path constraints were WRONG.
## They told Vivado these paths have 2 clock cycles, but they are all
## single-cycle paths. This caused Vivado to relax timing, allowing
## coeff_mod_s1d to capture wrong values (0 instead of correct value).
## Result: x_cand = ri + 257*0 = ri = r257 (wrong), dist = 5 (not 0).
## ILA data 7 confirmed: ch0_x = 0x0088 = r257, ch0_dist = 5.
## Mathematical proof: coeff_mod=0 → x_cand=136, dist(136,recv_r)=5 ✓
##
## All decoder pipeline stages use dont_touch registers with proper
## single-cycle timing. No multicycle paths are needed.
##
## Encoder multicycle paths also removed - encoder uses registered
## outputs that are stable for the full clock cycle.

## False path constraints for UART pins
set_false_path -from [get_clocks sys_clk_pin] -to [get_ports uart_tx]
set_false_path -from [get_ports uart_rx] -to [get_clocks sys_clk_pin]

## --------------------------------------------------------------------
## Bug #57 FIX REVERTED (2026-03-20, timing15.csv analysis)
## --------------------------------------------------------------------
## The set_property MAX_FANOUT XDC constraints were REMOVED because they
## caused WNS to worsen from -0.69ns to -0.95ns (timing15.csv).
## Root cause: forcing aggressive register replication caused placement
## congestion, increasing route delay more than the fanout reduction helped.
## The real problem is LOGIC DEPTH (% 257 = 5.06ns, % 61 = ~5ns), not
## fanout. The fix is 2-step decomposition in RTL (Bug #58), not XDC constraints.

## --------------------------------------------------------------------
## Bug #59 FIX: Targeted XDC MAX_FANOUT constraints (2026-03-20)
## --------------------------------------------------------------------
## timing16.csv (WNS = -0.69ns) shows Bug #58 was effective (WNS improved
## from -0.95ns to -0.69ns). Remaining violations are pure route delay:
##   coeff_raw_s1c_reg[3]_rep__0: fo=12, net delay 5.98-6.00ns (target=4)
##   x_mod55_step1_reg_reg[5]_rep__0: fo=5, net delay 5.74ns (target=4)
##   x_mod53_step1_reg_reg[8]_rep__3: fo=6, net delay 6.06ns (target=2)
##
## LESSON FROM BUG #57: Applying MAX_FANOUT to ALL registers simultaneously
## caused placement congestion. This time, we apply TARGETED constraints
## only to the specific registers that are still violating timing.
##
## NOTE: These constraints apply only to the decoder channel module instances.
## The -hierarchical flag with specific name patterns limits the scope.

set_property MAX_FANOUT 4 [get_cells -hierarchical -filter {NAME =~ *coeff_raw_s1c_reg*}]
set_property MAX_FANOUT 4 [get_cells -hierarchical -filter {NAME =~ *x_mod55_step1_reg_reg*}]
set_property MAX_FANOUT 2 [get_cells -hierarchical -filter {NAME =~ *x_mod53_step1_reg_reg*}]

## --------------------------------------------------------------------
## Decoder Pipeline Fanout Constraints (v2.4 -- Moved to Verilog Attributes)
## --------------------------------------------------------------------
## NOTE: set_max_fanout is NOT supported in XDC constraint files.
##   The fanout constraints have been moved to decoder_2nrm.v as in-code
##   Verilog attributes on the affected registers.

## --------------------------------------------------------------------
## ILA Debug Core Configuration
## --------------------------------------------------------------------
## ILA probes are added dynamically via Vivado GUI "Set Up Debug" after
## synthesis. Do NOT add create_debug_core commands here manually, as
## net names change with each synthesis run.
##
## Current ILA probe targets (for reference, add via GUI after synthesis):
##   ch_x_reg[0]    (16-bit): ch0 x output (should = sym_a when no injection)
##   ch_dist_reg[0]  (4-bit): ch0 distance (should = 0 when no injection)
##   ch_valid_reg[0] (1-bit): ch0 valid signal (use as trigger)
##   ch_x_reg[6]    (16-bit): ch6 x output (comparison channel)
##   ch_dist_reg[6]  (4-bit): ch6 distance (comparison channel)
##
## Trigger condition: ch_valid_reg[0] == 1
## Sample depth: 4096
##
## See docs/mark_debug_attributes.md for detailed ILA analysis guide.

## NOTE: ILA probes are added via Vivado GUI "Set Up Debug" after synthesis.
## Net names change with each synthesis run, so do not hardcode them here.

