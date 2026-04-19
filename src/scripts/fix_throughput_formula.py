path = r'd:/FPGAproject/FPGA-RRNS-Project-V2/docs/dissertation/Hardware Acceleration for Cluster Fault Tolerance in Hybrid CMOS non CMOS Memories.md'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Find and replace the throughput formula section
old = r"""$$\text{Throughput} = \frac{16 \text{ bits}}{(T_{\text{enc}} + T_{\text{dec}}) \text{ cycles}} \times f_{\text{clk}}$$

where $T_{\text{enc}}$ and $T_{\text{dec}}$ are the encoder and decoder latencies in clock cycles, and $f_{\text{clk}} = 50 \text{ MHz}$. This definition captures the end-to-end processing rate for a single data word, which is the relevant metric for a memory read/write operation."""

new = r"""$$\text{Throughput} = \frac{16 \text{ bits}}{T_{\text{total}} \text{ cycles}} \times f_{\text{clk}}$$

where $T_{\text{total}}$ is the complete trial cycle count measured by the hardware (including data generation, encoder, error injection, decoder, result comparison, and FSM overhead), and $f_{\text{clk}} = 50 \text{ MHz}$. Note that $T_{\text{total}} > T_{\text{enc}} + T_{\text{dec}}$ for all algorithms due to additional overhead cycles. This definition captures the true end-to-end processing rate for a single data word, which is the relevant metric for a memory read/write operation."""

if old in content:
    content = content.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Fixed: Section 4.4 throughput formula updated to use T_total')
else:
    print('NOT FOUND')
    # Search for partial match
    idx = content.find('T_{\\text{enc}} + T_{\\text{dec}}')
    if idx >= 0:
        print(f'Found at {idx}:', repr(content[idx-20:idx+100]))
    else:
        idx = content.find('T_enc')
        if idx >= 0:
            print(f'Found T_enc at {idx}:', repr(content[idx-20:idx+100]))
