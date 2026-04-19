

Slide 1: Title and Candidate Information
- Hardware Acceleration for Cluster Fault Tolerance in Hybrid CMOS/non-CMOS Memories
- Candidate name, student ID, supervisor, institution, date
- One-sentence thesis statement: FPGA-validated comparison of RRNS and RS ECC under realistic cluster faults

Slide 2: Motivation and Problem Definition
- Hybrid CMOS/non-CMOS memories face spatially correlated cluster faults (burst errors)
- Traditional ECCs are mainly optimized for random independent bit errors
- Need hardware-validated evidence, not simulation-only claims, for practical ECC selection

Slide 3: Research Gap and Core Questions
- Prior RRNS work lacks unified multi-algorithm FPGA benchmarking
- No clear hardware quantification of parallel vs serial MLD trade-off
- Research questions:
- Which ECC is best for cluster fault tolerance?
- What are the latency/resource/power/storage trade-offs on real hardware?

Slide 4: Aims and Objectives
- Build an FPGA platform for fair ECC benchmarking
- Implement and compare 6 configurations:
- 2NRM-RRNS (Parallel), 2NRM-RRNS (Serial), 3NRM-RRNS, C-RRNS-MLD, C-RRNS-MRC, RS(12,4)
- Evaluate four dimensions:
- Fault tolerance, latency/throughput, resource utilization/power, storage efficiency

Slide 5: ECC Background and Design Space
- RRNS principle: residue-based redundancy, correction capability $t=\lfloor(n-k)/2\rfloor$
- C-RRNS: stronger correction but long codeword (61 bits)
- 3NRM-RRNS: shorter codeword (48 bits), still t=3, uses MLD
- 2NRM-RRNS: shortest codeword (41 bits), t=2, uses MLD
- RS(12,4): 48 bits, t=4 symbols, mature decoding ecosystem

Slide 6: Key Algorithm Parameters (One Summary Table)
- Codeword length: C-RRNS 61, 3NRM 48, RS 48, 2NRM 41
- Storage efficiency: 26.2%, 33.3%, 33.3%, 39.0%
- Decoding search complexity:
- C/3NRM: $\binom{9}{3}=84$
- 2NRM: $\binom{6}{2}=15$
- RS: algebraic decoding (Berlekamp-Massey/Chien/Forney)

Slide 7: Methodology Overview (Two-Phase Validation)
- Phase 1: MATLAB simulation to establish baseline behavior
- Phase 2: FPGA hardware implementation for physical verification
- Same encode-inject-decode-analyze loop across algorithms for fairness

Slide 8: FPGA Platform Architecture
- PC host + FPGA target (UART 921600 bps)
- Single-Algorithm-Build mode for clean resource/power comparison
- Unified encoder/decoder wrapper with compile-time algorithm selection
- End-to-end automated BER sweep with result packet upload

Slide 9: Probabilistic Fault Injection Engine (Main Innovation)
- BER sweep: 0% to 10%, 101 points, 100,000 samples/point
- Supports random single-bit and cluster burst injections
- Uses only two BRAMs with ROM-based thresholds/patterns
- Scalable sample count without changing hardware structure

Slide 10: Experimental Setup and Fairness Controls
- Device: Artix-7 xc7a100t, 50 MHz
- Same infrastructure and test conditions for all algorithms
- FPGA-MATLAB cross-validation performed under aligned injection model
- Note on LFSR correlation effects and how interpretation is controlled

Slide 11: Random Single-Bit BER Results
- FPGA and MATLAB curves are in close agreement (implementation validated)
- Low BER: all correcting algorithms near 100%
- Elevated BER ranking (observed): RS > 2NRM-Parallel > 3NRM > 2NRM-Serial ≈ C-RRNS-MLD
- C-RRNS-MRC degrades linearly (no correction capability)

Slide 12: Cluster Burst BER Results (Representative $L=12$)
- Burst scenario better reflects target memory fault model
- RS and C-RRNS-MLD show strongest resilience
- 3NRM better than 2NRM variants at this burst length
- Core insight: practical burst tolerance depends on residue/symbol field structure, not just nominal $t$

Slide 13: Maximum Tolerable Burst Length Comparison
- C-RRNS-MLD: 14
- RS(12,4): 13
- 3NRM-RRNS: 11
- 2NRM-RRNS-Parallel: 8
- 2NRM-RRNS-Serial: 7
- Conclusion: C-RRNS-MLD is best for extreme cluster-fault resilience

Slide 14: Latency and Throughput Results
- Fastest correcting decoder: 2NRM-Parallel (24 decoder cycles, 10.96 Mbps)
- RS is balanced (127 cycles, 6.02 Mbps)
- C-RRNS-MLD and 3NRM are much slower (sequential MLD candidate evaluation)
- 2NRM Parallel vs Serial shows strong acceleration effect (large latency reduction)

Slide 15: Resource Utilization and Power Results
- 2NRM-Parallel has highest LUT/FF cost (~51% LUT) and highest power (0.58 W)
- Other schemes stay low-resource (~2–7% LUT) and low-power (~0.216–0.242 W)
- Clear hardware trade-off: speed via parallelism vs area/power budget

Slide 16: Storage Efficiency Results
- Best: 2NRM-RRNS at 39.0% (41-bit codeword)
- Mid: 3NRM and RS at 33.3% (48-bit)
- Lowest: C-RRNS at 26.2% (61-bit)
- Storage-constrained systems benefit most from 2NRM designs

Slide 17: Overall Conclusions and Practical Recommendations
- No single algorithm dominates all metrics
- High reliability priority: C-RRNS-MLD or RS
- Latency + compact codeword priority: 2NRM-Parallel
- Resource-limited FPGA priority: 2NRM-Serial
- Best general-purpose balance and ecosystem maturity: RS(12,4)

Slide 18: Contributions, Limitations, and Future Work
- Contributions:
- Unified FPGA benchmark platform and probabilistic injector
- First hardware quantification of 2NRM parallel/serial MLD trade-off
- Comprehensive four-dimension benchmark
- Limitations:
- LFSR-based injection correlation and FPGA-estimated power (not ASIC)
- Future work:
- Independent random source hardware, larger datasets, ASIC migration, adaptive/hybrid ECC selection

Slide 19: Backup (Optional) - Why 3NRM Can Be Slower Than C-RRNS-MLD
- Both can process 84 triplets, but candidate count per triplet differs
- Small moduli in 3NRM create more valid periodic candidates to test
- Therefore total MLD workload and latency can exceed C-RRNS-MLD

Slide 20: Q&A
- One-line closing: “Thank you for listening. I welcome questions and feedback.”

If you want, I can also generate a second version optimized for a strict 10-minute defense (about 12 slides) and map each slide to speaking time (e.g., 30-60s each).