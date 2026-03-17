# Timing Optimization Report — 2026-03-16

**Project:** FPGA Multi-Algorithm Fault-Tolerant Test System (2NRM-RRNS)
**Target Device:** xc7a100tcsg324-1 (Arty A7-100, Artix-7)
**Clock:** 100 MHz (10 ns period)
**File Modified:** `src/algo_wrapper/decoder_2nrm.v`
**Author:** Cline (AI-assisted)

---

## 1. Problem Statement

Vivado Implementation failed with severe timing violations:

| Metric | Value |
|--------|-------|
| WNS (Worst Negative Slack) | **-28.829 ns** |
| Failing Endpoints | **981** |
| Critical Path Logic Levels | **52** |
| Critical Path Source | `u_fsm/u_engine/inj_out_a_latch_reg[13]/C` |
| Critical Path Destination | `u_fsm/u_engine/u_dec/a/u_dec_2nrm/ch9/distance_reg[0]/D` |

Root cause: `decoder_channel_2nrm_param` contained ~52 LUT levels of pure combinational logic in a single clock cycle (CRT reconstruction + 6x modular reduction + Hamming distance).

---

## 2. Optimization Iterations

### v2.0 — 3-Stage Pipeline (WNS: -28.829 ns → -18.957 ns)

**Problem:** 52-level LUT chain in one clock cycle.

**Fix:** Split into 3 registered pipeline stages:
- Stage 1: CRT reconstruction (MUX → diff_mod → coeff_mod → x_cand)
- Stage 2: 6x modular residues (x_cand % modulus[k])
- Stage 3: Hamming distance accumulation

**Latency change:** 2 cycles → 4 cycles

---

### v2.1 — 4-Stage Pipeline (WNS: -18.957 ns → -14 ns)

**Problem:** Stage 1 still contained ~30 LUT (CRT full chain), Logic Delay ~15 ns.

**Fix:** Split Stage 1 into 1a + 1b:
- Stage 1a: diff_raw subtraction only (~3 LUT)
- Stage 1b: x_cand multiply+add (~12 LUT)

**Latency change:** 4 cycles → 5 cycles

---

### v2.2 — 6-Stage Pipeline + Input Register Bank (WNS: -14 ns → -8.5 ns)

**Problem:** Net Delay ~11 ns due to r0..r5 fanout=27 (15 channels × 2 residues each).

**Fix:**
1. CRT split into 4 sub-stages (1a/1b/1c/1d), each with at most ONE expensive operation
2. Input register bank added at top-level `decoder_2nrm`: r0..r5 registered BEFORE broadcast to 15 channels, reducing fanout from 27 to 1 per channel. `(* keep = "true" *)` prevents merging.

**Latency change:** 5 cycles → 8 cycles (including input reg + MLD reg)

---

### v2.3 — 7-Stage Pipeline + dont_touch (WNS: -8.5 ns → -3.6 ns)

**Problem:** Stage 1d contained both modulo AND multiply (~18 LUT). XDC `set_max_fanout` not supported (`[Designutils 20-1307]`).

**Fix:**
1. Stage 1d split into 1d (modulo only) + 1e (multiply-add only)
2. All intermediate registers annotated with `(* dont_touch = "true" *)` to prevent stage merging
3. XDC `set_max_fanout` removed (invalid command)

**Latency change:** 8 cycles → 9 cycles

---

### v2.4 — Verilog Fanout Attributes (WNS: -3.6 ns, Net Delay reduced)

**Problem:** Net Delay still ~6 ns on `diff_mod_s1b`, `coeff_raw_s1c`, `coeff_mod_s1d`.

**Fix:** Added `(* dont_touch = "true", max_fanout = 4 *)` inline Verilog attributes on the three high-fanout registers. Vivado replicates these registers to keep fanout ≤ 4, reducing Net Delay from ~6 ns to <2 ns.

**Note:** `max_fanout` must be a Verilog attribute, NOT an XDC command.

---

### v2.5 — DSP48E1 Mapping Attempt (WNS: -3.6 ns, Logic Delay ~7.4 ns)

**Problem:** Logic Delay ~7.4 ns on Stage 1c and 1e multiplications (LUT carry chains).

**Fix attempt:** Added `(* use_dsp = "true" *)` on `coeff_raw_1c` and `x_cand_1e` wires.

**Result:** Vivado error `[Netlist 29-72] Incorrect value 'true'` — invalid attribute value.

---

### v2.6 — DSP48E1 Attribute Value Corrected (WNS: -3.6 ns)

**Problem:** `use_dsp = "true"` is not a valid Vivado enum value.

**Fix:** Changed to `(* use_dsp = "YES" *)` (valid values: `"YES"/"NO"/"LOGIC"/"SIMD"/"AUTO"`).

**Result:** DSP48E1 mapped successfully (58 DSP slices). However, DSP Final Report showed `AREG=0, BREG=0, MREG=0, PREG=0` — multiplications were still combinational (passing through DSP without internal pipeline registers).

---

### v2.7 — DSP48E1 Internal Pipeline Registers Enabled (WNS: Expected ≥ 0)

**Problem:** DSP48E1 mapped but AREG/BREG/MREG/PREG all = 0. Logic Delay still ~7 ns because data passes through DSP combinationally.

**Root cause:** Vivado only packs external registers INTO DSP48E1 internal registers (AREG/MREG/PREG) when the register is placed immediately before/after the multiply operator in an `always @(posedge clk)` block. A combinational `assign` wire cannot be packed.

**Fix:** Split Stage 1c and Stage 1e each into two sub-stages with explicit registered always blocks:

#### Stage 1c Restructure

```
Before (v2.6):
  assign coeff_raw_1c = diff_mod_s1b * P_INV;   // combinational
  always @(posedge clk) coeff_raw_s1c <= coeff_raw_1c;

After (v2.7):
  // Stage 1c_pre: DSP AREG
  always @(posedge clk) dsp_a_1c <= diff_mod_s1b;

  // Stage 1c: DSP MREG
  always @(posedge clk) coeff_raw_s1c <= dsp_a_1c * P_INV;
```

DSP mapping: `dsp_a_1c` → AREG=1, `coeff_raw_s1c` → MREG=1

#### Stage 1e Restructure

```
Before (v2.6):
  assign x_cand_1e = {23'b0, ri_s1d} + (P_M1 * coeff_mod_s1d);  // combinational
  always @(posedge clk) x_cand_16_s1e <= clamp(x_cand_1e);

After (v2.7):
  // Stage 1e_pre: DSP AREG + CREG
  always @(posedge clk) begin
    dsp_a_1e <= coeff_mod_s1d;   // AREG
    dsp_c_1e <= ri_s1d;          // CREG
  end

  // Stage 1e: DSP PREG (MAC mode: P = A*B + C)
  always @(posedge clk) begin
    x_full = {23'b0, dsp_c_1e} + (P_M1 * dsp_a_1e);
    x_cand_16_s1e <= clamp(x_full);   // PREG
  end
```

DSP mapping: `dsp_a_1e` → AREG=1, `dsp_c_1e` → CREG=1, `x_cand_16_s1e` → PREG=1

---

### v2.7a — Single always Block (Enable Alignment Fix)

**Problem:** Stage 1c 和 Stage 1e 的 AREG 和 MREG/PREG 分别在两个独立的 `always` 块中，Vivado 无法跨块识别 DSP 内部寄存器打包模式。

**Fix:** 将每个 DSP 阶段的输入寄存器（AREG/CREG）和输出寄存器（MREG/PREG）合并到**同一个 `always` 块**中：

```verilog
// Stage 1c: AREG + MREG in ONE always block
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dsp_a_1c <= 18'd0;          // AREG reset
        coeff_raw_s1c <= 36'd0;     // MREG reset
        ...
    end else begin
        dsp_a_1c <= diff_mod_s1b;           // AREG: latch input
        coeff_raw_s1c <= dsp_a_1c * P_INV;  // MREG: multiply (uses previous dsp_a_1c)
        ...
    end
end
```

**关键点：** 非阻塞赋值语义保证 `coeff_raw_s1c` 使用的是上一拍的 `dsp_a_1c`，时序正确。

**Latency change:** 11 cycles（不变，但 DSP 推断成功率提升）

---

### v2.7b — 48-bit Full-Precision Intermediate Register (DSP Port Width Alignment)

**Problem:** DSP Final Report 仍显示 `AREG=0, MREG=0, PREG=0`。根本原因：

1. **Stage 1c**: `coeff_raw_s1c` 定义为 `[35:0]`（36-bit），但 DSP48E1 的 P 端口是 48-bit。Vivado 看到位宽不匹配，无法将 `coeff_raw_s1c` 映射为 MREG。
2. **Stage 1e**: `x_cand_16_s1e` 定义为 `[15:0]`（16-bit），同样与 P 端口 48-bit 不匹配。`dsp_c_1e` 定义为 `[8:0]`（9-bit），与 C 端口 48-bit 不匹配。

**Fix:** 引入 48-bit 全精度中间寄存器，截断操作移到 DSP 外部的独立 FF：

#### Stage 1c 修改

```verilog
reg [17:0] dsp_a_1c;          // DSP AREG (18-bit A-port) ✓
reg [47:0] mult_res_1c_full;  // DSP MREG (48-bit P-port) ✓ -- NEW
reg [35:0] coeff_raw_s1c;     // External FF (truncation, outside DSP)

always @(posedge clk) begin
    dsp_a_1c         <= diff_mod_s1b[17:0];          // AREG
    mult_res_1c_full <= {12'd0, dsp_a_1c} * P_INV;  // MREG (48-bit)
    coeff_raw_s1c    <= mult_res_1c_full[35:0];      // External truncation
end
```

#### Stage 1e 修改

```verilog
reg [17:0] dsp_a_1e;          // DSP AREG (18-bit A-port) ✓
reg [47:0] dsp_c_1e;          // DSP CREG (48-bit C-port) ✓ -- CHANGED from 9-bit
reg [47:0] mac_res_1e_full;   // DSP PREG (48-bit P-port) ✓ -- NEW
reg [15:0] x_cand_16_s1e;     // External FF (truncation + clamp, outside DSP)

always @(posedge clk) begin
    dsp_a_1e        <= coeff_mod_s1d[17:0];              // AREG
    dsp_c_1e        <= {39'd0, ri_s1d};                  // CREG (48-bit zero-extend)
    mac_res_1e_full <= dsp_c_1e + ({30'd0, dsp_a_1e} * P_M1); // PREG (48-bit MAC)
    x_cand_16_s1e   <= (mac_res_1e_full > 48'd65535) ?   // External clamp
                       16'hFFFF : mac_res_1e_full[15:0];
end
```

**DSP Port Width Alignment:**

| Register | v2.7 Width | DSP Port | v2.7b Width | Match |
|----------|-----------|---------|------------|-------|
| `dsp_a_1c` | 18-bit | A-port (18-bit) | 18-bit | ✓ |
| `coeff_raw_s1c` | 36-bit | P-port (48-bit) | → `mult_res_1c_full` 48-bit | ✓ |
| `dsp_a_1e` | 18-bit | A-port (18-bit) | 18-bit | ✓ |
| `dsp_c_1e` | 9-bit | C-port (48-bit) | 48-bit | ✓ |
| `x_cand_16_s1e` | 16-bit | P-port (48-bit) | → `mac_res_1e_full` 48-bit | ✓ |

**Latency change:** 11 cycles → **13 cycles** (+2 for external truncation FFs)

---

## 3. Complete Pipeline Structure (v2.7b)

```
Cycle 0:  Input register bank (r0..r5 latched, start_r delayed)
Cycle 1:  Stage 1a     — diff_raw subtraction (~3 LUT)
Cycle 2:  Stage 1b     — diff_mod = diff_raw % P_M2 (~8 LUT)
Cycle 3:  Stage 1c_pre — dsp_a_1c = diff_mod_s1b  [DSP AREG]
Cycle 4:  Stage 1c     — coeff_raw_s1c = dsp_a_1c * P_INV  [DSP MREG]
Cycle 5:  Stage 1d     — coeff_mod = coeff_raw_s1c % P_M2 (~8 LUT)
Cycle 6:  Stage 1e_pre — dsp_a_1e = coeff_mod_s1d, dsp_c_1e = ri_s1d  [DSP AREG+CREG]
Cycle 7:  Stage 1e     — x_cand_16_s1e = ri + P_M1*coeff_mod  [DSP PREG, MAC]
Cycle 8:  Stage 2      — 6x modular residues (~8-10 LUT each, parallel)
Cycle 9:  Stage 3      — Hamming distance accumulation (~5-8 LUT)
Cycle 10: MLD output   — minimum distance selection + output register
```

**Total decoder latency: 11 clock cycles** (start → valid)

---

## 4. Optimization Summary Table

| Version | WNS | Key Technique | Latency |
|---------|-----|---------------|---------|
| Original | -28.829 ns | None (52-level LUT chain) | 2 cycles |
| v2.0 | -18.957 ns | 3-stage pipeline | 4 cycles |
| v2.1 | -14 ns | Stage 1 split (1a+1b) | 5 cycles |
| v2.2 | -8.5 ns | 4 CRT sub-stages + input reg bank (fanout fix) | 8 cycles |
| v2.3 | -3.6 ns | Stage 1d/1e split + dont_touch | 9 cycles |
| v2.4 | -3.6 ns | max_fanout Verilog attribute (Net Delay fix) | 9 cycles |
| v2.5 | -3.6 ns | use_dsp="true" (invalid, error) | 9 cycles |
| v2.6 | -3.6 ns | use_dsp="YES" (DSP mapped, AREG/MREG=0) | 9 cycles |
| v2.7 | -3.6 ns (pending) | DSP AREG+MREG+CREG+PREG enabled (single always block) | 11 cycles |
| v2.7a | -3.6 ns (pending) | AREG+MREG / AREG+CREG+PREG merged into single always block | 11 cycles |
| **v2.7b** | **Expected ≥ 0** | **48-bit full-precision MREG/PREG + enable alignment fix** | **13 cycles** |

---

## 5. Techniques Applied (Reference)

| Technique | Verilog Syntax | Effect |
|-----------|---------------|--------|
| Pipeline register | `always @(posedge clk) reg <= comb;` | Breaks long combinational path |
| Prevent stage merging | `(* dont_touch = "true" *)` | Forces register to remain |
| Fanout control | `(* dont_touch = "true", max_fanout = 4 *)` | Replicates register, reduces Net Delay |
| Input reg bank | `(* keep = "true" *) reg r0..r5` | Reduces fanout from 27 to 1 per channel |
| DSP mapping | `(* use_dsp = "YES" *)` on wire | Maps multiply to DSP48E1 |
| DSP AREG | Register before multiply in always block | Packs into DSP input register |
| DSP MREG/PREG | Register after multiply in always block | Packs into DSP output register |

---

## 6. Upper-Level Impact

**No changes required** in any module other than `decoder_2nrm.v`:

- `auto_scan_engine.v`: `DEC_WAIT` state polls `dec_valid_a && dec_valid_b` (not a fixed counter). The latency increase from 9 to 11 cycles is absorbed automatically.
- `decoder_wrapper.v`: Interface unchanged.
- `result_comparator.v`: Waits for `valid_in` — unaffected.
- Watchdog threshold: 10,000 cycles — far above 11-cycle latency.

---

## 7. Verification Steps

After applying v2.7, run in Vivado Tcl Console:

```tcl
reset_run synth_1
launch_runs synth_1 -wait
open_run synth_1
report_dsp -file dsp_report_v2.7.txt
report_timing_summary -file timing_summary_v2.7.txt
```

**Expected results:**
- DSP Final Report: `AREG=1`, `MREG=1` (Stage 1c); `AREG=1`, `CREG=1`, `PREG=1` (Stage 1e)
- Logic Delay per DSP stage: ~1 ns (vs ~7 ns in v2.6)
- WNS ≥ 0 (timing closure achieved)
