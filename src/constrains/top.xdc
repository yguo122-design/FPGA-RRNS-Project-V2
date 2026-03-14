## --------------------------------------------------------------------
## Modified XDC for FPGA Multi-Algorithm Fault Tolerance Test System
## Target Board: Digilent Arty A7-100 (Rev. D/E)
## Clock: 100MHz
## --------------------------------------------------------------------

## 1. Clock Signal (100MHz)
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { clk_100m }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_100m }]

## 2. Global Reset (Active Low)
## Mapped to SW0 for manual control
set_property -dict { PACKAGE_PIN A8 IOSTANDARD LVCMOS33 } [get_ports { rst_n_i }]

## 3. Buttons (Input)
## Mapping (top_module.v / top_top):
## btn[0] -> Global Reset (Center Button, D9)
## btn[1] -> Start Decode (Up Button, C9)
## btn[2] -> Reserved (Left Button, B9)
## btn[3] -> Reserved (Right Button, B8)
## Note: Arty buttons are Active High (Press = 1)
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { btn[0] }]
set_property -dict { PACKAGE_PIN C9  IOSTANDARD LVCMOS33 } [get_ports { btn[1] }]
set_property -dict { PACKAGE_PIN B9  IOSTANDARD LVCMOS33 } [get_ports { btn[2] }]
set_property -dict { PACKAGE_PIN B8  IOSTANDARD LVCMOS33 } [get_ports { btn[3] }]

## 3b. Abort Button for top_fault_tolerance_test (BUG FIX P5)
## btn_abort -> Emergency FSM Abort (Left Button, B9, Active-High)
## When pressed, main_scan_fsm immediately returns to IDLE from any state.
## Provides hardware recovery from deadlock without power cycle.
## NOTE: B9 is shared with btn[2] above. Use ONLY ONE top-level module at a time.
##       For top_fault_tolerance_test builds, use this constraint.
##       For top_top builds, use btn[2] above instead.
set_property -dict { PACKAGE_PIN B9  IOSTANDARD LVCMOS33 } [get_ports { btn_abort }]

## 4. LEDs (Output)
## Mapping: led[0:3] to the 4 discrete LEDs on Arty
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

## 5. USB-UART Interface (Via JD Pmod Header)
## FPGA TX (uart_tx_pin) -> Connects to FTDI RX (Pin D10 / JD1)
## FPGA RX (uart_rx_pin) <- Connects to FTDI TX (Pin A9  / JD2)
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_tx_pin }]
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports { uart_rx_pin }]

## Note: gpio constraints removed as they are internally connected to led signals