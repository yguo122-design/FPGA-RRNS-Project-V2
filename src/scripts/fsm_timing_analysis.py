"""
FSM Timing Analysis - Find the true root cause of 98% failure after Bug #38
============================================================================
Key data:
  - Avg_Clk_Per_Trial = 25 (from test_results_20260319_141457.csv)
  - comp_latency_a = 24 (from iladata5, after Bug #37)
  - After Bug #38: comp_latency_a should be 25 (one more ch_reg cycle)
  - Failure rate ~98% at ALL BER points including BER_Index=0 (no injection)

Goal: Find exactly where the timing mismatch is.
"""

print("=" * 70)
print("FSM CYCLE-BY-CYCLE TIMING ANALYSIS")
print("=" * 70)
print()

# ============================================================
# Step 1: Count FSM cycles precisely
# ============================================================
print("--- FSM State Sequence (from auto_scan_engine.v) ---")
print()
print("Cycle  State       Action")
print("-----  ----------  ----------------------------------------")
print("  1    CONFIG      latch params, inject_en_latch, prbs_start_gen=1")
print("  2    GEN_WAIT    prbs_valid=1: latch sym_a/b, enc_start=1")
print("  3    ENC_WAIT    [1st cycle] comp_start=1, enc_done_d1 starts")
print("                   enc_done=1 (encoder 1-cycle latency)")
print("                   enc_done_d1 <= enc_done = 1 (NBA, effective cycle 4)")
print("  4    ENC_WAIT    [2nd cycle] enc_done_d1=1: latch enc_out, -> INJ_WAIT")
print("  5    INJ_WAIT    cnt=0: injector pipeline starts")
print("  6    INJ_WAIT    cnt=1: injector pipeline running")
print("  7    INJ_WAIT    cnt=2: latch inj_out, dec_start=1, -> DEC_WAIT")
print("  8    DEC_WAIT    [entry] dec_start was issued at cycle 7")
print("  ...")
print("  8+N  DEC_WAIT    dec_valid_a=1 AND dec_valid_b=1 -> COMP_WAIT")
print("  9+N  COMP_WAIT   latch comp_result, -> DONE")
print(" 10+N  DONE        done=1, -> IDLE")
print()
print("Total trial cycles = 10 + N  (where N = DEC_WAIT duration)")
print()

# ============================================================
# Step 2: Calculate decoder pipeline latency
# ============================================================
print("--- Decoder Pipeline Latency (dec_start -> dec_valid_a) ---")
print()
print("decoder_2nrm.v pipeline stages:")
stages = [
    ("input_reg",    "r0..r5 registered, start_r delayed"),
    ("Stage 1a",     "diff_raw"),
    ("Stage 1b",     "diff_mod"),
    ("Stage 1c_pre", "DSP A/B input register"),
    ("Stage 1c_p2",  "side-channel stage 2"),
    ("Stage 1c_p3",  "side-channel stage 3"),
    ("Stage 1c",     "DSP PREG -> coeff_raw_s1c"),
    ("Stage 1d",     "coeff_mod"),
    ("Stage 1e_pre", "DSP A/B/C input register"),
    ("Stage 1e_p2",  "side-channel stage 2"),
    ("Stage 1e_p3",  "side-channel stage 3"),
    ("Stage 1e",     "DSP PREG -> x_cand_16_s1e"),
    ("Stage 2a",     "% 257, % 256"),
    ("Stage 2b",     "% 61, % 59"),
    ("Stage 2c",     "% 55, % 53 (valid_s2=1)"),
    ("Stage 3a",     "5 candidate distances (valid_s3a=1)"),
    ("Stage 3b",     "min selection -> x_out, distance, valid (ch_valid=1)"),
    ("ch_reg",       "Bug #38: ch_x_reg, ch_dist_reg, ch_valid_reg"),
    ("MLD-A reg",    "mid_dist_a/b_reg, mid_valid_reg"),
    ("MLD-B reg",    "decoder_2nrm: data_out, valid"),
    ("wrapper_reg",  "decoder_wrapper: dec_out_a, dec_valid_a"),
]

for i, (name, desc) in enumerate(stages):
    print(f"  Cycle {i+1:2d}: {name:12s} - {desc}")

total_dec_cycles = len(stages)
print()
print(f"Total decoder pipeline: {total_dec_cycles} cycles from dec_start to dec_valid_a")
print()

# ============================================================
# Step 3: Calculate comp_latency
# ============================================================
print("--- comp_latency Calculation ---")
print()
comp_start_cycle = 3   # issued at ENC_WAIT entry (cycle 3)
dec_start_cycle = 7    # issued at INJ_WAIT exit (cycle 7)
dec_valid_cycle = dec_start_cycle + total_dec_cycles
print(f"comp_start issued at FSM cycle: {comp_start_cycle}")
print(f"dec_start issued at FSM cycle:  {dec_start_cycle}")
print(f"dec_valid_a arrives at FSM cycle: {dec_start_cycle} + {total_dec_cycles} = {dec_valid_cycle}")
print()

# comp_latency = dec_valid_cycle - comp_start_cycle
# BUT: result_comparator counts from start=1 to valid_in=1
# start=1 at cycle 3, valid_in=1 at cycle dec_valid_cycle
# latency counter: starts at 0 when start=1, increments each cycle
# When valid_in=1: current_latency = lat_counter (before increment)
# So latency = dec_valid_cycle - comp_start_cycle - 1
# (because counter starts at 0 on the start cycle, not 1)
comp_latency_calc = dec_valid_cycle - comp_start_cycle - 1
print(f"comp_latency = {dec_valid_cycle} - {comp_start_cycle} - 1 = {comp_latency_calc}")
print("(counter starts at 0 on start cycle, so subtract 1)")
print()

# ============================================================
# Step 4: Calculate total trial cycles
# ============================================================
print("--- Total Trial Cycles ---")
print()
dec_wait_entry = 8
dec_wait_exit = dec_valid_cycle  # FSM exits DEC_WAIT when dec_valid_a=1
comp_wait_cycle = dec_wait_exit + 1
done_cycle = comp_wait_cycle + 1
total_cycles = done_cycle

print(f"DEC_WAIT entry: cycle {dec_wait_entry}")
print(f"DEC_WAIT exit (dec_valid_a=1): cycle {dec_wait_exit}")
print(f"COMP_WAIT: cycle {comp_wait_cycle}")
print(f"DONE: cycle {done_cycle}")
print(f"Total trial cycles: {total_cycles}")
print()

# ============================================================
# Step 5: Compare with observed data
# ============================================================
print("=" * 70)
print("COMPARISON WITH OBSERVED DATA")
print("=" * 70)
print()
print(f"Calculated comp_latency:    {comp_latency_calc}")
print(f"Observed comp_latency (ILA iladata5, Bug #37): 24")
print(f"Observed comp_latency (ILA iladata5, Bug #38): should be 25")
print()
print(f"Calculated total trial cycles: {total_cycles}")
print(f"Observed Avg_Clk_Per_Trial:    25")
print()

if comp_latency_calc == 25 and total_cycles == 28:
    print("MATCH: Calculated values match expected Bug #38 behavior")
    print("  comp_latency=25, total_cycles=28")
    print("  But test shows Avg_Clk_Per_Trial=25, NOT 28!")
    print()
    print("CRITICAL DISCREPANCY: Total cycles should be 28 but observed is 25!")
    print()
    print("This means the FSM is NOT waiting for dec_valid_a!")
    print("The FSM exits DEC_WAIT after only 25-10=15 cycles, NOT 20 cycles!")
    print()
    print("POSSIBLE CAUSES:")
    print("1. dec_valid_a is arriving EARLIER than expected (pipeline shorter)")
    print("2. The FSM is exiting DEC_WAIT via a different path (not dec_valid)")
    print("3. The decoder pipeline has fewer stages than counted")
elif comp_latency_calc == 24 and total_cycles == 27:
    print("This matches Bug #37 behavior (before Bug #38)")
    print("But test shows Avg_Clk_Per_Trial=25, NOT 27!")
    print()
    print("CRITICAL DISCREPANCY!")
else:
    print(f"Unexpected values: comp_latency={comp_latency_calc}, total={total_cycles}")

print()
print("=" * 70)
print("RECOUNT: How many pipeline stages does decoder_2nrm actually have?")
print("=" * 70)
print()

# Let me recount more carefully based on the actual code
print("Recounting from decoder_2nrm.v source code:")
print()
print("decoder_2nrm top-level input register:")
print("  start -> start_r (1 cycle delay)")
print("  r0..r5 -> registered r0..r5 (1 cycle delay)")
print("  So: start_r=1 at cycle 1 after dec_start")
print()
print("decoder_channel_2nrm_param pipeline (from start_r=1):")
print("  Stage 1a: valid_s1a = start_r (registered) -> valid at cycle 2")
print("  Stage 1b: valid_s1b = valid_s1a (registered) -> valid at cycle 3")
print("  Stage 1c_pre: valid_s1c_pre = valid_s1b (registered) -> valid at cycle 4")
print("  Stage 1c_p2: valid_s1c_p2 = valid_s1c_pre (registered) -> valid at cycle 5")
print("  Stage 1c_p3: valid_s1c_p3 = valid_s1c_p2 (registered) -> valid at cycle 6")
print("  Stage 1c: valid_s1c = valid_s1c_p3 (registered) -> valid at cycle 7")
print("  Stage 1d: valid_s1d = valid_s1c (registered) -> valid at cycle 8")
print("  Stage 1e_pre: valid_s1e_pre = valid_s1d (registered) -> valid at cycle 9")
print("  Stage 1e_p2: valid_s1e_p2 = valid_s1e_pre (registered) -> valid at cycle 10")
print("  Stage 1e_p3: valid_s1e_p3 = valid_s1e_p2 (registered) -> valid at cycle 11")
print("  Stage 1e: valid_s1e = valid_s1e_p3 (registered) -> valid at cycle 12")
print("  Stage 2a: valid_s2a = valid_s1e (registered) -> valid at cycle 13")
print("  Stage 2b: valid_s2b = valid_s2a (registered) -> valid at cycle 14")
print("  Stage 2c: valid_s2 = valid_s2b (registered) -> valid at cycle 15")
print("  Stage 3a: valid_s3a = valid_s2 (registered) -> valid at cycle 16")
print("  Stage 3b: valid = valid_s3a (registered) -> ch_valid=1 at cycle 17")
print()
print("decoder_2nrm top-level (Bug #38):")
print("  ch_reg: ch_valid_reg = ch_valid (registered) -> valid at cycle 18")
print()
print("MLD-A combinational + register:")
print("  mid_valid_comb = AND(ch_valid_reg[0..14]) -> combinational from ch_valid_reg")
print("  mid_valid_reg = mid_valid_comb (registered) -> valid at cycle 19")
print()
print("MLD-B register (decoder_2nrm output):")
print("  valid = mid_valid_reg (registered) -> dec_2nrm_valid=1 at cycle 20")
print()
print("decoder_wrapper output register:")
print("  valid = mux_valid = dec_2nrm_valid (registered) -> dec_valid_a=1 at cycle 21")
print()
print("TOTAL: dec_valid_a arrives 21 cycles after dec_start")
print()

dec_pipeline = 21
dec_valid_cycle2 = dec_start_cycle + dec_pipeline
comp_latency2 = dec_valid_cycle2 - comp_start_cycle - 1
total_cycles2 = dec_valid_cycle2 + 2  # COMP_WAIT + DONE

print(f"dec_valid_a at FSM cycle: {dec_start_cycle} + {dec_pipeline} = {dec_valid_cycle2}")
print(f"comp_latency = {dec_valid_cycle2} - {comp_start_cycle} - 1 = {comp_latency2}")
print(f"Total trial cycles = {dec_valid_cycle2} + 2 = {total_cycles2}")
print()
print(f"Observed comp_latency (iladata5, Bug #37): 24")
print(f"Observed Avg_Clk_Per_Trial: 25")
print()

if comp_latency2 == 24:
    print("comp_latency=24 MATCHES iladata5 Bug #37 observation!")
    print(f"But total_cycles={total_cycles2}, observed=25 -- MISMATCH!")
    print()
    print("WAIT: iladata5 was captured with Bug #37 bitstream (no ch_reg stage)")
    print("Without Bug #38 ch_reg: dec_pipeline = 21 - 1 = 20 cycles")
    dec_pipeline_no38 = 20
    dec_valid_no38 = dec_start_cycle + dec_pipeline_no38
    comp_lat_no38 = dec_valid_no38 - comp_start_cycle - 1
    total_no38 = dec_valid_no38 + 2
    print(f"  dec_valid_a at cycle: {dec_valid_no38}")
    print(f"  comp_latency = {comp_lat_no38}")
    print(f"  total_cycles = {total_no38}")
    print()
    if comp_lat_no38 == 24:
        print("  comp_latency=24 MATCHES iladata5 Bug #37!")
        print(f"  total_cycles={total_no38} -- but observed=25!")
        print()
        print("  STILL A MISMATCH: calculated total={}, observed=25".format(total_no38))

print()
print("=" * 70)
print("RESOLVING THE DISCREPANCY: Avg_Clk_Per_Trial=25 vs calculated")
print("=" * 70)
print()
print("The Avg_Clk_Per_Trial is calculated by Python as:")
print("  Avg_Clk_Per_Trial = Clk_Count / Total_Trials")
print("  = 25000 / 1000 = 25.00")
print()
print("This is the FPGA-measured clock count per trial.")
print("The FPGA counts clocks from eng_start to eng_done.")
print()
print("Let me re-examine what 'Clk_Count' actually measures...")
print("From auto_scan_engine.v: latency_cycles = comp_latency_a")
print("From mem_stats_array.v: clk_sum += latency_cycles")
print()
print("So Clk_Count = sum of comp_latency_a values!")
print("Avg_Clk_Per_Trial = avg(comp_latency_a) = 25.00")
print()
print("This means comp_latency_a = 25 in the current Bug #38 bitstream!")
print("(Not the total FSM cycles, but the decoder latency measurement)")
print()
print("So after Bug #38:")
print("  comp_latency_a = 25 (was 24 in Bug #37)")
print("  This confirms Bug #38 ch_reg stage IS working (+1 cycle)")
print()
print("Now: comp_latency=25 means dec_valid_a arrives at cycle 3+25+1=29")
print("  (comp_start at cycle 3, latency counter starts at 0)")
print("  dec_valid_a at FSM cycle = 3 + 25 + 1 = 29")
print("  Total trial = 29 + 2 = 31 cycles")
print()
print("But this is the DECODER LATENCY, not total trial cycles.")
print("The total trial cycles would be much larger than 25.")
print()
print("CONCLUSION: Avg_Clk_Per_Trial = avg(comp_latency_a) = 25")
print("This is consistent with Bug #38 being active (comp_latency went from 24 to 25)")
print()
print("=" * 70)
print("FINAL ROOT CAUSE ANALYSIS")
print("=" * 70)
print()
print("Given:")
print("  - MLD algorithm is 100% correct (Python simulation)")
print("  - ch_valid_reg IS correctly aligned with ch_x_reg/ch_dist_reg")
print("  - comp_latency_a = 25 (Bug #38 ch_reg is working)")
print("  - Failure rate ~98% at ALL BER points including no-injection")
print()
print("The 98% failure rate with correct algorithm and correct timing")
print("suggests the decoder is outputting the WRONG TRIAL's result.")
print()
print("HYPOTHESIS: The decoder is outputting the result of trial N-1")
print("when the comparator reads it during trial N.")
print()
print("This would happen if dec_valid_a is a LEVEL signal (stays HIGH)")
print("rather than a 1-cycle PULSE, causing the comparator to read")
print("the result from the previous trial.")
print()
print("OR: The decoder is outputting the result of trial N+1")
print("(one trial ahead), which would also cause ~98% failure.")
print()
print("Let's check: in decoder_2nrm.v MLD-B output:")
print("  valid <= mid_valid_reg;  // 1-cycle pulse")
print("  if (mid_valid_reg) begin")
print("    data_out <= ...;       // only updated when mid_valid_reg=1")
print("  end")
print()
print("In decoder_wrapper.v output register:")
print("  valid <= mux_valid;      // 1-cycle pulse")
print("  if (mux_valid) begin")
print("    data_out <= mux_data;  // only updated when mux_valid=1")
print("  end")
print()
print("CRITICAL ISSUE FOUND:")
print("  decoder_wrapper.valid is a 1-cycle pulse at cycle T")
print("  decoder_wrapper.data_out is updated at cycle T")
print("  result_comparator reads data_recov=dec_out_a at cycle T")
print()
print("  BUT: dec_out_a is the OUTPUT of decoder_wrapper's register")
print("  At cycle T, the register JUST updated (NBA semantics)")
print("  The combinational read of dec_out_a at cycle T sees the")
print("  VALUE THAT WAS REGISTERED AT CYCLE T-1 (previous value)")
print()
print("  Wait - this is standard synchronous design. The register")
print("  output is stable throughout cycle T (it was clocked in at")
print("  the rising edge of T). So dec_out_a at cycle T is the value")
print("  that was registered at the rising edge of T.")
print()
print("  Since both valid and data_out are in the SAME always block,")
print("  they are both registered at the SAME rising edge.")
print("  So when valid=1 at cycle T, data_out also has the new value.")
print("  This is CORRECT.")
print()
print("THEREFORE: The issue must be elsewhere.")
print()
print("NEW HYPOTHESIS: The decoder is computing the WRONG answer")
print("due to a pipeline stage count mismatch that causes it to")
print("process the WRONG input data.")
print()
print("Specifically: if the 'start' signal propagates through the")
print("pipeline but the DATA (r0..r5) takes a different number of")
print("cycles, the decoder will compute CRT using mismatched data.")
print()
print("Let's check: in decoder_2nrm.v top-level:")
print("  start_r <= start;  // 1-cycle delay")
print("  r0 <= r0_w;        // 1-cycle delay (same always block)")
print("  r1 <= r1_w;        // 1-cycle delay")
print("  ...")
print("  r5 <= r5_w;        // 1-cycle delay")
print()
print("All in the SAME always block -> start_r and r0..r5 are")
print("registered at the SAME clock edge. ALIGNED. OK.")
print()
print("In decoder_channel_2nrm_param Stage 1a:")
print("  valid_s1a <= start;  // start = start_r from top-level")
print("  diff_raw_s1a <= diff_raw;  // computed from r0..r5 (top-level registered)")
print("  ri_s1a <= ri;  // computed from r0..r5")
print("  r0_s1a <= r0; ... r5_s1a <= r5;")
print()
print("All in the SAME always block -> ALIGNED. OK.")
print()
print("CONCLUSION: All pipeline stages appear correctly aligned.")
print()
print("THE REAL QUESTION: Is the 98% failure rate actually a")
print("'stale data' problem or a 'wrong computation' problem?")
print()
print("From iladata5 analysis (Bug #38 report):")
print("  'MLD correct: 0/20' - hardware outputs wrong values")
print("  'decoder outputs ch6 k=0 result (dist=4) instead of ch0 (dist=0)'")
print()
print("This is a WRONG COMPUTATION problem, not a stale data problem.")
print("The decoder is computing the wrong answer for the CURRENT trial.")
print()
print("But Python simulation shows MLD is 100% correct...")
print()
print("RESOLUTION: The iladata5 was captured with Bug #37 bitstream")
print("(before Bug #38 ch_reg fix). The 'wrong channel selection'")
print("was due to inter-channel timing skew (Bug #38 root cause).")
print()
print("After Bug #38: ch_reg ensures all channels are read at the")
print("same stable cycle. But the test STILL shows 98% failure.")
print()
print("This means Bug #38 did NOT fix the problem.")
print("There must be ANOTHER timing issue that Bug #38 missed.")
