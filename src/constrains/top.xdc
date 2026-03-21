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


create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_50mhz_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 41 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {u_fsm/u_engine/inj_out_a_latch[0]} {u_fsm/u_engine/inj_out_a_latch[1]} {u_fsm/u_engine/inj_out_a_latch[2]} {u_fsm/u_engine/inj_out_a_latch[3]} {u_fsm/u_engine/inj_out_a_latch[4]} {u_fsm/u_engine/inj_out_a_latch[5]} {u_fsm/u_engine/inj_out_a_latch[6]} {u_fsm/u_engine/inj_out_a_latch[7]} {u_fsm/u_engine/inj_out_a_latch[8]} {u_fsm/u_engine/inj_out_a_latch[9]} {u_fsm/u_engine/inj_out_a_latch[10]} {u_fsm/u_engine/inj_out_a_latch[11]} {u_fsm/u_engine/inj_out_a_latch[12]} {u_fsm/u_engine/inj_out_a_latch[13]} {u_fsm/u_engine/inj_out_a_latch[14]} {u_fsm/u_engine/inj_out_a_latch[15]} {u_fsm/u_engine/inj_out_a_latch[16]} {u_fsm/u_engine/inj_out_a_latch[17]} {u_fsm/u_engine/inj_out_a_latch[18]} {u_fsm/u_engine/inj_out_a_latch[19]} {u_fsm/u_engine/inj_out_a_latch[20]} {u_fsm/u_engine/inj_out_a_latch[21]} {u_fsm/u_engine/inj_out_a_latch[22]} {u_fsm/u_engine/inj_out_a_latch[23]} {u_fsm/u_engine/inj_out_a_latch[24]} {u_fsm/u_engine/inj_out_a_latch[25]} {u_fsm/u_engine/inj_out_a_latch[26]} {u_fsm/u_engine/inj_out_a_latch[27]} {u_fsm/u_engine/inj_out_a_latch[28]} {u_fsm/u_engine/inj_out_a_latch[29]} {u_fsm/u_engine/inj_out_a_latch[30]} {u_fsm/u_engine/inj_out_a_latch[31]} {u_fsm/u_engine/inj_out_a_latch[32]} {u_fsm/u_engine/inj_out_a_latch[33]} {u_fsm/u_engine/inj_out_a_latch[34]} {u_fsm/u_engine/inj_out_a_latch[35]} {u_fsm/u_engine/inj_out_a_latch[36]} {u_fsm/u_engine/inj_out_a_latch[37]} {u_fsm/u_engine/inj_out_a_latch[38]} {u_fsm/u_engine/inj_out_a_latch[39]} {u_fsm/u_engine/inj_out_a_latch[40]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 6 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {u_fsm/u_engine/inj_flip_a[0]} {u_fsm/u_engine/inj_flip_a[1]} {u_fsm/u_engine/inj_flip_a[2]} {u_fsm/u_engine/inj_flip_a[3]} {u_fsm/u_engine/inj_flip_a[4]} {u_fsm/u_engine/inj_flip_a[5]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 16 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {u_fsm/u_engine/sym_a_latch[0]} {u_fsm/u_engine/sym_a_latch[1]} {u_fsm/u_engine/sym_a_latch[2]} {u_fsm/u_engine/sym_a_latch[3]} {u_fsm/u_engine/sym_a_latch[4]} {u_fsm/u_engine/sym_a_latch[5]} {u_fsm/u_engine/sym_a_latch[6]} {u_fsm/u_engine/sym_a_latch[7]} {u_fsm/u_engine/sym_a_latch[8]} {u_fsm/u_engine/sym_a_latch[9]} {u_fsm/u_engine/sym_a_latch[10]} {u_fsm/u_engine/sym_a_latch[11]} {u_fsm/u_engine/sym_a_latch[12]} {u_fsm/u_engine/sym_a_latch[13]} {u_fsm/u_engine/sym_a_latch[14]} {u_fsm/u_engine/sym_a_latch[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 16 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {u_fsm/u_engine/u_dec_a/dec_out_a[0]} {u_fsm/u_engine/u_dec_a/dec_out_a[1]} {u_fsm/u_engine/u_dec_a/dec_out_a[2]} {u_fsm/u_engine/u_dec_a/dec_out_a[3]} {u_fsm/u_engine/u_dec_a/dec_out_a[4]} {u_fsm/u_engine/u_dec_a/dec_out_a[5]} {u_fsm/u_engine/u_dec_a/dec_out_a[6]} {u_fsm/u_engine/u_dec_a/dec_out_a[7]} {u_fsm/u_engine/u_dec_a/dec_out_a[8]} {u_fsm/u_engine/u_dec_a/dec_out_a[9]} {u_fsm/u_engine/u_dec_a/dec_out_a[10]} {u_fsm/u_engine/u_dec_a/dec_out_a[11]} {u_fsm/u_engine/u_dec_a/dec_out_a[12]} {u_fsm/u_engine/u_dec_a/dec_out_a[13]} {u_fsm/u_engine/u_dec_a/dec_out_a[14]} {u_fsm/u_engine/u_dec_a/dec_out_a[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 16 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[0]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[1]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[2]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[3]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[4]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[5]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[6]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[7]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[8]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[9]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[10]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[11]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[12]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[13]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[14]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_x_reg[0]_1409[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 4 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_dist_reg[0]_898[0]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_dist_reg[0]_898[1]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_dist_reg[0]_898[2]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_dist_reg[0]_898[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 4 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_dist_reg[9]_386[0]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_dist_reg[9]_386[1]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_dist_reg[9]_386[2]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/ch_dist_reg[9]_386[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 4 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {u_fsm/u_engine/u_dec_a/u_dec_2nrm/mid_dist_b_reg[0]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/mid_dist_b_reg[1]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/mid_dist_b_reg[2]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/mid_dist_b_reg[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 4 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {u_fsm/u_engine/u_dec_a/u_dec_2nrm/mid_dist_a_reg[0]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/mid_dist_a_reg[1]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/mid_dist_a_reg[2]} {u_fsm/u_engine/u_dec_a/u_dec_2nrm/mid_dist_a_reg[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 1 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list u_fsm/u_engine/u_comp_a/comp_result_a]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 1 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list u_fsm/u_engine/dec_timeout_flag]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list u_fsm/u_engine/dec_valid_a]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 1 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list u_fsm/u_engine/enc_out_a_latch]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 1 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list u_fsm/u_engine/eng_result_pass]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 1 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list u_fsm/u_engine/inject_en_latch]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_50mhz_BUFG]
