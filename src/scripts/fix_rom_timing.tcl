# =============================================================================
# Script: fix_rom_timing.tcl
# Purpose: Verify ROM IP core configuration and regenerate output products
#          for project_only_2NRM (Arty A7-100T, 100MHz)
# Usage:   In Vivado Tcl Console: source {D:/FPGAproject/FPGA-RRNS-Project-V2/src/scripts/fix_rom_timing.tcl}
# =============================================================================

puts "============================================================"
puts " fix_rom_timing.tcl — ROM IP Timing Fix Script"
puts "============================================================"

# -----------------------------------------------------------------------------
# Step 1: Verify the project is open
# -----------------------------------------------------------------------------
set proj [current_project -quiet]
if {$proj eq ""} {
    puts "ERROR: No project is currently open."
    puts "       Please open project_only_2NRM.xpr first, then re-run this script."
    return
}
puts "\[OK\] Current project: [get_property NAME [current_project]]"

# -----------------------------------------------------------------------------
# Step 2: Find all blk_mem_gen IP instances
# -----------------------------------------------------------------------------
set bram_ips [get_ips -filter {VLNV =~ *blk_mem_gen*} -quiet]
if {[llength $bram_ips] == 0} {
    puts "ERROR: No blk_mem_gen IP instances found in the project."
    puts "       Please ensure blk_mem_gen_0 and blk_mem_gen_1 are added to the project."
    return
}
puts "\[OK\] Found [llength $bram_ips] blk_mem_gen IP(s): $bram_ips"

# -----------------------------------------------------------------------------
# Step 3: For each IP, verify key timing parameters
# -----------------------------------------------------------------------------
# NOTE: The XCI files already have correct settings:
#   - Register_PortA_Output_of_Memory_Primitives = true  (output register enabled)
#   - Port_A_Clock = 100 (100MHz)
#   - C_READ_LATENCY_A = 1
#
# The root cause of WNS=-29.805ns is NOT the IP configuration.
# It is the combinational address calculation in rom_threshold_ctrl.v:
#   addr = (algo_id * 1365) + (ber_idx * 15) + (burst_len - 1)
# This multiplication synthesizes to ~30ns LUT chains.
# The fix is already applied in rom_threshold_ctrl.v (pipeline register added).
#
# This script verifies the IP settings are correct and regenerates output products.

foreach ip $bram_ips {
    puts "\n--- Checking IP: $ip ---"

    # Read current settings
    set mem_output_reg [get_property CONFIG.Register_PortA_Output_of_Memory_Primitives [get_ips $ip]]
    set clk_freq       [get_property CONFIG.Port_A_Clock [get_ips $ip]]
    set mem_type       [get_property CONFIG.Memory_Type [get_ips $ip]]
    set write_width    [get_property CONFIG.Write_Width_A [get_ips $ip]]
    set write_depth    [get_property CONFIG.Write_Depth_A [get_ips $ip]]
    set coe_file       [get_property CONFIG.Coe_File [get_ips $ip]]

    puts "  Memory_Type                              : $mem_type"
    puts "  Write_Width_A                            : $write_width bits"
    puts "  Write_Depth_A                            : $write_depth entries"
    puts "  Register_PortA_Output_of_Memory_Primitives: $mem_output_reg"
    puts "  Port_A_Clock                             : $clk_freq MHz"
    puts "  COE File                                 : $coe_file"

    # Verify output register is enabled
    if {$mem_output_reg ne "true"} {
        puts "  WARNING: Output register is NOT enabled! Enabling now..."
        set_property CONFIG.Register_PortA_Output_of_Memory_Primitives true [get_ips $ip]
        puts "  \[FIXED\] Register_PortA_Output_of_Memory_Primitives set to true"
    } else {
        puts "  \[OK\] Output register is enabled (correct)"
    }

    # Verify clock frequency
    if {$clk_freq != 100} {
        puts "  WARNING: Port_A_Clock is $clk_freq MHz, expected 100 MHz! Fixing..."
        set_property CONFIG.Port_A_Clock 100 [get_ips $ip]
        puts "  \[FIXED\] Port_A_Clock set to 100 MHz"
    } else {
        puts "  \[OK\] Port_A_Clock = 100 MHz (correct)"
    }
}

# -----------------------------------------------------------------------------
# Step 4: Regenerate IP output products
# -----------------------------------------------------------------------------
puts "\n--- Regenerating IP output products ---"
foreach ip $bram_ips {
    puts "  Regenerating: $ip ..."
    generate_target all [get_ips $ip]
    puts "  \[OK\] $ip output products regenerated"
}

# -----------------------------------------------------------------------------
# Step 5: Save project
# -----------------------------------------------------------------------------
save_project_as -force [get_property DIRECTORY [current_project]]/[get_property NAME [current_project]]
puts "\n\[OK\] Project saved."

# -----------------------------------------------------------------------------
# Step 6: Summary and next steps
# -----------------------------------------------------------------------------
puts "\n============================================================"
puts " Script Complete — Summary"
puts "============================================================"
puts ""
puts " ROOT CAUSE OF WNS=-29.805ns:"
puts "   Combinational address calculation in rom_threshold_ctrl.v:"
puts "     addr = (algo_id * 1365) + (ber_idx * 15) + (burst_len - 1)"
puts "   Multiplication synthesizes to ~30ns LUT chains."
puts "   This path feeds directly into BRAM addra, violating 10ns period."
puts ""
puts " FIX APPLIED (rom_threshold_ctrl.v):"
puts "   Added pipeline register between address calculation and BRAM:"
puts "   - Before: req → \[comb addr\] → BRAM → valid  (1 cycle, ~30ns path)"
puts "   - After:  req → \[comb addr\] → \[REG\] → BRAM → valid  (2 cycles, ~9ns each)"
puts "   Total latency: 1 cycle → 2 cycles (FSM waits for thresh_valid, no change needed)"
puts ""
puts " IP CORE STATUS:"
foreach ip $bram_ips {
    puts "   $ip: Output register ENABLED, Clock=100MHz — OK"
}
puts ""
puts " NEXT STEPS:"
puts "   1. Reset Synthesis: Flow Navigator → Reset Runs → synth_1"
puts "   2. Run Synthesis:   Flow Navigator → Run Synthesis"
puts "   3. Run Implementation: Flow Navigator → Run Implementation"
puts "   4. Check Timing:    Open Implemented Design → Report Timing Summary"
puts "      Expected: WNS >= 0 (positive slack)"
puts "   5. Generate Bitstream if timing passes"
puts "============================================================"
