## 修改完成：所有 mark_debug 属性已移除

`decoder_2nrm.v` 现在是干净的 RTL 代码，没有任何 `mark_debug` 属性，可以正常综合。

---

## Vivado GUI 动态添加 ILA 探针的操作步骤

**第一步：Run Synthesis + Run Implementation（正常流程）**

**第二步：综合完成后，在 Vivado 中打开 Synthesized Design**
- Flow Navigator → Open Synthesized Design

**第三步：Set Up Debug（添加 ILA 探针）**
- 菜单：Tools → Set Up Debug
- 或在 Netlist 窗口中右键信号 → Mark Debug

**需要添加的关键信号（在 Netlist 中搜索）：**

| 信号名（综合后网表名）                          | 位宽     | 说明          | 期望值（无注入） |
| ------------------------------------ | ------ | ----------- | -------- |
| `u_dec_a/u_dec_2nrm/ch_x_reg[0]`     | 16-bit | ch0 x输出     | = sym_a  |
| `u_dec_a/u_dec_2nrm/ch_dist_reg[0]`  | 4-bit  | ch0 距离      | = 0      |
| `u_dec_a/u_dec_2nrm/ch_valid_reg[0]` | 1-bit  | ch0 valid   | 触发信号     |
| `u_dec_a/u_dec_2nrm/ch_x_reg[6]`     | 16-bit | ch6 x输出（对比） | ≠ sym_a  |
| `u_dec_a/u_dec_2nrm/ch_dist_reg[6]`  | 4-bit  | ch6 距离（对比）  | > 0      |

**触发条件：** `ch_valid_reg[0] == 1`（ch0 valid 时触发）

**第四步：Generate Bitstream → Program Device**

**第五步：ILA 抓取后，关键判断：**
- `ch_dist_reg[0] = 0` 且 `ch_x_reg[0] = sym_a` → Stage 3a2 计算正确，问题在 MLD 选择
- `ch_dist_reg[0] ≠ 0` → Stage 3a2 距离计算仍有时序问题（cr2→cr3→cr4 链超时）

请将 ILA 数据保存为 `src/scripts/iladata6.csv`，我将编写分析脚本。