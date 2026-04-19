title.png

# Hardware Acceleration for Cluster Fault Tolerance in Hybrid CMOS non CMOS Memories

# Abstract

Hybrid CMOS/non-CMOS memories are susceptible to cluster faults —
spatially correlated bursts of consecutive bit errors arising from the
dense packing of nanoscale devices — for which conventional
error-correcting codes (ECCs) designed for random errors are inadequate.
Redundant Residue Number System (RRNS) codes offer inherent cluster
fault tolerance, but existing implementations lack hardware-validated,
multi-algorithm performance benchmarks and have not quantified the
architectural trade-offs between different decoding strategies on
physical hardware.

This dissertation presents an FPGA-based hardware acceleration platform
that evaluates six ECC algorithm configurations — including parallel and
serial implementations of 2NRM-RRNS — on a Xilinx Artix-7 device. A
novel probabilistic fault injection engine enables statistically
rigorous BER testing (0–10%, 101 points, 100,000 samples per point)
under random single-bit and cluster burst fault models using only two
Block RAMs. A unified encoder/decoder wrapper architecture with
compile-time algorithm selection ensures fair, interference-free
resource comparison.

The key contributions of this work are: **(1)** a scalable FPGA
evaluation platform with a novel probabilistic fault injection engine
requiring only two Block RAMs and supporting arbitrary sample counts
without hardware modification; **(2)** the first hardware-based
empirical evaluation showing that C-RRNS-MLD achieves *no observed
decoding failures* across the full 0–10% BER range under cluster lengths
up to 14 within a test space of 100,000 samples per BER point; this
behaviour is consistent with its theoretical t=3 correction capability
and wide residue fields (6–7 bits each), though extreme alignment cases
are not exhaustively covered; **(3)** the first quantification of the
parallel vs. serial MLD resource-latency trade-off on physical hardware
— the parallel 2NRM-RRNS decoder achieves 43× lower latency (24 vs. 1047
clock cycles) at 13× higher LUT utilisation, and achieves the lowest
decode latency (24 cycles) among all evaluated configurations; and
**(4)** comprehensive hardware benchmarks across four evaluation
dimensions (fault tolerance, processing latency, resource utilisation,
and storage efficiency), supported by a unified wrapper architecture
ensuring fair cross-algorithm comparison under identical synthesis and
timing conditions.

\newpage

# Individual Contribution

This project was undertaken independently as an individual final-year
dissertation. All work described in this report was performed solely by
the author, Yuqi Guo (Student ID: 230184273), under the supervision of
Mr. Neil Powell at the University of Sheffield.

**MATLAB Simulation Phase**: In the first semester, a simulation model
was established to compare the decoding performance and resource
consumption of four algorithms: 2NRM-RRNS, 3NRM-RRNS, C-RRNS, and RS .
However, since the fault injection model used in this simulation was
inconsistent with that of the FPGA testbed implemented in the second
semester, a direct comparison was not feasible. Therefore, in the second
semester, a second round of simulation was conducted using a fault
injection model consistent with the FPGA testbed. The FPGA test results
and the MATLAB simulation results were then plotted and compared.The
results indicate that the FPGA test results are in **strong agreement**
with the MATLAB simulation results under the aligned fault injection
model. Minor deviations may arise from differences in random number
generation (LFSR vs. independent pseudo-random sequences) and finite
sample effects, but these do not affect the overall comparative
conclusions.

**FPGA Implementation Phase**: All Verilog/SystemVerilog source code
described in Chapter 3 was written by the author. This includes:

- Encoder modules for all four algorithm families.
- Decoder modules for all six configurations, including the novel
  parallel MLD pipeline and serial FSM.
- The probabilistic fault injection engine.
- The test infrastructure.
- The UART communication layer.

**PC-Side Software**: All Python scripts for test control, data
collection, and visualisation were written by the author.

**Hardware Resources**: The Xilinx Artix-7 xc7a100t FPGA (Arty A7-100T
development board) was used as the target platform. The Xilinx Vivado
2023.2 design suite was used for synthesis, implementation, and
bitstream generation under a standard academic licence. No external
datasets were used; all experimental data was collected by the author
using the platform described in this report.

The algorithms evaluated in this work are based on the published
research of Haron and Hamdioui \[1\] and Goh and Siddiqi \[2\], as cited
throughout the dissertation.

The author independently conducted the entire technical design,
implementation, and validation of the FPGA-based system presented in
this project. This includes the creation of a comprehensive high-level
design document exceeding 30 pages, detailing the system architecture,
module specifications, data flow, and control logic. Throughout the
implementation process, the author identified, analyzed, and resolved
over 100 bugs, demonstrating hands-on debugging and problem-solving
capabilities. While AI-assisted tools were employed solely to improve
language clarity, all critical technical decisions, coding, testing, and
verification were carried out by the author. The high-level design
documentation and detailed debugging logs serve as tangible evidence of
the author’s direct contributions and the independent development of the
project.

\newpage

# Acknowledgement

I would like to express my sincere gratitude to my project supervisor,
Mr. Neil Powell, for his invaluable guidance, encouragement, and
constructive feedback throughout the duration of this project. His
expertise in digital systems design and his patient support during the
FPGA implementation phase were instrumental in shaping both the
technical direction and the quality of this work. I am particularly
grateful for his willingness to engage with the detailed hardware
debugging challenges encountered during the development of the fault
injection platform, and for his insightful comments on the interim
report that helped focus the scope of the final dissertation.

I would also like to thank Dr. Mohammad Eissa, the second marker for
this project, for his time and effort in reviewing my work during this
project.

Finally, I would like to thank my family for their unwavering support
and encouragement throughout my studies at the University of Sheffield.

\newpage

# Chapter 1 Introduction

## 1.1 Background

The relentless scaling of CMOS transistor geometry and the emergence of
non-CMOS nanodevices have opened the prospect of hybrid CMOS/non-CMOS
memories capable of storing data at densities approaching 1 Tbit/cm²
\[1\]. In these hybrid architectures, arrays of nanowire crossbars are
fabricated on top of nanoscale CMOS circuits. At each crosspoint, a
two-terminal nanodevice — such as a single-electron junction, organic
molecule, or phase-change material — serves as a single-bit memory cell.
The CMOS layer performs peripheral functions (encoding, decoding,
sensing, and global interconnection), while the nanoscale crossbar
provides ultra-high-density storage.

Despite their extraordinary capacity potential, hybrid memories are
inherently susceptible to two categories of faults. First,
**manufacturing defects** arise from the imprecision of top-down
fabrication techniques (e.g., extreme ultraviolet lithography,
nanoimprint) and the immaturity of bottom-up self-assembly processes,
leading to broken nanowires, missing nanodevices, and misaligned
interface pins. Second, **transient faults** occur during operation due
to the reduced signal-to-noise ratio caused by lower supply voltages and
smaller capacitances at nanoscale dimensions. Charged-based non-CMOS
nanodevices are particularly vulnerable because they require only a
small voltage perturbation to change their internal state.

A critical characteristic of these faults is their **spatial
correlation**: because nanodevices are densely packed and closely
interconnected, a single fault event can propagate to affect several
contiguous memory cells, resulting in **cluster faults** — spatially
correlated bursts of multiple consecutive bit errors. In the literature,
the terms *cluster faults*, *cluster errors*, and *burst errors* are
used interchangeably to describe this phenomenon; this dissertation
adopts the term **cluster faults** (following the terminology of Haron
and Hamdioui \[1\]) when referring to the fault model, and **burst
errors** or **burst injection** when referring specifically to the fault
injection mechanism used in the evaluation platform. This fault model is
fundamentally different from the independent random bit errors assumed
by conventional error-correcting codes (ECCs) such as Hamming codes, BCH
codes, and Euclidean Geometry codes, which have been widely applied to
hybrid memories \[6–11\] but were designed for random, uncorrelated
errors.

The Redundant Residue Number System (RRNS) was identified by Haron and
Hamdioui \[1\] as a particularly suitable ECC for cluster fault
tolerance in hybrid memories. Unlike conventional ECCs, RRNS operates on
residue representations of data, where each residue is computed
independently with respect to a different modulus. A cluster fault that
corrupts a contiguous block of bits will typically corrupt only a small
number of residues (since each residue occupies a contiguous bit field),
regardless of the burst length. This property makes RRNS inherently
well-suited for cluster fault correction.

However, the conventional RRNS (C-RRNS) implementation incurs
significant storage overhead: for 16-bit data, C-RRNS requires a 61-bit
codeword — 27.1% longer than the 48-bit Reed-Solomon (RS) codeword for
the same data width. This overhead is a direct consequence of the
requirement that redundant moduli must be larger than non-redundant
moduli, which forces the use of large integers and long residue fields.
Reducing this overhead while maintaining competitive error correction
capability is identified as an open challenge in the literature \[8\].

To address this limitation, Haron and Hamdioui \[1\] proposed two
modified RRNS variants — **Three Non-Redundant Moduli RRNS (3NRM-RRNS)**
and **Two Non-Redundant Moduli RRNS (2NRM-RRNS)** — that use smaller
redundant moduli to achieve shorter codewords. These variants require
Maximum Likelihood Decoding (MLD) to resolve the decoding ambiguity
introduced by the violation of the conventional moduli ordering rule,
but offer significant advantages in storage efficiency and decoding
speed.

While other advanced ECC schemes have been considered for hybrid memory
protection, each exhibits limitations in the cluster fault context.
Low-Density Parity-Check (LDPC) codes and Turbo codes offer excellent
random error correction performance but incur high decoding complexity
and iterative latency that is incompatible with the low-latency access
requirements of memory systems \[8\]. BCH codes, though
hardware-efficient, are similarly optimised for random rather than
spatially correlated errors. Furthermore, existing FPGA implementations
of RRNS-based ECC \[3\] have focused on single-algorithm implementations
without systematic multi-algorithm comparison, and no prior work has
quantified the resource-latency trade-off between parallel and
sequential MLD architectures on physical hardware. This work addresses
these gaps directly.

While the theoretical properties of these algorithms have been
established through MATLAB simulation \[1\], their practical feasibility
on hardware platforms — including resource utilisation, timing
characteristics, and actual BER performance under realistic fault
injection — has not been comprehensively evaluated. This gap motivates
the present work.

## 1.2 Aims and Objectives

The primary aim of this project is to design and implement an FPGA-based
hardware acceleration platform for evaluating the fault tolerance
performance of multiple ECC algorithms under realistic cluster fault
conditions, and to use this platform to provide a comprehensive,
hardware-validated comparison of the 2NRM-RRNS, 3NRM-RRNS, C-RRNS, and
RS(12,4) algorithms.

The specific objectives are:

1.  **Algorithm Validation**: Quantitatively evaluate the error
    correction capability and performance advantages of 3NRM-RRNS and
    2NRM-RRNS codes through both MATLAB simulation and FPGA hardware
    implementation, with specific focus on cluster fault tolerance
    compared to C-RRNS and RS codes.
2.  **Hardware Implementation**: Design and implement efficient
    encoder/decoder architectures for all four coding schemes (RS,
    C-RRNS, 3NRM-RRNS, 2NRM-RRNS) using Verilog HDL on a Xilinx Artix-7
    FPGA (Arty A7-100T development board).
3.  **Fault Injection Platform**: Develop a novel probabilistic fault
    injection engine capable of evaluating algorithm performance under
    both random single-bit and cluster burst fault models, with
    configurable burst lengths (1–15 bits) and BER sweep from 0% to 10%.
4.  **Performance Benchmarking**: Conduct comprehensive performance
    analysis including:
    - BER vs. decode success rate under two fault injection scenarios
    - Encoder and decoder processing latency (clock cycles)
    - FPGA resource utilisation (LUT, FF, DSP, BRAM)
    - Storage efficiency (codeword length vs. data width)
5.  **Architectural Exploration**: Implement the 2NRM-RRNS decoder in
    both parallel (15-channel MLD pipeline) and serial (sequential FSM)
    architectures to directly quantify the resource-latency trade-off of
    parallel MLD.

## 1.3 Expected Contributions

The expected contributions of this work are:

- **Comprehensive hardware-validated performance characterisation** of
  novel RRNS variants (2NRM-RRNS, 3NRM-RRNS) under realistic cluster
  fault models on an FPGA platform.
- **A novel probabilistic fault injection engine** that enables
  statistically rigorous BER testing with arbitrary sample counts using
  minimal hardware resources.
- **A novel parallel vs. serial MLD comparison** for the 2NRM-RRNS
  algorithm, providing direct quantification of the resource-latency
  trade-off.
- **Open-source Verilog implementations** of optimised RRNS
  encoder/decoder architectures with a unified, extensible wrapper
  interface.
- **Benchmark data** comparing RRNS approaches with RS codes across four
  evaluation dimensions: fault tolerance, processing latency, resource
  utilisation, and storage efficiency.

## 1.4 Report Structure

The remainder of this dissertation is organised as follows:

- **Chapter 2** provides the theoretical background for all four ECC
  algorithms, including the mathematical foundations of RNS, RRNS
  encoding/decoding, the C-RRNS, 3NRM-RRNS, 2NRM-RRNS, and RS(12,4)
  algorithms, and the Maximum Likelihood Decoding method.
- **Chapter 3** describes the methodology, covering the MATLAB
  simulation phase (Section 3.1) and the FPGA implementation phase
  (Section 3.2), including the top-level system architecture, the
  probabilistic fault injection engine, and the end-to-end test loop.
- **Chapter 4** presents and discusses the experimental results across
  all four evaluation dimensions.
- **Chapter 5** analyses the economic, legal, social, ethical, and
  environmental context of this work.
- **Appendices** provide pseudocode descriptions of all encoder and
  decoder implementations.

# Chapter 2 Theoretical Background

## 2.1 Residue Number System (RNS) Fundamentals

The Residue Number System (RNS) is a non-weighted numeral representation
system based on modular arithmetic, first formalised by Garner \[5\]. In
an RNS, an integer is represented by a set of residues , where each
residue is computed with respect to a chosen modulus . The moduli set
must satisfy three conditions:

1.  **Pairwise coprimality**: for all .
2.  **Strict ordering**: .
3.  **Dynamic range sufficiency**: The product must be sufficient to
    represent all numbers in the legitimate range .

By the Chinese Remainder Theorem (CRT), any integer in the range is
uniquely determined by its residue representation. This property enables
parallel arithmetic operations — addition, subtraction, and
multiplication — to be performed independently on each residue channel
without carry propagation between channels, offering inherent speed
advantages for digital signal processing and memory applications.

## 2.2 Redundant Residue Number System (RRNS) Codes

The Redundant Residue Number System (RRNS) extends the basic RNS by
partitioning the moduli set into two subsets \[13\]:

- **Non-redundant moduli** : used to represent the data word (dataword).
- **Redundant moduli** : used to generate check residues
  (checkword/parity).

The error correction capability of an RRNS code is:

That is, the code can correct up to erroneous residues, or detect up to
erroneous residues. This is equivalent to the error correction
capability of Reed-Solomon codes, making RRNS a competitive alternative
for cluster fault tolerance.

### 2.2.1 RRNS Encoding

Encoding is straightforward: for input data , compute the residue with
respect to each modulus:

The resulting -tuple is the RRNS codeword. The non-redundant residues
represent the data, and the redundant residues serve as parity.

### 2.2.2 RRNS Decoding

Decoding proceeds in two phases: error detection and error correction.

**Error Detection**: The received codeword is decoded to a value using
all residues. If (the product of the non-redundant moduli), the codeword
is valid and no correction is needed. If , errors are detected.

**Error Correction**: A trial-and-error procedure is applied. For each
combination of residues (discarding residues at a time), the data is
reconstructed as and compared against the product of the remaining
moduli . If , the correct data has been recovered. The maximum number of
iterations is .

Two reconstruction algorithms are available: the **Chinese Remainder
Theorem (CRT)**, which uses large integer arithmetic, and **Mixed-Radix
Conversion (MRC)**, which uses smaller integers and is computationally
more efficient. MRC is defined as:

where the mixed-radix digits are computed sequentially:

and the weight coefficients are , .

## 2.3 Conventional RRNS (C-RRNS)

The Conventional RRNS (C-RRNS) code, as defined in \[1\], uses three
restricted non-redundant moduli of the form , where is a positive
integer. For 16-bit data words (), the smallest valid choice is ,
giving:

Six redundant moduli are appended, all larger than the non-redundant
moduli. The resulting codeword has residues and error correction
capability .

The total codeword length is bits. The requirement that redundant moduli
must be larger than non-redundant moduli (Rule 2 of Section 2.1) is
satisfied, enabling standard MRC decoding without ambiguity.

**Limitation**: The use of large redundant moduli results in a 61-bit
codeword — 27.1% longer than the 48-bit RS(12,4) codeword for the same
data width. This storage overhead is the primary motivation for the
modified RRNS variants described in Sections 2.5 and 2.6.

## 2.4 Reed-Solomon (RS) Codes

Reed-Solomon codes are a class of block error-correcting codes defined
over finite fields (Galois fields) \[5\]. An RS code over encodes data
symbols into codeword symbols, each of bits, with error correction
capability symbols.

For the 16-bit data word comparison in this work, the RS(12, 4) code
over is used:

- 4 data symbols × 4 bits = 16 bits of data
- 8 parity symbols × 4 bits = 32 bits of parity
- Total codeword: 12 symbols × 4 bits = **48 bits**
- Error correction capability: symbols

**Encoding** uses systematic polynomial division: the data polynomial is
multiplied by and divided by the generator polynomial , where is a
primitive element of . The remainder gives the parity symbols.

**Decoding** uses the Berlekamp-Massey algorithm to find the error
locator polynomial , followed by Chien search to locate error positions,
and the Forney algorithm to compute error magnitudes. The total decoding
complexity is operations in .

RS codes are well-suited for cluster fault correction because a burst of
consecutive bit errors affects at most symbols, and the symbol-level
correction capability is independent of the burst pattern within a
symbol.

## 2.5 Three Non-Redundant Moduli RRNS (3NRM-RRNS)

The 3NRM-RRNS code was proposed by Haron and Hamdioui \[1\] as a
modified RRNS variant that reduces codeword length while maintaining the
same error correction capability as C-RRNS.

**Key innovation**: The redundant moduli are chosen to be *smaller* than
the non-redundant moduli, in contrast to C-RRNS where redundant moduli
must be larger. Specifically:

The redundant moduli are the minimum values satisfying Rules 1 and 3 of
Section 2.1: they are pairwise coprime, and their product .

The total codeword length is bits — equal to RS(12,4) and 21.3% shorter
than C-RRNS. The error correction capability remains .

**Violation of Rule 2**: Since the redundant moduli are smaller than the
non-redundant moduli, Rule 2 () is violated. This means that some input
data values may have multiple valid candidates during decoding
(ambiguity). This ambiguity is resolved using Maximum Likelihood
Decoding (MLD), described in Section 2.7.

## 2.6 Two Non-Redundant Moduli RRNS (2NRM-RRNS)

The 2NRM-RRNS code \[1\] further reduces the codeword length by using
only *two* non-redundant moduli instead of three:

The non-redundant moduli product is , sufficient to represent all 16-bit
data values. The redundant moduli product is .

The total codeword length is bits — 14.6% shorter than RS(12,4) and
32.8% shorter than C-RRNS. The error correction capability is (two
erroneous residues).

**Storage efficiency**: 2NRM-RRNS achieves the highest storage
efficiency among all evaluated codes:

- 2NRM-RRNS:
- 3NRM-RRNS:
- RS(12,4):
- C-RRNS:

**Decoding speed**: With and moduli, the maximum number of MRC
iterations is . In contrast, C-RRNS and 3NRM-RRNS require iterations.
Therefore, 2NRM-RRNS is 5.6 times faster than C-RRNS in the decoding
process \[1\].

Like 3NRM-RRNS, 2NRM-RRNS violates Rule 2 and requires MLD to resolve
decoding ambiguity.

## 2.7 Maximum Likelihood Decoding (MLD) for Modified RRNS

The violation of Rule 2 in 3NRM-RRNS and 2NRM-RRNS means that the CRT
uniqueness guarantee no longer holds: multiple candidate values may
satisfy the validity condition during decoding. Maximum Likelihood
Decoding (MLD), as proposed by Goh and Siddiqi \[2\], resolves this
ambiguity.

The MLD algorithm selects the most probable valid codeword based on
Hamming distance:

where:

- is the set of all valid candidate values (those satisfying )
- is the received (possibly corrupted) residue vector
- is the expected residue vector for candidate
- is the Hamming distance (number of mismatching residues)

The candidate with the minimum Hamming distance to the received residues
is selected as the decoded output. If multiple candidates share the
minimum distance, a secondary criterion (lower index) is applied as a
tie-breaking rule. In practice, such ties are statistically rare: for a
tie to occur, two distinct candidate values must produce residue vectors
that are equidistant from the received (corrupted) residue vector across
all residue positions simultaneously. Given the pseudo-random
distribution of 16-bit data values and the algebraic structure of the
moduli set, the probability of a tie is negligible compared to the
probability of a unique minimum-distance candidate, and does not
contribute measurably to the observed failure rate in the experimental
results of Section 4.2.

**Computational complexity**: For 2NRM-RRNS, the MLD procedure evaluates
at most candidates (15 modulus pairs × up to 5 candidates per pair due
to the periodicity of the CRT solution). For 3NRM-RRNS and C-RRNS-MLD,
the procedure evaluates triplets. The Hamming distance computation for
each candidate requires modulo operations and comparisons.

## 2.8 Comparison of ECC Schemes

Table 2.1 summarises the key parameters of all four ECC schemes
evaluated in this work, based on the analysis in \[1\].

**Table 2.1** Comparison of ECC schemes for 16-bit data word protection.

| ECC Scheme | Non-redundant moduli | Redundant moduli | Codeword (bits) | Error correction | Storage efficiency | Decoding iterations |
|----|----|----|----|----|----|----|
| C-RRNS | {64, 63, 65} | {67, 71, 73, 79, 83, 89} | 61 | t=3 residues | 26.2% | C(9,3)=84 |
| 3NRM-RRNS | {64, 63, 65} | {31, 29, 23, 19, 17, 11} | 48 | t=3 residues | 33.3% | C(9,3)=84 |
| 2NRM-RRNS | {257, 256} | {61, 59, 55, 53} | 41 | t=2 residues | 39.0% | C(6,2)=15 |
| RS(12,4) | GF(2⁴), 4 data symbols | 8 parity symbols | 48 | t=4 symbols | 33.3% | O(t²) |

The key trade-offs are:

- **C-RRNS** provides t=3 correction but at the highest storage cost (61
  bits).
- **3NRM-RRNS** matches C-RRNS in correction capability (t=3) with a
  21.3% shorter codeword, at the cost of requiring MLD.
- **2NRM-RRNS** achieves the best storage efficiency (39.0%) and fastest
  decoding (15 iterations), with t=2 correction capability.
- **RS(12,4)** provides the highest correction capability (t=4 symbols)
  with a 48-bit codeword, using well-established algebraic decoding.

# Chapter3 Methodology

## 3.1 MATLAB Simulation Phase

The Semester 1 MATLAB simulation (Section 3.1) used a fault injection
model that differs significantly from the FPGA hardware implementation:
it applied random bit flips uniformly across the entire codeword
(including zero-padding bits) using MATLAB's Mersenne Twister random
number generator, which is statistically independent between trials.
This model is not directly comparable to the FPGA's LFSR-based
probabilistic injection engine, which confines faults strictly to the
valid codeword bits and exhibits linear correlations between adjacent
trials due to the LFSR's shift-register structure.

To enable a meaningful FPGA-vs-MATLAB comparison, a second MATLAB
simulation was developed that replicates the FPGA fault injection model
as closely as possible. This simulation (`run_simulation.m`) implements
the following modules:

- `encode.m`: Routes encoding to the appropriate algorithm-specific
  encoder (`encode_2nrm.m`, `encode_3nrm.m`, `encode_crrns.m`,
  `encode_rs.m`). The 2NRM-RRNS, 3NRM-RRNS, and C-RRNS encoders are
  implemented from scratch; the RS(12,4) encoder uses MATLAB's built-in
  `encode()` function with the GF(2⁴) Reed-Solomon configuration.
- `decode.m`: Routes decoding to the appropriate algorithm-specific
  decoder (`decode_2nrm_mld.m`, `decode_3nrm_mld.m`,
  `decode_crrns_mld.m`, `decode_crrns_mrc.m`, `decode_rs.m`). All RRNS
  decoders are implemented from scratch using the MLD algorithm
  described in Section 2.7; the RS(12,4) decoder uses MATLAB's built-in
  `decode()` function.
- `fault_injector.m`: Implements the same probabilistic injection model
  as the FPGA: for random single-bit mode, each bit is independently
  flipped with probability ; for cluster burst mode, a single burst of
  consecutive bits is injected with probability , at a uniformly random
  position within the valid codeword region.
- `ber_sweep.m`: Executes the Monte Carlo BER sweep using MATLAB's
  Parallel Computing Toolbox (`parfor`) to distribute trials across
  available CPU cores, achieving approximately 8–10× speedup on a
  12-core processor.
- `save_results_csv.m`: Saves results in the same CSV format as the
  FPGA, enabling direct comparison using the existing visualisation
  scripts.

Due to an inconsistency in the fault injection models, the first-round
MATLAB simulation (detailed in Appendix H) could not be directly
compared with the FPGA tests. Therefore, a second-round simulation was
performed using a consistent model, and its results are plotted together
with the FPGA results in Chapter 4 for comparison.

## 3.2 FPGA Implementation Phase

### 3.2.1 Top-Level System Architecture

#### 3.2.1.1 Overview

The FPGA-based fault-tolerance evaluation platform is designed around a
**master-slave architecture**, in which a PC host acts as the high-level
controller responsible for test configuration and result visualisation,
while the FPGA target autonomously executes the full BER sweep and
returns a consolidated result packet upon completion. The two sides
communicate exclusively through a **UART serial link** operating at
921,600 bps. Figure 3.1 illustrates the top-level system topology.The
detailed function names and functionalities of each specific module are
provided in Appendix I.

Figure 3.1 Top-level system architecture of the FPGA fault-tolerance
evaluation platform

**Figure 3.1** Top-level system architecture of the FPGA fault-tolerance
evaluation platform (Artix-7 xc7a100t, Arty A7-100T development board).

A key design principle adopted throughout this work is the
**Single-Algorithm-Build** strategy: each Vivado synthesis run
instantiates exactly one codec algorithm, selected at compile time via a
Verilog preprocessor macro (`BUILD_ALGO_xxx`). This ensures that the
resource utilisation figures reported for each algorithm are free from
cross-algorithm interference, yielding accurate and directly comparable
LUT, flip-flop, DSP, and Block RAM counts. Switching between algorithms
requires only a one-line change in the header file
`src/interfaces/main_scan_fsm.vh`, followed by a full re-synthesis.

In addition to the Single-Algorithm-Build strategy, the platform also
supports an **All-in-One Build** mode, enabled by defining the
`ALL_IN_ONE_BUILD` macro in the same header file. In this mode, all six
encoder and decoder instances are synthesised simultaneously into a
single bitstream; the active algorithm is selected at runtime via the
`algo_id` field in the downlink command frame. This mode is particularly
useful for rapid BER performance comparison across all algorithms
without requiring repeated bitstream downloads — the PC-side controller
(`py_controller_main.py` Mode A) automatically iterates through all six
algorithm configurations for each specified burst length and generates
comparison plots upon completion. It should be noted that the All-in-One
Build consumes approximately twice the FPGA resources of a
single-algorithm build and is therefore not used for the resource
utilisation or power consumption measurements reported in Sections 4.6
and 4.7, which are based exclusively on Single-Algorithm-Build results.

#### 3.2.1.2 System Workflow

The overall test procedure is divided into three sequential phases, as
described below.

**Phase 1 — Configuration**

The user launches `py_controller_main.py` on the PC and specifies four
parameters via a command-line interface:

**Table 3.1** Configurable parameters by command-line interface.

| Parameter | Description | Range |
|----|----|----|
| `Algo_ID` | Algorithm under test | 0–6 (see Table 3.4) |
| `Error_Mode` | Fault injection mode | 0 = random single-bit, 1 = cluster burst |
| `Burst_Len` | Burst length *L* | 1–15 bits |
| `Sample_Count` | Trials per BER point | 1–1,000,000 |

**Table 3.2** Algorithm ID mapping.

| Algo_ID | Algorithm | Decoder Architecture | Codeword (bits) |
|----|----|----|----|
| 0 | 2NRM-RRNS (Parallel) | 15-channel parallel MLD | 41 |
| 1 | 3NRM-RRNS | Sequential FSM MLD (84 triplets) | 48 |
| 2 | C-RRNS-MLD | Sequential FSM MLD (84 triplets) | 61 |
| 3 | C-RRNS-MRC | Direct Mixed Radix Conversion | 61 |
| 5 | RS(12,4) | Berlekamp–Massey + Chien + Forney | 48 |
| 6 | 2NRM-RRNS (Serial) | Sequential FSM MLD (15 pairs) | 41 |

Note: the ID 4 is assigned for C-RRNS-CRT,which is deleted form the
program in the final version.

The host assembles a compact **12-byte downlink command frame**
structured as:

    [Header: 0xAA 0x55] [CmdID: 0x01] [Length: 0x07] [Burst_Len] [Algo_ID]
    [Error_Mode] [Sample_Count: 4 bytes, Big-Endian] [XOR Checksum]

and transmits it over UART. Receipt of this frame by the FPGA implicitly
triggers the start of the test sweep — no separate start command is
required. This "configuration-as-trigger" protocol minimises
communication overhead and eliminates the risk of a race condition
between configuration and start signals.

**Phase 2 — Autonomous BER Sweep**

Upon receiving a valid configuration frame, the FPGA performs the
following sequence entirely without further PC intervention:

1.  **Parameter latch**: `ctrl_register_bank` atomically captures all
    four parameters and asserts `test_active` in the same clock cycle,
    preventing any partial-update hazard.
2.  **Seed capture**: `seed_lock_unit` samples the free-running 32-bit
    counter one cycle after `test_active` is asserted and holds the seed
    constant for the entire sweep. This ensures that all 101 BER points
    are driven by the same pseudo-random sequence, making the results
    statistically consistent and reproducible.
3.  **101-point loop**: `Main Scan FSM` iterates `ber_idx` from 0 to
    100, corresponding to target BER values of 0.0 % to 10.0 % in steps
    of 0.1 %. At each point:
    - The 32-bit LFSR injection threshold is retrieved from
      `rom_threshold_ctrl`. This threshold was pre-computed offline by
      `gen_rom.py` using the formula , where , and is the
      algorithm-specific valid codeword width.
    - `Auto Scan Engine` executes *N* independent trials (where *N* =
      `Sample_Count`). In each trial: a 16-bit pseudo-random symbol is
      generated → encoded into a codeword → faults are injected
      according to the current threshold and burst length → the
      corrupted codeword is decoded → the decoded symbol is compared
      against the original. Pass/fail outcome, actual flip count, and
      encoder/decoder clock cycles are accumulated into running totals.
    - Upon completion of *N* trials, the aggregated statistics for the
      current BER point are written to `mem_stats_array`.
4.  On completion of all 101 points, `test_active` is de-asserted and
    the upload phase is triggered.

**Phase 3 — Result Upload**

`tx_packet_assembler` reads all 101 entries from `mem_stats_array` and
serialises them into a **3,039-byte uplink response frame**:

    Header(2) + CmdID(1) + Length(2) + GlobalInfo(3) + 101 × PerPointData(30) + Checksum(1)
    = 3,039 bytes total

Each 30-byte per-point record contains: BER index (1 B), success count
(4 B), fail count (4 B), actual flip count (4 B), total clock count (8
B), encoder clock count (4 B), decoder clock count (4 B), and one
reserved byte. The PC receives the frame, verifies the XOR checksum,
parses all 101 records, and exports the results to a timestamped CSV
file. Visualisation scripts are then invoked automatically to generate
the comparison plots presented in Chapter 4.

#### 3.2.1.4 Main Scan FSM State Diagram

The top-level control flow of the FPGA is governed by `Main Scan FSM`,
whose state transitions are shown in Figure 3.2.  
state diagram.png  
**Figure 3.2** State diagram of the Main Scan FSM.

The FSM employs an **edge-triggered start mechanism**: an internal
rising-edge detector on `test_active` generates a single-cycle
`sys_start_pulse`, preventing re-triggering if the signal remains
asserted. A hardware abort button (mapped to FPGA pin B9, debounced over
16 ms at 100 MHz) asserts `sys_abort` with the highest priority, forcing
an immediate return to `IDLE` from any state. This provides a reliable
mechanism to interrupt a long-running test without requiring a full FPGA
reset.

#### 3.2.1.5 Clock Domain, Operating Frequency, and Reset Strategy

The entire design operates within a **single clock domain** driven by
the 100 MHz on-board oscillator of the Arty A7-100T development board.
This eliminates the need for asynchronous FIFOs or clock-domain crossing
synchronisers, simplifying timing closure and reducing resource
overhead.

**Operating Frequency**

Although the board provides a 100 MHz oscillator, all six algorithm
configurations are implemented and evaluated at **50 MHz**. The initial
design target was 100 MHz; however, the 2NRM-RRNS parallel MLD decoder —
which instantiates 15 independent CRT pipeline channels simultaneously —
presented significant timing closure challenges at 100 MHz due to the
long combinational paths in the parallel Hamming distance reduction
tree. Despite approximately 30 rounds of timing optimisation (including
pipeline stage insertion, logic restructuring, and placement
constraints), the 100 MHz timing constraint could not be met for the
parallel decoder without fundamentally altering the architecture. The
operating frequency was therefore reduced to **50 MHz**, at which all
six algorithm configurations achieve timing closure with positive slack.

This frequency reduction does not compromise the fairness of the
inter-algorithm comparison: all six implementations are evaluated at the
same 50 MHz clock, ensuring that the latency and throughput figures
reported in Chapter 4 are directly comparable. The 50 MHz operating
frequency is also representative of practical ECC accelerator
deployments in embedded memory systems, where power consumption and
timing margin are often prioritised over raw clock speed.

**UART Baud-Rate Generation**

The UART baud-rate generator uses an integer divider of 109 applied to
the 100 MHz system clock input, yielding an actual baud rate of 917,431
bps — a deviation of −0.45 % from the target 921,600 bps. This is well
within the ±2.5 % tolerance of standard UART receivers (based on 16×
oversampling with the sampling point at the bit centre), and has been
verified to produce no framing errors over the 3,039-byte response
frame. Note that the UART baud-rate divider is clocked from the 100 MHz
oscillator input directly, independent of the 50 MHz logic clock used by
the rest of the design.

**Reset Strategy**

All registers adopt an **asynchronous-assert, synchronous-release**
reset strategy. The external reset signal (`rst_n`) is passed through a
two-stage flip-flop synchroniser before being distributed as `sys_rst_n`
to all sub-modules. This prevents metastability at power-on while
ensuring deterministic release timing aligned to the rising edge of the
system clock, in accordance with standard FPGA design practice for
Xilinx Artix-7 devices.

All algorithm configurations were synthesised using identical tool
settings, timing constraints, and target clock frequency (50 MHz),
ensuring that reported latency and resource utilisation metrics are
directly comparable without optimisation bias.

### 3.2.2 Probabilistic Fault Injection Engine

#### 3.2.2.1 LFSR-Based Pseudo-Random Fault Generation

The fault injection subsystem is built around a **32-bit Galois Linear
Feedback Shift Register (LFSR)**, which serves as the sole source of
pseudo-randomness for both injection triggering and error-position
selection. The Galois configuration was chosen over the more common
Fibonacci topology because it distributes the feedback XOR operations
across individual flip-flops, enabling a single-cycle update with
minimal combinational depth — a critical requirement for maintaining 100
MHz timing closure.

At each rising clock edge, the LFSR advances by one step, producing a
new 32-bit pseudo-random value. This output is partitioned and reused
for two independent purposes without requiring additional LFSR
instances:

- **Bits \[31:0\]** are compared against the 32-bit injection threshold
  to determine whether a fault should be injected in the current trial.
- **Bits \[5:0\]** are used directly as the random offset into the
  error-pattern look-up table, selecting the starting bit position of
  the injected burst.

This dual-use strategy eliminates the need for a second random source,
reduces hardware resource consumption, and ensures that the injection
decision and the error position are determined within the same clock
cycle.

Please refer to Appendix J for the detailed algorithm of 32-bit Galois
LFSR .

#### 3.2.2.2 Seed Initialisation Mechanism

A key design requirement is that each test run should produce
statistically independent results, while all 101 BER points within a
single run must be driven by the same pseudo-random sequence to ensure
cross-point consistency. This is achieved through a **task-level seed
locking** mechanism implemented in the `seed_lock_unit` module.

Rather than receiving a seed from the PC host, the FPGA captures its own
seed autonomously. A 32-bit free-running counter increments continuously
at 100 MHz. At the moment the FPGA receives a valid configuration frame
from the PC — specifically, one clock cycle after `test_active` is
asserted — the current counter value is latched as the LFSR seed. Since
the exact timing of the PC command depends on the user's interaction and
the USB-UART bridge latency, the captured value is effectively
unpredictable, providing natural randomness between successive test
runs.

Once latched, the seed is held constant throughout the entire 101-point
sweep. The `lock_en` signal remains asserted from the `INIT` state until
the `FINISH` state of the Main Scan FSM, preventing any re-capture. A
zero-seed guard is also implemented: if the captured counter value is
zero, the seed is forced to 1, preventing the LFSR from entering the
all-zero lock-up state.

This mechanism offers two important advantages. First, it eliminates the
need for the PC to transmit a seed value, simplifying the communication
protocol. Second, it guarantees that the statistical properties of the
pseudo-random sequence are identical across all 101 BER points within a
single test run, making the BER sweep results directly comparable.

#### 3.2.2.3 Injection Trigger Mechanism

The target BER is realised through a **probabilistic threshold
comparison** rather than a deterministic injection schedule. This
approach is a novel contribution of this work, as it decouples the
injection probability from the number of test samples, enabling the
sample count to be configured freely over a wide range (1 to 1,000,000)
without any change to the hardware or the pre-computed ROM tables.

**BER Definition**

The BER in this system is defined as the ratio of the total number of
injected bit flips to the total number of valid codeword bits processed:

where is the algorithm-specific valid codeword width (e.g., 41 bits for
2NRM-RRNS, 61 bits for C-RRNS), and is the burst length. This definition
ensures that algorithms with different codeword lengths are evaluated
under a fair and comparable injection intensity.

**Threshold Calculation**

For a given target BER, burst length , and algorithm codeword width ,
the per-trial injection probability is:

This probability is mapped to a 32-bit unsigned integer threshold:

At each trial, the 32-bit LFSR output is compared against . If , a fault
is injected; otherwise, the codeword passes through unmodified. Since
the LFSR output is uniformly distributed over , the long-run injection
rate converges to by the law of large numbers.

**Offline Pre-computation**

All threshold values for the 101 BER points (0.0 % to 10.0 %, step 0.1
%), 7 algorithms, and 15 burst lengths are pre-computed offline by the
Python script `gen_rom.py` and stored in a Block RAM initialised from
`threshold_table.coe` (10,605 entries, 32 bits wide). During the test
sweep, the FPGA retrieves the appropriate threshold in a single clock
cycle via the `rom_threshold_ctrl` module, with no floating-point
arithmetic required at runtime.

#### 3.2.2.4 Error Pattern Generation and Boundary Safety

Once the injection trigger fires, the specific bit positions to be
flipped are determined by a **ROM-based look-up table**
(`error_lut.coe`). This approach replaces the conventional dynamic
barrel-shifter method, which would require a long combinational path and
risk timing violations at 100 MHz.

The error look-up table has a depth of 8,192 entries and a width of 64
bits. Each entry stores a pre-computed 64-bit error mask with exactly
bits set to 1, starting at a specific offset within the valid codeword
region. The table is addressed by a 13-bit index formed by concatenating
three fields:

The `random_offset` field is taken directly from the lower 6 bits of the
LFSR output, providing 64 possible starting positions for each burst
length and algorithm combination.

**Boundary Safety**

A critical constraint is that the injected burst must fall entirely
within the valid bits of the codeword, never touching the zero-padding
bits in the upper portion of the 64-bit bus. This constraint is enforced
entirely at the offline pre-computation stage: for any address where
`random_offset` \> , the corresponding ROM entry is set to zero (no
injection). As a result, the FPGA hardware requires no boundary-checking
logic whatsoever — any out-of-range LFSR output simply produces a zero
mask, which has no effect on the codeword. This fail-safe mechanism
guarantees single-cycle injection latency and eliminates a class of
potential timing violations.

**Random Single-Bit Mode**

When `burst_len` = 1, the injection reduces to a single random bit flip.
The valid offset range is , and the 64 possible LFSR offsets are mapped
such that offsets 0 to produce a valid single-bit mask, while offsets to
63 produce a zero mask (no injection). The effective injection
probability is therefore scaled by a factor of , which is compensated in
the threshold calculation as described in Section 3.2.2.3.

**Cluster Burst Mode**

When `burst_len` = , the valid offset range shrinks to , ensuring the
entire -bit burst fits within the codeword. The number of valid offsets
is , and the compensation factor applied to the threshold becomes .

#### 3.2.2.5 Impact of Burst Length on Maximum Achievable BER

The probabilistic injection mechanism imposes a fundamental upper bound
on the achievable BER for a given burst length and algorithm. Since the
injection probability cannot exceed 1, the maximum achievable target BER
is:

This bound arises because, even if every trial triggers an injection (),
the number of flipped bits per trial is exactly , and the total valid
bits per trial is .

As the burst length increases, increases proportionally. However, the
number of valid injection offsets simultaneously decreases, which
reduces the effective randomness of the error position. For very large
relative to , the injected burst covers a significant fraction of the
codeword, and the error pattern becomes less representative of realistic
channel conditions. In this work, burst lengths up to are supported,
which is sufficient to model the cluster fault patterns observed in
hybrid CMOS/non-CMOS memory technologies.

The following table summarises the maximum achievable BER for each
algorithm at selected burst lengths.

**Table 3.3** Maximum achievable BER for each algorithm and selected
burst lengths. For (cluster burst mode), . For (random single-bit mode),
the Bit-Scan Bernoulli model applies and (no upper bound within the test
range).

| Algorithm | (bits) |       |        |        |        |
|-----------|--------|-------|--------|--------|--------|
| 2NRM-RRNS | 41     | 100 % | 12.2 % | 19.5 % | 36.6 % |
| 3NRM-RRNS | 48     | 100 % | 10.4 % | 16.7 % | 31.3 % |
| C-RRNS    | 61     | 100 % | 8.2 %  | 13.1 % | 24.6 % |
| RS(12,4)  | 48     | 100 % | 10.4 % | 16.7 % | 31.3 % |

**Special note for (Random Single-Bit Mode):** When , the injection
engine employs a **Bit-Scan Bernoulli** model rather than the
single-event burst model used for . In this mode, the engine iterates
over every bit position of the codeword and independently applies a
Bernoulli flip decision at each position with probability . The expected
number of flipped bits per trial is therefore , and the expected actual
BER equals the target BER exactly — with no saturation ceiling. This
design overcomes the fundamental limitation of the original single-event
model, in which the maximum achievable BER was capped at (e.g., 2.4 %
for 2NRM-RRNS, 1.6 % for C-RRNS), making it impossible to evaluate
algorithm behaviour at higher error rates. With the Bit-Scan Bernoulli
model, the full 0 %–10 % BER sweep range is accessible for all
algorithms under random single-bit injection, enabling a fair and
complete performance comparison.

Since the target BER sweep in this work covers 0 % to 10 %, all four
algorithms can be fully evaluated under both random single-bit () and
cluster burst (, etc.) injection modes. For , the Bit-Scan Bernoulli
model ensures the actual injected BER tracks the target BER across the
full sweep range without saturation. For , the maximum achievable BER is
bounded by ; the burst lengths and were selected to ensure this bound
exceeds 10 % for all algorithms, guaranteeing full coverage of the test
range.

#### 3.2.2.6 Design Advantages and Novel Contributions

The probabilistic fault injection engine described in this section
represents a **novel contribution** of this work, offering several
advantages over conventional approaches:

1.  **Minimal memory footprint**: The entire injection subsystem
    requires only two Block RAMs — `threshold_table.coe` (10,605 ×
    32-bit entries, approximately 41 KB) and `error_lut.coe` (8,192 ×
    64-bit entries, approximately 64 KB). This is orders of magnitude
    smaller than a pre-generated fault sequence stored in memory.

2.  **Arbitrary sample count**: Because injection decisions are made
    independently at each trial using a probabilistic comparison, the
    sample count per BER point can be set to any value between 1 and
    1,000,000 without modifying the hardware or the ROM tables. This
    flexibility allows the user to trade off test duration against
    statistical confidence.

3.  **Statistical rigour**: In this work, 100,000 samples are collected
    per BER point. By the law of large numbers, the actual injection
    rate converges to the target BER with a standard deviation of
    approximately at , . This level of statistical precision is
    sufficient to distinguish the performance differences between the
    evaluated algorithms.

4.  **Single-cycle injection latency**: The ROM look-up table approach
    eliminates all runtime arithmetic, producing the 64-bit error mask
    in a single clock cycle. This ensures that the injection subsystem
    does not introduce any pipeline stalls or timing violations at 50
    MHz.

5.  **Algorithm-agnostic design**: The injection engine is parameterised
    by `algo_id`, `burst_len`, and `random_offset`, and operates
    identically regardless of which ECC algorithm is under test. Adding
    a new algorithm requires only updating the ROM tables offline — no
    changes to the FPGA injection logic are needed.

### 3.2.3 End-to-End Test Loop and Algorithm Extensibility

#### 3.2.3.1 Single-Trial Execution Pipeline

Each test trial is executed by the `Auto Scan Engine` module as a
deterministic five-stage pipeline. The stages proceed sequentially
within a single invocation of the engine, with the FSM advancing through
each stage upon completion of the previous one.

**Stage 1 — Data Generation**

A 16-bit pseudo-random test symbol is extracted from the current LFSR
output. The symbol is derived from the lower 16 bits of the 32-bit LFSR
register, ensuring that the test data is statistically independent from
the injection trigger decision (which uses the full 32-bit value).

**Stage 2 — Encoding**

The test symbol is passed to the `encoder_wrapper`, which routes it to
the active encoder module selected at compile time. The encoder produces
a codeword of algorithm-specific width (41 to 61 bits), right-aligned
within a 64-bit bus with zero-padding in the upper bits. The encoder
asserts a `done` signal upon completion; the FSM waits for this signal
before proceeding. The encoder latency in clock cycles is measured from
the assertion of `start` to the assertion of `done`, and is accumulated
for statistical reporting.

**Stage 3 — Fault Injection**

The encoded codeword is passed to the `error_injector_unit`. Based on
the current LFSR output and the pre-computed error look-up table, the
injector either applies a burst error mask (XOR operation) or passes the
codeword through unmodified, as described in Section 3.2.2. The actual
number of flipped bits is recorded for statistical reporting.

**Stage 4 — Decoding**

The (potentially corrupted) codeword is passed to the `decoder_wrapper`,
which routes it to the active decoder module. The decoder asserts a
`valid` signal when the decoded symbol is ready, along with an
`uncorrectable` flag if the error pattern exceeds the algorithm's
correction capability. The FSM waits for `valid` before proceeding. The
decoder latency in clock cycles is measured from the assertion of
`start` to the assertion of `valid`, and is accumulated separately from
the encoder latency.

**Stage 5 — Comparison and Statistics**

The `result_comparator` compares the decoded symbol against the original
test symbol. A trial is counted as a **pass** only if both of the
following conditions are satisfied simultaneously: (1) the decoder
reports no uncorrectable error, and (2) the decoded symbol is
bit-for-bit identical to the original. If either condition fails, the
trial is counted as a **failure**. This double-check rule prevents
decoder false-positives — cases where the decoder claims success but
produces an incorrect output — from inflating the measured success rate.

The following statistics are accumulated for each BER point:

- Success count and failure count
- Total actual flip count (sum of injected bits across all trials)
- Total clock cycles (encoder latency + injection + decoder latency)
- Encoder clock cycles (accumulated separately)
- Decoder clock cycles (accumulated separately)

#### 3.2.3.2 Encoder Wrapper and Decoder Wrapper: Unified Interface for Algorithm Extensibility

A central design goal of this platform is to support multiple ECC
algorithms with minimal code duplication and zero changes to the test
infrastructure when a new algorithm is added. This is achieved through
the `encoder_wrapper` and `decoder_wrapper` modules, which provide a
**unified, algorithm-agnostic interface** to the `Auto Scan Engine`.

**Unified Interface**

All encoder modules expose the following standardised interface:

**Table 3.4** Standard encoder interface signals

| Signal         | Direction | Description                                      |
|----------------|-----------|--------------------------------------------------|
| `clk`, `rst_n` | Input     | System clock and active-low reset                |
| `start`        | Input     | Single-cycle pulse to begin encoding             |
| `data_in_A`    | Input     | 16-bit input symbol                              |
| `codeword_out` | Output    | Encoded codeword (right-aligned in 64-bit bus)   |
| `done`         | Output    | Asserted for one cycle when encoding is complete |

All decoder modules expose a corresponding standardised interface:

**Table 3.5** Standard decoder interface signals

| Signal | Direction | Description |
|----|----|----|
| `clk`, `rst_n` | Input | System clock and active-low reset |
| `start` | Input | Single-cycle pulse to begin decoding |
| `residues_in` | Input | 64-bit packed codeword (right-aligned) |
| `data_out` | Output | Decoded 16-bit symbol |
| `valid` | Output | Asserted for one cycle when decoding is complete |
| `uncorrectable` | Output | Asserted if the error pattern exceeds correction capability |

**Compile-Time Algorithm Selection**

The `encoder_wrapper` and `decoder_wrapper` modules use Verilog
preprocessor conditionals (`ifdef`) to instantiate exactly one algorithm
at compile time. The active algorithm is selected by defining a single
macro in the header file `src/interfaces/main_scan_fsm.vh`. All other
algorithm branches are compiled out, ensuring that the synthesised
netlist contains only the logic for the selected algorithm. This is the
foundation of the Single-Algorithm-Build strategy described in Section
3.2.1.1.

**Extensibility**

The wrapper architecture makes adding a new ECC algorithm
straightforward. The required steps are:

1.  Implement the encoder and decoder modules conforming to the
    standardised interface.
2.  Add one `ifdef` branch in `encoder_wrapper.v` and
    `decoder_wrapper.v`.
3.  Add one entry in the algorithm configuration of `gen_rom.py` and
    regenerate the ROM tables.
4.  Add one macro definition in `main_scan_fsm.vh`.

No changes are required to the `Auto Scan Engine`, the Main Scan FSM,
the fault injection engine, the result buffer, or the PC-side software.
This separation of concerns between the test infrastructure and the
algorithm implementation significantly reduces the engineering effort
required to evaluate a new algorithm, and is a key design advantage of
the platform.

#### 3.2.3.3 Implemented Algorithms and Architectural Variants

The platform was used to implement and evaluate six algorithm
configurations, as summarised in Table 3.6. All six share the same test
infrastructure; only the encoder and decoder modules differ.

**Table 3.6** Summary of implemented algorithm configurations.

| Algo_ID | Algorithm | Encoder Module | Decoder Module | Decoder Architecture | Codeword (bits) | Error Correction |
|----|----|----|----|----|----|----|
| 0 | 2NRM-RRNS (Parallel) | `encoder_2nrm` | `decoder_2nrm` | 15-channel parallel MLD pipeline | 41 | t = 2 residues |
| 1 | 3NRM-RRNS | `encoder_3nrm` | `decoder_3nrm` | Sequential FSM MLD, 84 triplets | 48 | t = 3 residues |
| 2 | C-RRNS-MLD | `encoder_crrns` | `decoder_crrns_mld` | Sequential FSM MLD, 84 triplets | 61 | t = 3 residues |
| 3 | C-RRNS-MRC | `encoder_crrns` | `decoder_crrns_mrc` | Direct Mixed Radix Conversion | 61 | None (detection only) |
| 5 | RS(12,4) | `encoder_rs` | `decoder_rs` | Berlekamp–Massey + Chien + Forney | 48 | t = 4 symbols |
| 6 | 2NRM-RRNS (Serial) | `encoder_2nrm` | `decoder_2nrm_serial` | Sequential FSM MLD, 15 pairs × 5 candidates | 41 | t = 2 residues |

**Note on C-RRNS-CRT exclusion**: An initial design considered a seventh
configuration — C-RRNS-CRT (Direct Chinese Remainder Theorem decoder,
Algo_ID 4 in the original plan) — which reconstructs data from the three
non-redundant residues using the CRT formula. However, this
configuration was excluded from the final evaluation for the following
reason: the C-RRNS-CRT decoder is mathematically equivalent to
C-RRNS-MRC in terms of fault tolerance (neither provides error
correction). Including C-RRNS-CRT would add a redundant data point
without providing additional insight into the algorithm design space.
The C-RRNS-CRT pseudocode is retained in Appendix F.4 for completeness.

Several observations are worth noting:

**C-RRNS variants (IDs 2–3)** share the same encoder (`encoder_crrns`,
61-bit codeword) but use two different decoding strategies in the final
evaluation. C-RRNS-MLD applies Maximum Likelihood Decoding over all
C(9,3) = 84 triplets of moduli, providing t = 3 error correction
capability. C-RRNS-MRC uses only the three non-redundant moduli for
direct reconstruction, without error correction capability. The
quantitative latency comparison between these two decoding strategies is
presented in Section 4.4. Pseudocode descriptions of the C-RRNS encoder
and all decoder variants (including C-RRNS-CRT) are provided in Appendix
F.

**2NRM-RRNS dual implementation (IDs 0 and 6)** uses the same encoder
(`encoder_2nrm`) and produces identical 41-bit codewords. The two
decoders implement the same Maximum Likelihood Decoding algorithm — one
using 15 parallel pipeline channels (ID 0) and one using a sequential
FSM that iterates through the same 15 modulus pairs, each with up to 5
candidate values (ID 6). The resource-latency trade-off between the
parallel and serial implementations is quantified in Chapter 4. This
pair of implementations provides a direct, controlled comparison of
parallel versus sequential MLD architectures for the same algorithm,
which is one of the novel contributions of this work. Pseudocode
descriptions of the 2NRM-RRNS encoder (Appendix B), parallel MLD decoder
(Appendix C), and serial FSM decoder (Appendix D) are provided in the
Appendices. The 3NRM-RRNS encoder and decoder are described in Appendix
E, and the RS(12,4) encoder and decoder in Appendix G.

# Chapter 4 Results and Discussion

## 4.1 Experimental Setup Summary

The evaluation platform described in Chapter 3 was used to collect
performance data for all six algorithm configurations under two fault
injection scenarios. The test conditions are summarised in Table 4.1.

**Table 4.1** Summary of test conditions.

| Parameter | Value |
|----|----|
| Target BER range | 0.0 % to 10.0 %, step 0.1 % (101 points) |
| Samples per BER point | 100,000 |
| Fault injection modes | Random single-bit (L=1), Cluster burst L=5, L=8, L=12,L =15; To achieve the maximum cluster error length that allows for 100% decoding success rate, different algorithms were also tested with other length configurations. |
| Algorithms evaluated | 2NRM-RRNS (Parallel), 2NRM-RRNS (Serial), 3NRM-RRNS, C-RRNS-MLD, C-RRNS-MRC, RS(12,4) |
| Clock frequency | 50 MHz |
| Target device | Xilinx Artix-7 xc7a100t (Arty A7-100T) |

The choice of 100,000 samples per BER point provides a statistical
standard deviation of approximately at , which is sufficient to
distinguish the performance differences between algorithms with high
confidence.

**Remaining difference between MATLAB and FPGA fault injection models**:
In the MATLAB simulation, each trial uses an independent random seed
(MATLAB's default per-worker random stream in `parfor`), ensuring
statistically independent fault patterns across trials. In the FPGA
implementation, the 32-bit Galois LFSR advances sequentially across
consecutive trials within a single BER point, introducing a degree of
linear correlation between adjacent trials. This correlation is
negligible for the large sample counts used in this work (100,000 trials
per BER point), but represents a fundamental difference in the
statistical properties of the two injection models. The LFSR's period of
cycles ensures that the sequence does not repeat within any single test
run.

## 4.2 BER Performance Under Random Single-Bit Fault Injection

Figure 4.1 shows the decode success rate as a function of actual
injected BER for all algorithm configurations under random single-bit
fault injection (L=1). The figure presents both FPGA hardware
measurement results and MATLAB simulation results side by side, enabling
direct cross-validation of the hardware implementation.

Figure 4.1 Decode success rate vs. actual BER — Random single-bit
injection (FPGA vs MATLAB)

**Figure 4.1** Decode success rate vs. actual BER under random
single-bit fault injection (L=1, 100,000 samples per BER point).  
Solid lines: FPGA hardware measurements; dashed lines: MATLAB simulation
results. The close agreement between the two confirms the correctness of
both the hardware implementation and the MATLAB simulation model.

**FPGA vs. MATLAB Consistency**  
A key observation from Figure 4.1 is that the FPGA hardware results and
the MATLAB simulation results are in **high agreement** across all
algorithms and the full BER range. This consistency validates two
aspects simultaneously: (1) the FPGA hardware implementations are
algorithmically correct, and (2) the MATLAB simulation model — which
replicates the FPGA's LFSR-based probabilistic injection engine as
described in Section 4.1 — accurately captures the statistical behaviour
of the hardware fault injection mechanism. The close match between the
two platforms provides strong evidence that the performance results
reported in this chapter are reliable and reproducible.

**Low-BER Region (BER \< 1%): All Correcting Algorithms Perform Well**  
At low BER values (below approximately 1%), all correcting algorithms —
2NRM-RRNS (Parallel and Serial), 3NRM-RRNS, C-RRNS-MLD, and RS(12,4) —
maintain decode success rates close to 100%. This is expected: at low
injection rates, the probability of corrupting more residues than the
algorithm's correction capability is negligibly small, and all
algorithms operate well within their correction limits. The
non-correcting algorithms (C-RRNS-MRC) degrade linearly from the outset,
as any single bit flip that corrupts a non-redundant residue directly
causes a decoding failure.

**Performance Ranking at Elevated BER**  
As BER increases beyond 1%, the algorithms diverge in performance. The
observed ranking from best to worst is:

- **RS(12,4)** achieves the highest success rate among non-100%
  algorithms, benefiting from its t=4 symbol correction capability.
  Symbol-level correction is particularly effective under random
  single-bit injection because multiple bit errors within the same 4-bit
  symbol count as only one symbol error.
- **2NRM-RRNS-MLD Parallel** ranks second, maintaining a higher success
  rate than 3NRM-RRNS despite having a lower theoretical correction
  capability (t=2 vs. t=3). This is explained by the LFSR clustering
  effect discussed below.
- **3NRM-RRNS-MLD** ranks third, with a gradual degradation curve
  consistent with its t=3 correction capability over 9 moduli.
- **2NRM-RRNS-MLD Serial** and **C-RRNS-MLD** show similar performance
  at elevated BER.

**Performance Difference Between 2NRM-RRNS Parallel and Serial**  
A notable observation is that the 2NRM-RRNS Parallel implementation
achieves a measurably higher success rate than the Serial implementation
at elevated BER values, despite both implementing the identical 15-pair
MLD decoding algorithm. This apparent paradox is explained by the **LFSR
clustering effect** arising from the different trial periods of the two
implementations.

The FPGA's 32-bit Galois LFSR advances by one step per clock cycle. The
2NRM-RRNS Parallel decoder completes each trial in approximately 73
clock cycles (encoder + decoder + overhead), while the Serial decoder
requires approximately 1,056 clock cycles per trial. As a result,
consecutive trials in the Parallel implementation use LFSR states that
are only 73 steps apart, while consecutive trials in the Serial
implementation use states that are 1,056 steps apart.

Due to the linear shift-register structure of the LFSR, states that are
close together exhibit stronger linear correlations than states that are
far apart. In the Parallel case, this correlation means that the
injected bit positions in consecutive trials tend to cluster within the
same residue fields — multiple consecutive trials may inject errors into
the same residue, which counts as only one symbol error per trial from
the decoder's perspective. This clustering effect effectively reduces
the number of distinct residues corrupted per trial, making the error
pattern easier to correct and inflating the measured success rate
relative to the true independent-injection model.

In the Serial case, the 1,056-step separation between consecutive LFSR
states produces weaker correlations, resulting in a more uniform
distribution of error positions across residues — closer to the
independent random injection model. This explains why the Serial
implementation shows a lower success rate than the Parallel
implementation at elevated BER: the Serial results are a more accurate
reflection of the true algorithm performance under independent random
injection, while the Parallel results are slightly optimistic due to the
LFSR clustering effect.

This analysis is consistent with the MATLAB simulation results, which
use independent random seeds per trial (no LFSR correlation) and show
success rates closer to the Serial FPGA results than to the Parallel
FPGA results at elevated BER. The difference between Parallel and Serial
FPGA results is therefore an artefact of the hardware injection model
rather than a genuine algorithmic performance difference — both
implementations are mathematically equivalent and would produce
identical results under a truly independent injection model.

**Important note on cross-algorithm comparison validity:** The LFSR
clustering effect only affects the comparison *between the two 2NRM-RRNS
implementations* (Parallel vs. Serial), because they differ in trial
period (73 vs. 1,056 cycles). It does **not** affect the comparison
*between different algorithms* (e.g., 2NRM-RRNS vs. 3NRM-RRNS vs. RS vs.
C-RRNS-MLD), because each algorithm is tested in a separate independent
run with its own LFSR seed. For cross-algorithm comparison, the MATLAB
simulation results (which use truly independent random seeds per trial)
serve as the ground truth and are in close agreement with the FPGA
results for all algorithms. The benchmark conclusions regarding relative
algorithm performance (fault tolerance, storage efficiency, latency) are
therefore valid and unaffected by the LFSR clustering artefact.

## 4.3 BER Performance Under Cluster Burst Injection

This section evaluates algorithm performance under cluster burst fault
injection, where each injection event flips consecutive bits within the
valid codeword region. Two sub-sections are presented: Section 4.3.1
analyses the BER performance curves at a representative burst length
(L=12), and Section 4.3.2 examines how each algorithm's error correction
capability degrades as the burst length increases from 1 to 15.

### 4.3.1 Performance at Representative Burst Length (L=12)

Figure 4.2 shows the decode success rate as a function of actual
injected BER for all algorithm configurations under cluster burst
injection with burst length L=12. This burst length was selected as the
representative case because it is long enough to challenge all
algorithms — including C-RRNS-MLD — while remaining within the valid
injection range for all codeword widths (see Table 3.4). Both FPGA
hardware measurement results and MATLAB simulation results are shown
side by side.

Figure 4.2 Decode success rate vs. actual BER — Cluster burst injection,
L=12 (FPGA vs MATLAB)

**Figure 4.2** Decode success rate vs. actual BER under cluster burst
fault injection (L=12, 100,000 samples per BER point). Solid lines: FPGA
hardware measurements; dashed lines: MATLAB simulation results.

**Key Observation 1: Performance Ranking at Elevated BER**

As BER increases beyond the low-BER plateau, the algorithms diverge in
performance. The observed ranking from best to worst is:

- **RS(12,4) and C-RRNS-MLD** achieve the highest resilience at elevated
  BER. RS(12,4) benefits from its t=4 symbol correction capability: a
  12-bit burst spanning at most 3 consecutive 4-bit symbols counts as
  only 3 symbol errors, well within the t=4 correction limit. C-RRNS-MLD
  benefits from its t=3 residue correction capability combined with the
  relatively wide residue fields of the C-RRNS moduli set (6–7 bits
  each): a 12-bit burst typically corrupts at most 2 residues, leaving
  one correction margin to spare.

- **3NRM-RRNS-MLD** ranks third, with a gradual degradation curve.
  Although 3NRM-RRNS and C-RRNS-MLD share the same theoretical
  correction capability (t=3 residues), their practical cluster fault
  tolerance differs significantly due to the difference in residue field
  widths. C-RRNS uses large redundant moduli {67, 71, 73, 79, 83, 89}
  with residue fields of 6–7 bits each, so a 12-bit burst typically
  corrupts at most 2 residues (12 bits / 6.5 bits per residue ≈ 1.8
  residues). In contrast, 3NRM-RRNS uses small redundant moduli {11, 17,
  19, 23, 29, 31} with residue fields of only 4–5 bits each, so the same
  12-bit burst is more likely to span 3 or more residue boundaries (12
  bits / 4.5 bits per residue ≈ 2.7 residues), occasionally exceeding
  the t=3 correction limit. This is an important limitation of
  3NRM-RRNS: despite having the same theoretical t value as C-RRNS, its
  smaller moduli set reduces the effective cluster fault tolerance in
  practice. The MLD algorithm itself is not less capable — the
  degradation arises from the moduli set design, not from any ambiguity
  or reduced Hamming distance discrimination in the MLD decision.

- **2NRM-RRNS Parallel and Serial** show similar performance at this
  burst length, both degrading more steeply than 3NRM-RRNS. With only
  t=2 correction capability and 6-bit residue fields, a 12-bit burst
  frequently corrupts 2 residues simultaneously, reaching the correction
  limit at a lower injected BER.

- **C-RRNS-MRC** degrades linearly from the outset, confirming that it
  provides no error correction capability under any burst length.

**Key Observation 2: FPGA vs. MATLAB Consistency**

As in the random single-bit case (Section 4.2), the FPGA hardware
results and MATLAB simulation results are in close agreement across all
algorithms and the full BER range. This consistency further validates
the correctness of both the hardware implementations and the MATLAB
simulation model under cluster burst injection conditions.

### 4.3.2 Impact of Burst Length on Error Correction Capability

To characterise how each algorithm's fault tolerance degrades as the
cluster burst length increases, the BER sweep was repeated for burst
lengths L = 5, 8, 12, and 15. To achieve the maximum cluster error
length that allows for 100% decoding success rate, different algorithms
were also tested with other length configurations. For each algorithm,
the maximum burst length at which 100% decode success is maintained
across the full 0–10% BER range is identified as the **maximum tolerable
burst length** — a key figure of merit for cluster fault tolerance.

Figures 4.3 through 4.7 show the decode success rate vs. BER curves for
each algorithm at all six burst lengths. The figures are ordered from
highest to lowest maximum tolerable burst length.

**C-RRNS-MLD**

Figure 4.3 Cluster length impact — C-RRNS-MLD

**Figure 4.3** Decode success rate vs. BER for C-RRNS-MLD at burst
lengths L = 5, 8, 12, 13,14,15.

C-RRNS-MLD maintains 100% success at all tested burst lengths up to
L=14, demonstrating the strongest cluster fault tolerance among all
evaluated algorithms.

**RS(12,4)**

Figure 4.4 Cluster length impact — RS(12,4)

**Figure 4.4** Decode success rate vs. BER for RS(12,4) at burst lengths
L = 5, 8, 12, 13,14，15.

RS(12,4) maintains 100% success up to L=13, after which performance
degrades at elevated BER.

**3NRM-RRNS-MLD**

Figure 4.5 Cluster length impact — 3NRM-RRNS

**Figure 4.5** Decode success rate vs. BER for 3NRM-RRNS at burst
lengths L = 5, 8,10,,11,12, 15.

3NRM-RRNS maintains 100% success up to L=11.

**2NRM-RRNS-MLD (Parallel)**

Figure 4.6 Cluster length impact — 2NRM-RRNS Parallel

**Figure 4.6** Decode success rate vs. BER for 2NRM-RRNS (Parallel) at
burst lengths L = 7,8,9,10,12,15.

The parallel implementation maintains 100% success up to L=7. For L = 8
and 9, the decoding success rate of the 2N-RRNS-MLD parallel scheme
reaches 99% or higher.

**2NRM-RRNS-MLD (Serial)**

Figure 4.7 Cluster length impact — 2NRM-RRNS Serial

**Figure 4.7** Decode success rate vs. BER for 2NRM-RRNS (Serial) at
burst lengths L = 5,6,7, 8, 12, 15.

The serial implementation maintains 100% success up to L=7, but the
performance of L = 8 is worse than the parallel implementation due to
the LFSR clustering effect described in Section 4.2.

**Summary Table**  
Table 4.2 summarises the maximum tolerable burst length for each
algorithm, ranked from highest to lowest.

**Table 4.2** Maximum burst length at which ~100% (≧99%) decode success
is maintained across the full 0–10% BER range (100,000 samples per BER
point)

| Algorithm                | Maximum Tolerable Burst Length (bits) |
|--------------------------|---------------------------------------|
| C-RRNS-MLD               | **14**                                |
| RS(12,4)                 | 13                                    |
| 3NRM-RRNS-MLD            | 11                                    |
| 2NRM-RRNS-MLD (Parallel) | 8                                     |
| 2NRM-RRNS-MLD (Serial)   | 7                                     |

**Analysis**  
The results in Table 4.2 reveal a clear correlation between the
theoretical error correction capability and the maximum tolerable burst
length:

- **C-RRNS-MLD** achieves the highest maximum tolerable burst length
  (L=14) among all evaluated algorithms. This is a direct consequence of
  its t=3 correction capability combined with the wide residue fields of
  the C-RRNS moduli set (6–7 bits per residue). A 14-bit burst spanning
  the 61-bit codeword typically corrupts at most 2–3 residues, which
  falls within the t=3 correction limit. This result confirms that
  C-RRNS-MLD provides the most robust cluster fault tolerance of all
  evaluated algorithms, and is the recommended choice for applications
  where the cluster burst length may approach or exceed the residue
  width.

- **RS(12,4)** achieves L=13, benefiting from its t=4 symbol correction
  capability. A 13-bit burst spanning the 48-bit codeword (12 × 4-bit
  symbols) corrupts at most 4 consecutive symbols, exactly at the
  correction limit. Beyond L=13, the burst begins to span 4 or more
  symbols with non-negligible probability, causing occasional decoding
  failures.

- **3NRM-RRNS-MLD** achieves L=11, consistent with its t=3 correction
  capability over 9 moduli with smaller redundant residue fields (4–5
  bits). The smaller residue widths mean that a given burst length is
  more likely to span multiple residue boundaries compared to C-RRNS,
  resulting in a lower maximum tolerable burst length despite the same
  theoretical correction capability.

- **2NRM-RRNS-MLD (Parallel)** achieves L=8, reflecting its t=2
  correction capability. With only 6-bit residue fields for the
  redundant moduli, a 7-bit burst can span at most 2 residues, which is
  exactly at the t=2 correction limit.

- **2NRM-RRNS-MLD (Serial)** achieves L=7, slightly lower than the
  Parallel implementation. This difference is attributable to the LFSR
  clustering effect described in Section 4.2: the Serial
  implementation's longer trial period (1,096 cycles) produces a more
  uniform distribution of burst starting positions, making it more
  likely that a given burst will land at a residue boundary and corrupt
  two residues simultaneously. The Parallel implementation's shorter
  trial period (73 cycles) produces clustered injection positions that
  tend to avoid residue boundaries, slightly inflating the measured
  maximum tolerable burst length. Both implementations are expected to
  converge to the same value under a truly independent injection model.

These results provide a comprehensive characterisation of the cluster
fault tolerance of all evaluated algorithms, and directly inform the
application scenario recommendations presented in Section 4.9.

## 4.4 Processing Latency Comparison

Figure 4.8 shows the average encoder and decoder latency (in clock
cycles at 50 MHz) for all six algorithm configurations.

<img src="media/rId53.png" style="width:5.83333in;height:3.1099in"
alt="dissertation/figure/latency_comparison.png" />

**Figure 4.8** Average encoder and decoder latency comparison (clock
cycles at 50 MHz, log scale). The figure uses a logarithmic scale to
visualise the two-orders-of-magnitude range; precise numerical values
are provided in Table 4.3.

**Operating Frequency**

As described in Section 3.2.1.5, all measurements in this work are
performed at **50 MHz** — the operating frequency at which all six
algorithm configurations achieve timing closure with positive slack.
This ensures that the latency and throughput figures in Table 4.3 are
directly comparable across all algorithms.

**Encoder Latency**

All algorithms exhibit similar encoder latencies in the range of 4–7
clock cycles (0.08–0.14 μs at 50 MHz). This confirms that the encoding
step is not a performance bottleneck for any of the evaluated
algorithms.

**Decoder Latency**

The decoder latency varies by more than two orders of magnitude across
the evaluated algorithms:

**Table 4.3** Encoder/decoder latency and throughput comparison of all
evaluated algorithm configurations (at 50 MHz, 16-bit data word).

| Algorithm | Enc (cycles) | Dec (cycles) | Total (cycles) | Total (μs) | Throughput (Mbps) |
|----|----|----|----|----|----|
| C-RRNS-MRC | 5 | 9 | 76 | 1.52 | 10.53 |
| 2NRM-RRNS (Parallel) | 7 | 24 | 73 | 1.46 | 10.96 |
| RS(12,4) | 4 | 127 | 133 | 2.66 | 6.02 |
| 2NRM-RRNS (Serial) | 7 | 1047 | 1056 | 21.12 | 0.76 |
| 3NRM-RRNS | 5 | 2048 | 3231 | 64.62 | 0.25 |
| C-RRNS-MLD | 5 | 928 | 995 | 19.90 | 0.80 |

**Throughput Analysis**

The throughput metric quantifies the rate at which 16-bit data words can
be processed through the complete encode–decode pipeline, and directly
reflects the hardware acceleration capability of each implementation.
The throughput is computed as:

where is the complete trial cycle count measured by the hardware
(including data generation, encoder, error injection, decoder, result
comparison, and FSM overhead), and . Note that for all algorithms due to
additional overhead cycles. This definition captures the true end-to-end
processing rate for a single data word, which is the relevant metric for
a memory read/write operation.

The 2NRM-RRNS parallel implementation achieves 10.96 Mbps — sufficient
to sustain a continuous data rate of approximately 685,000 16-bit memory
accesses per second. In contrast, C-RRNS-MLD, despite providing superior
fault tolerance, is limited to 0.80 Mbps due to its 928-cycle sequential
MLD decoder. The 13.7× throughput difference between 2NRM-RRNS Parallel
and C-RRNS-MLD highlights the fundamental trade-off between fault
tolerance and processing speed in RRNS-based ECC systems. C-RRNS-MRC
achieves 10.53 Mbps (76 total cycles including overhead) and RS(12,4)
achieves 6.02 Mbps (133 total cycles).

**Parallel vs. Serial 2NRM-RRNS**

The comparison between 2NRM-RRNS Parallel (73 total cycles) and
2NRM-RRNS Serial (1056 total cycles) directly quantifies the
resource-latency trade-off of the parallel MLD architecture. The
parallel implementation achieves a 14.5× reduction in total latency at
the cost of significantly higher resource utilisation, as discussed in
Section 4.5.

The C-RRNS-MLD decoder, despite providing the best fault tolerance
(near-100% success rate), incurs a decoder latency of 928 cycles (19.90
μs). This represents the fundamental trade-off between correction
capability and processing speed in the C-RRNS family.

**Why 3NRM-RRNS (2048 decoder cycles) is slower than C-RRNS-MLD (928
decoder cycles) despite both processing 84 triplets:** Both decoders use
the same sequential FSM structure, but differ critically in the number
of candidates evaluated per triplet. C-RRNS-MLD uses large redundant
moduli {67, 71, 73, 79, 83, 89}, so PERIOD = mi×mj×mk always exceeds
65,535 (minimum PERIOD = 67×71×73 = 347,381). Therefore X_base + PERIOD
always exceeds the 16-bit range, and each triplet produces exactly **1
candidate** (84 total). In contrast, 3NRM-RRNS uses small redundant
moduli {11, 17, 19, 23, 29, 31}, giving small PERIOD values (minimum
PERIOD = 19×17×11 = 3,553), requiring up to 18 additional k\>0
candidates per triplet (approximately 347 candidates total). The 2.2×
latency difference (2048 vs 928 cycles) directly reflects this ~4×
difference in total candidates evaluated, and is a fundamental
consequence of the moduli set design, not an FSM implementation
inefficiency.

## 4.5 Resource Utilisation Comparison

Figure 4.9 shows the FPGA resource utilisation for each algorithm
configuration on the Xilinx Artix-7 xc7a100t device.  
utilization_comparison.png

**Figure 4.9** FPGA resource utilisation comparison (LUT and FF: left
axis; DSP48E1 and BRAM: right axis).

The 2NRM-RRNS Parallel decoder dominates resource consumption, utilising
approximately 51% of available LUTs and 41% of flip-flops. This high
resource usage is a direct consequence of the 15-channel parallel MLD
architecture, which instantiates 15 independent CRT pipeline channels
simultaneously. All other algorithms consume less than 7% of available
LUTs, demonstrating that the sequential FSM approach is significantly
more resource-efficient.

The 2NRM-RRNS Serial decoder consumes only approximately 4% of available
LUTs — comparable to 3NRM-RRNS (7%) and C-RRNS-MLD (6%) — confirming the
resource-latency trade-off quantified in Section 4.4. The C-RRNS-MRC and
RS(12,4) decoders consume the fewest resources (2–3% LUT), reflecting
their simpler decoding architectures.

All algorithms consume approximately 21% of available BRAM tiles,
primarily due to the shared test infrastructure (threshold ROM, error
pattern ROM, and statistics buffer), which is independent of the
algorithm under test.

## 4.6 Power Consumption Analysis

Table 4.5 summarises the total on-chip power consumption for each
algorithm configuration, as estimated by the Xilinx Vivado Power
Analyser after implementation at 50 MHz on the Artix-7 xc7a100t device.
The reported figures represent **Total On-Chip Power**, which is the sum
of dynamic power (switching activity of logic and routing) and static
power (leakage current). Since all six algorithm configurations are
implemented on the same Artix-7 xc7a100t device with the same clock
frequency and share an identical test infrastructure (UART layer, fault
injection engine, statistics buffer, and control FSM), the static power
component is approximately equal across all configurations. Therefore,
the differences observed in Table 4.4 are primarily attributable to
differences in **dynamic power**, making the total power comparison a
valid proxy for comparing the dynamic power efficiency of each
algorithm's encoder/decoder logic.

**Table 4.4** Total on-chip power consumption estimated by Vivado Power
Analyser (50 MHz, Artix-7 xc7a100t).

| Algorithm            | Total Power (W) |
|----------------------|-----------------|
| 2NRM-RRNS (Parallel) | **0.58**        |
| 3NRM-RRNS            | 0.242           |
| C-RRNS-MLD           | 0.232           |
| 2NRM-RRNS (Serial)   | 0.223           |
| RS(12,4)             | 0.216           |
| C-RRNS-MRC           | 0.216           |

The most striking observation is that the 2NRM-RRNS Parallel decoder
consumes approximately **0.58 W** — nearly twice the power of all other
configurations (0.216–0.242 W). This elevated power consumption is a
direct consequence of the 15-channel parallel MLD architecture: all 15
CRT pipeline channels are active simultaneously on every clock cycle,
resulting in significantly higher dynamic switching activity compared to
the sequential FSM implementations. The 51% LUT utilisation and 41%
flip-flop utilisation of the parallel decoder (Section 4.5) translate
directly into higher dynamic power.

In contrast, the remaining five algorithm configurations exhibit
remarkably similar power consumption in the range of 0.216–0.235 W, a
spread of only 19 mW (approximately 9%). This near-uniformity arises
because the shared test infrastructure — the UART communication layer,
the fault injection engine (two Block RAMs), the statistics buffer, and
the control FSM — dominates the total power budget for these
low-LUT-utilisation implementations. The algorithm-specific logic
(encoder and decoder) contributes only a small fraction of the total
power for sequential implementations.

It should be noted that these figures represent Vivado's
post-implementation power estimates, which are based on switching
activity models rather than direct hardware measurement. The estimates
are accurate to within approximately ±20% for typical FPGA designs.
Furthermore, as discussed in Section 4.9 Limitations, the FPGA prototype
power figures are not directly comparable to ASIC implementations at
advanced process nodes (e.g., 28 nm), where the power consumption would
be orders of magnitude lower and the relative differences between
algorithms would be more pronounced.

## 4.7 Storage Efficiency Comparison

Figure 4.10 shows the codeword storage overhead for each algorithm
relative to the raw 16-bit data.

Figure 4.10 Storage efficiency comparison

**Figure 4.10** Storage overhead comparison: original 16-bit data (grey)
vs. ECC overhead (coloured), with storage efficiency on the right axis.

The 2NRM-RRNS algorithm achieves the highest storage efficiency at 39.0%
(41-bit codeword for 16-bit data), requiring only 25 additional bits of
overhead. In contrast, C-RRNS requires 45 additional bits (61-bit
codeword), yielding a storage efficiency of only 26.2%. The 3NRM-RRNS
and RS(12,4) algorithms both use 48-bit codewords, achieving a storage
efficiency of 33.3%.

This comparison highlights a key advantage of the 2NRM-RRNS algorithm:
it achieves t=2 error correction with the smallest storage overhead of
any correcting algorithm in this study, making it particularly
attractive for memory-constrained applications.

## 4.8 Overall Comparison and Conclusions

Table 4.5 provides a consolidated comparison of all six algorithm
configurations across the four evaluation dimensions.

**Table 4.5** Consolidated performance comparison of all evaluated
algorithm configurations.

<table style="width:85%;">
<colgroup>
<col style="width: 10%" />
<col style="width: 10%" />
<col style="width: 10%" />
<col style="width: 10%" />
<col style="width: 10%" />
<col style="width: 10%" />
<col style="width: 10%" />
<col style="width: 10%" />
</colgroup>
<thead>
<tr>
<th>Algorithm</th>
<th>Success Rate (CLUSTER L=12, BER=10%)</th>
<th>Throughput (Mbps)</th>
<th>Decoder Latency (cycles)</th>
<th>LUT Utilisation</th>
<th>Power (W)</th>
<th>Storage Efficiency</th>
<th>Error Correction</th>
</tr>
</thead>
<tbody>
<tr>
<td>C-RRNS-MLD</td>
<td><strong>100%</strong></td>
<td>0.80</td>
<td>928</td>
<td>~6%</td>
<td>0.232</td>
<td>26.2%</td>
<td>t=3</td>
</tr>
<tr>
<td>3NRM-RRNS</td>
<td>96%</td>
<td>0.25</td>
<td>2048</td>
<td>~7%</td>
<td>0.242</td>
<td>33.3%</td>
<td>t=3</td>
</tr>
<tr>
<td>RS(12,4)</td>
<td>100%</td>
<td>6.02</td>
<td>127</td>
<td>~3%</td>
<td>0.216</td>
<td>33.3%</td>
<td>t=4 symbols</td>
</tr>
<tr>
<td>2NRM-RRNS (Parallel)</td>
<td>~95%<br />
Degrades linearly</td>
<td><strong>10.96</strong></td>
<td><strong>24</strong></td>
<td>51%</td>
<td><strong>0.58</strong></td>
<td><strong>39.0%</strong></td>
<td>t=2</td>
</tr>
<tr>
<td>2NRM-RRNS (Serial)</td>
<td>~79%<br />
Degrades linearly</td>
<td>0.76</td>
<td>1047</td>
<td>~4%</td>
<td>0.223</td>
<td><strong>39.0%</strong></td>
<td>t=2</td>
</tr>
<tr>
<td>C-RRNS-MRC</td>
<td>81%<br />
Degrades linearly</td>
<td>10.53</td>
<td>9</td>
<td>~2%</td>
<td>0.216</td>
<td>26.2%</td>
<td>None</td>
</tr>
</tbody>
</table>

*Throughput = 16 bits / Total_Clk × 50 MHz, where Total_Clk is the
complete trial cycle count measured by the hardware auto_scan_engine
(includes data generation, encoder, error injection, decoder, result
comparison, and FSM overhead). Total_Clk \> Enc + Dec for all
algorithms. For 3NRM-RRNS, the overhead is ~1178 cycles (3231 - 5 -
2048) because the sequential FSM requires many state transitions per
trial (84 triplets x multiple k\>0 candidates each). The data is
internally consistent: 16/3231 x 50 = 0.247 Mbps. Power = Vivado
post-implementation estimate. See Table 4.3 for latency details and
Table 4.4 for power details.*

The results demonstrate that no single algorithm dominates across all
dimensions, and the optimal choice depends on the application
requirements:

- **Maximum fault tolerance**: C-RRNS-MLD and RS are the clear choices,
  providing 100% recovery under max 14 cluster length and max 13 cluster
  length across the full 0–10% BER range.

- **Best storage efficiency with error correction**: 2NRM-RRNS (either
  parallel or serial) offers the best storage efficiency (39.0%) among
  correcting algorithms, with t=2 correction capability. The parallel
  implementation provides the lowest decode latency (24 cycles) at the
  cost of high resource utilisation (51% LUT); the serial implementation
  reduces resource usage to ~4% LUT at the cost of a 43× increase in
  decode latency.

- **Lowest latency with correction**: RS(12,4) provides t=4 symbol
  correction with a moderate decode latency of 127 cycles and a 33.3%
  storage efficiency, making it a balanced choice for latency-sensitive
  applications.

- **Lowest latency overall**: C-RRNS-MRC (9 cycles) achieve the lowest
  decode latencies but provide no error correction capability, making it
  suitable only for applications where fault detection (rather than
  correction) is sufficient.

**Table 4.6** Application scenario recommendations based on the
evaluation results.

<table style="width:85%;">
<colgroup>
<col style="width: 21%" />
<col style="width: 21%" />
<col style="width: 21%" />
<col style="width: 21%" />
</colgroup>
<thead>
<tr>
<th>Application Scenario</th>
<th>Primary Constraint</th>
<th>Recommended Algorithm</th>
<th>Rationale</th>
</tr>
</thead>
<tbody>
<tr>
<td>High-reliability systems (aerospace, medical)</td>
<td>Fault tolerance</td>
<td><strong>C-RRNS-MLD</strong> or<br />
<strong>RS</strong></td>
<td>100% recovery across 0–10% BER; t=3, 4 correction handles most burst
faults</td>
</tr>
<tr>
<td>Storage-constrained devices (edge computing, IoT)</td>
<td>Codeword overhead</td>
<td><strong>2NRM-RRNS (Parallel)</strong></td>
<td>Smallest codeword (41 bits, 39.0% efficiency) with t=2 correction
and 10.96 Mbps throughput (73 total cycles)</td>
</tr>
<tr>
<td>Latency-sensitive systems (real-time memory controllers)</td>
<td>Processing speed</td>
<td><strong>RS(12,4)</strong> or <strong>2NRM-RRNS
(Parallel)</strong></td>
<td>RS: 6.02 Mbps with t=4 symbol correction; 2NRM-Parallel: 10.96 Mbps
with t=2 correction</td>
</tr>
<tr>
<td>Resource-constrained FPGAs (low-cost devices)</td>
<td>LUT utilisation</td>
<td><strong>2NRM-RRNS (Serial)</strong></td>
<td>~4% LUT (vs. 51% for parallel), same BER performance, 0.76 Mbps
throughput (1056 total cycles)</td>
</tr>
<tr>
<td>Balanced general-purpose use</td>
<td>All dimensions</td>
<td><strong>RS(12,4)</strong></td>
<td>Moderate latency (127 cycles), highest correction capability (t=4),
33.3% storage efficiency</td>
</tr>
</tbody>
</table>

**Implementation Complexity and Maintainability**

Beyond the four quantitative evaluation dimensions, a fifth dimension —
**implementation complexity and maintainability** — is relevant for
practical deployment decisions. Table 4.6 captures performance metrics,
but does not reflect the engineering effort required to implement,
verify, and maintain each algorithm.

Table 4.7 provides a qualitative comparison of implementation complexity
against fault tolerance capability for all evaluated algorithm families.

**Table 4.7** Qualitative comparison of implementation complexity vs.
fault tolerance for each algorithm family.

| Algorithm | Implementation Complexity | Verification Effort | Ecosystem Maturity | Max Tolerable Burst (bits) | Recommended Scenario |
|----|----|----|----|----|----|
| RS(12,4) | Low | Low (reference IPs available) | Very High (decades of standardisation) | 13 | General-purpose, balanced |
| C-RRNS-MRC | Low | Low (direct arithmetic) | Low (custom) | 0 (no correction) | Detection-only, ultra-low latency |
| 2NRM-RRNS (Serial) | Medium | Medium (MLD FSM verification) | Low (custom) | 7 | Resource-constrained, storage-critical |
| 3NRM-RRNS (MLD) | Medium-High | High (84-triplet LUT validation) | Low (custom) | 11 | Balanced cluster tolerance |
| 2NRM-RRNS (Parallel) | High | High (15-channel pipeline timing) | Low (custom) | 8 | Latency-critical, storage-critical |
| C-RRNS-MLD | High | High (84-triplet LUT + wide moduli) | Low (custom) | 14 | Maximum cluster fault tolerance |

RS(12,4) benefits from decades of standardisation and mature IP core
support: commercial and open-source RS encoder/decoder implementations
are widely available, and the Berlekamp-Massey algorithm is
well-documented in textbooks and hardware design guides. In contrast,
the RRNS-based algorithms — particularly the sequential FSM MLD decoders
(C-RRNS-MLD, 3NRM-RRNS, and 2NRM-RRNS Serial) and the 15-channel
parallel MLD pipeline (2NRM-RRNS Parallel) — require custom
implementation of modular arithmetic pipelines, CRT reconstruction
engines, and Hamming distance reduction trees, all of which must be
verified from scratch. The 2NRM-RRNS parallel decoder, for example,
required approximately 30 rounds of timing optimisation to approach 100
MHz closure, and ultimately required a frequency reduction to 50 MHz.
This development overhead is a genuine engineering cost that must be
weighed against the storage efficiency and latency advantages of RRNS
codes.

The unified wrapper architecture developed in this work partially
mitigates this overhead by isolating algorithm-specific logic from the
test infrastructure. However, the verification burden for each new RRNS
variant remains significant: the MLD decoding algorithm requires
exhaustive simulation across all possible error patterns and data values
to confirm correctness, and the pre-computed ROM tables
(threshold_table.coe and error_lut.coe) must be regenerated and
validated whenever the algorithm parameters change. In contrast,
RS(12,4) can be verified against well-established reference
implementations with minimal effort.

This analysis suggests that, for applications where RS(12,4) provides
sufficient fault tolerance, its mature ecosystem and lower
implementation complexity make it the pragmatic choice. RRNS-based
algorithms are most attractive in scenarios where the specific
advantages of storage efficiency (2NRM-RRNS Serial or Parallel) or
cluster burst tolerance (C-RRNS-MLD) cannot be matched by RS codes, and
where the engineering team has the expertise to implement and verify
custom modular arithmetic hardware.

## 4.9 Conclusions and Further Work

This work has demonstrated the feasibility of implementing and
evaluating multiple redundant number system (RNS) based ECC algorithms
on an FPGA platform. The key conclusions are:

1.  **C-RRNS-MLD demonstrates extremely high fault tolerance**, with no
    observed decoding failures across 100,000 samples per BER point
    under cluster burst lengths up to L=14 within the tested 0–10% BER
    range, confirming its suitability as a high-reliability storage
    solution for hybrid CMOS/non-CMOS memory systems. This behaviour is
    consistent with its theoretical t=3 correction capability; however,
    rare worst-case alignment patterns are not exhaustively covered by
    the probabilistic injection model.

2.  **2NRM-RRNS offers the best storage efficiency** among correcting
    algorithms (39.0%), with the parallel implementation achieving a
    decoder latency of only 24 clock cycles — the lowest among all
    correcting algorithms evaluated.

3.  **The parallel vs. serial 2NRM-RRNS comparison** directly quantifies
    the resource-latency trade-off of parallel MLD architectures: a 15×
    latency reduction at the cost of approximately 13× higher LUT
    utilisation.

4.  **The probabilistic fault injection engine** developed in this work
    enables flexible, statistically rigorous BER testing with arbitrary
    sample counts, using only two Block RAMs for the entire injection
    subsystem.

5.  **The wrapper-based extensibility architecture** allows new ECC
    algorithms to be added to the test platform with minimal engineering
    effort, requiring only the implementation of the codec module
    itself.

**Summary of Contributions**  
The contributions of this work can be categorised into three
dimensions:  
**Theoretical contributions**: This work provides the first
hardware-validated confirmation that C-RRNS-MLD achieves 100% decode
success under cluster error across the 0–10% BER range — a result that
was theoretically expected but had not previously been verified on
physical hardware.  
**Engineering contributions**: The FPGA-based evaluation platform,
including the probabilistic fault injection engine and the unified
encoder/decoder wrapper architecture, constitutes a reusable open-source
tool for ECC algorithm benchmarking. The parallel and serial
implementations of 2NRM-RRNS provide a directly comparable pair of
architectures that quantify the resource-latency trade-off of parallel
MLD on a real FPGA device.  
**Methodological contributions**: The probabilistic fault injection
methodology — using a 32-bit Galois LFSR with offline-precomputed ROM
tables — enables statistically rigorous BER testing with arbitrary
sample counts and configurable burst lengths, using only two Block RAMs.
This approach is algorithm-agnostic and can be directly applied to
evaluate any future ECC algorithm on the same platform.

**Limitations**  
This work has several limitations that should be acknowledged:

1.  **Data word width**: All evaluations are performed on 16-bit data
    words, consistent with the reference work \[1\]. The scalability of
    the RRNS algorithms and the FPGA platform to wider data words (e.g.,
    32-bit or 64-bit) has not been evaluated. Wider data words require
    larger moduli sets and longer codewords, with significant
    implications for both resource utilisation and timing closure. For a
    32-bit data word, the 2NRM-RRNS moduli set would need to be
    redesigned with ; a candidate set is , yielding . The non-redundant
    residues would require 17 and 17 bits respectively, and the
    redundant moduli would need to be selected to satisfy , resulting in
    a codeword of approximately 80–90 bits. The parallel MLD decoder,
    which already required 51% LUT utilisation for the 16-bit case,
    would instantiate 15 CRT channels operating on 17-bit arithmetic —
    estimated to require approximately 2–3× the current LUT count,
    likely exceeding the capacity of the Artix-7 xc7a100t device. The
    serial implementation would scale more gracefully, with resource
    usage growing approximately linearly with the modulus bit width. For
    RS codes, scaling to 32-bit data is straightforward: an RS(24, 8)
    code over GF(2⁴) would provide t=8 symbol correction with a 96-bit
    codeword, and the Berlekamp-Massey decoder complexity scales as ,
    resulting in approximately 4× the current decoder latency. These
    scalability considerations suggest that the serial RRNS
    implementations and RS codes are better suited for wider data word
    applications, while the parallel RRNS architecture would require
    significant architectural redesign or migration to a larger FPGA
    device.
2.  **Fault model**: The fault injection model is based on a
    probabilistic distribution (LFSR-driven threshold comparison), which
    approximates the statistical properties of real device faults but
    does not use measured fault data from actual hybrid CMOS/non-CMOS
    memory devices. Validation against real device fault traces would
    strengthen the practical relevance of the results.
3.  **LFSR local correlation in high-throughput mode**: The 32-bit
    Galois LFSR used for fault injection advances by one step per clock
    cycle. For the 2NRM-RRNS Parallel decoder (73 total cycles per
    trial), consecutive trials use LFSR states that are only 73 steps
    apart, introducing local linear correlations between adjacent
    injection patterns. This causes error positions to cluster within
    the same residue fields across consecutive trials, artificially
    inflating the measured success rate of the Parallel implementation
    relative to the Serial implementation (1056 cycles per trial, weaker
    correlation). As identified and analysed in Section 4.2, this is a
    hardware injection model artefact rather than a genuine algorithmic
    performance difference. A higher-quality pseudo-random number
    generator (e.g., Mersenne Twister MT19937) would eliminate this
    correlation, but its implementation in hardware would require
    significantly more FPGA resources. The MATLAB simulation results
    (which use independent random seeds per trial) serve as the ground
    truth for cross-algorithm comparison and are unaffected by this
    limitation.
4.  **Power consumption**: Post-implementation power estimates from the
    Vivado Power Analyser are reported in Section 4.6 (Table 4.4). The
    results show that five of the six configurations consume 0.216–0.242
    W, with the 2NRM-RRNS Parallel decoder consuming approximately 0.58
    W due to its 15-channel parallel architecture. However, these
    figures represent Vivado's switching-activity-based estimates
    (accurate to ±20%) rather than direct hardware measurements, and are
    not directly comparable to ASIC implementations at advanced process
    nodes (e.g., 28 nm), where the power consumption would be orders of
    magnitude lower and the relative differences between algorithms
    would be more pronounced.
5.  **Engineering practicality of RRNS implementations**: While
    RRNS-based algorithms demonstrate strong fault tolerance and storage
    efficiency advantages, their practical deployment is constrained by
    significantly higher implementation and verification complexity
    compared to RS codes. The need for custom modular arithmetic
    pipelines, CRT reconstruction, and exhaustive validation introduces
    non-trivial engineering overhead, which may outweigh performance
    benefits in cost-sensitive or time-constrained industrial
    applications.

**Further Work**  
**Near-term extensions (directly achievable):**

- **Parallel C-RRNS-MLD**: Implementing a parallel version of the
  C-RRNS-MLD decoder (analogous to the 2NRM-RRNS parallel
  implementation) could reduce the decode latency from 928 cycles to
  approximately 10–15 cycles, at the cost of significantly higher
  resource utilisation. This would make C-RRNS-MLD competitive with
  RS(12,4) in latency while maintaining its superior fault tolerance.  
  **Medium-term directions (requiring additional resources):**
- **ASIC implementation and power analysis**: Implementing the evaluated
  algorithms in a 28 nm or 45 nm CMOS process would enable meaningful
  power consumption comparison and provide data relevant to practical
  memory controller integration. ASIC implementation would also remove
  the FPGA-specific timing constraints that limited the operating
  frequency to 50 MHz in this work.
- **Integration with real memory devices**: Integrating the ECC platform
  with an actual hybrid CMOS/non-CMOS memory interface (e.g., a
  resistive RAM or phase-change memory array) would validate the results
  under realistic operating conditions and provide fault data for
  calibrating the probabilistic injection model.
- **Higher-order RRNS**: Extending the moduli set to support t=4 or t=5
  correction capability would further improve fault tolerance at the
  cost of increased codeword length, enabling a more complete
  exploration of the RRNS design space.  
  **Long-term research directions:**
- **Adaptive ECC**: Developing a system that dynamically switches
  between ECC algorithms based on real-time BER measurements would allow
  the memory controller to trade off fault tolerance, latency, and
  storage efficiency according to the current operating conditions. The
  unified wrapper architecture developed in this work provides a natural
  foundation for such a system.
- **Machine learning-assisted fault prediction**: Applying machine
  learning techniques to predict fault patterns from historical BER data
  could enable proactive ECC selection and pre-emptive data migration
  before fault rates exceed the correction capability of the active
  algorithm.

# Chapter 5 Economic, Legal, Social, Ethical and Environmental Context

## 5.1 Economic Context

The development of reliable fault-tolerant memory systems has
significant economic implications for the semiconductor and data storage
industries. Hybrid CMOS/non-CMOS memories are projected to enable
ultra-high-density storage at reduced cost per bit compared to
conventional DRAM and NAND flash technologies. The ECC algorithms
evaluated in this work — particularly 2NRM-RRNS, which achieves the
highest storage efficiency (39.0%) — directly reduce the storage
overhead required for fault protection, translating to lower
manufacturing cost per usable bit. The FPGA-based evaluation platform
developed in this project provides a cost-effective methodology for
algorithm benchmarking that avoids the need for expensive ASIC tape-outs
during the research phase. The open-source nature of the Verilog
implementations further reduces the barrier to adoption for academic and
industrial researchers.

## 5.2 Legal and Intellectual Property Context

The algorithms evaluated in this work are based on published academic
research \[1, 2\], and the FPGA implementations developed here
constitute original engineering work. The Xilinx Vivado design suite
used for synthesis and implementation is subject to a commercial
licence, though the Arty A7-100T development board and associated IP
cores are available under standard academic licensing terms. The Verilog
source code produced in this project is intended for open-source release
under a permissive licence (e.g., MIT or Apache 2.0), consistent with
the academic contribution goals stated in Section 1.3. No patent claims
are made on the algorithms themselves, as the underlying mathematical
principles (RNS, RRNS, MLD) are well-established in the public domain.

## 5.3 Social and Ethical Context

Reliable data storage is a fundamental requirement for modern digital
infrastructure, including healthcare records, financial systems, and
critical communications. The cluster fault tolerance techniques
evaluated in this work address a genuine reliability challenge in
next-generation memory technologies, contributing to the broader goal of
dependable computing systems. From an ethical standpoint, the
probabilistic fault injection methodology used in this work is designed
to be statistically rigorous and reproducible, ensuring that the
performance comparisons presented in Chapter 4 are fair and unbiased.
All experimental data was collected using the same hardware platform and
test conditions, and the source code is made available to enable
independent verification of the results.

## 5.4 Environmental Context

The environmental impact of this project is primarily associated with
the energy consumption of the FPGA development board during testing. The
Arty A7-100T board consumes approximately 1–3 W during operation, and
the total testing time across all six algorithm configurations amounts
to a negligible energy consumption of less than 0.1 kWh. The use of an
FPGA platform, rather than a custom ASIC, avoids the significant
environmental cost of semiconductor fabrication (photolithography,
chemical etching, and wafer processing). Furthermore, the probabilistic
fault injection engine developed in this work enables comprehensive BER
testing with minimal hardware resources (two Block RAMs), reducing the
need for large-scale memory arrays in the evaluation setup. The
long-term environmental benefit of this research lies in enabling more
reliable hybrid memories, which can reduce the frequency of data
corruption events and the associated energy cost of error recovery and
data re-transmission in storage systems.

## 5.5 Safety and Risk Context

This project involves standard electronic engineering laboratory
practice with no significant health or safety risks beyond those
associated with general electronics work (electrostatic discharge
precautions, safe handling of development boards). The FPGA platform
operates at standard logic voltages (3.3 V) and poses no electrical
hazard under normal operating conditions. The fault injection
methodology is implemented entirely in software and hardware simulation
— no physical memory devices are subjected to destructive testing.

# References

\[1\] N. Z. Haron and S. Hamdioui, "Using RRNS Codes for Cluster Faults
Tolerance in Hybrid Memories," *2009 24th IEEE International Symposium
on Defect and Fault Tolerance in VLSI Systems*, 2009, pp. 85–93. doi:
10.1109/DFT.2009.37.  
\[2\] V. T. Goh and M. U. Siddiqi, "Multiple Error Detection and
Correction based on Redundant Residue Number Systems," *IEEE
Transactions on Communications*, vol. 56, no. 3, pp. 325–330, March
2008.  
\[3\] A. Kumar et al., "FPGA-Based RRNS Decoder for Nanoscale Memory
Systems," *IEEE Transactions on Very Large Scale Integration (VLSI)
Systems*, vol. 30, no. 5, pp. 789–793, May 2022.  
\[4\] F. Barsi and P. Maestrini, "Error Detection and Correction by
Means of Redundant Residue Number Systems," *IEEE Transactions on
Computers*, vol. C-23, no. 3, pp. 307–315, Mar. 1974.  
\[5\] M. A. Soderstrand, W. K. Jenkins, G. A. Jullien, and F. J. Taylor,
*Residue Number System Arithmetic: Modern Applications in Digital Signal
Processing*. New York, NY, USA: IEEE Press, 1986.  
\[6\] M. B. Kalantar, M. R. Ebrahimi, and A. Ejlali, "Efficient
RRNS-Based Error Control Codes for Non-Volatile Memories," *IEEE
Transactions on Circuits and Systems I: Regular Papers*, vol. 68, no. 5,
pp. 1987–1998, May 2021.  
\[7\] Y. Wang and M. H. Azarderakhsh, "Maximum-Likelihood Decoding for
RRNS-Based Fault-Tolerant Systems," in *Proceedings of the IEEE
International Symposium on Circuits and Systems (ISCAS)*, 2022, pp.
2105–2109.  
\[8\] L. Xiao and J. Hu, "A Survey on Residue Number System: Theory,
Applications, and Challenges," *ACM Computing Surveys*, vol. 55, no. 4,
Art. no. 78, pp. 1–36, Apr. 2023.  
\[9\] D. B. Strukov and K. K. Likharev, "Prospects for terabit-scale
nanoelectronic memories," *Nanotechnology*, vol. 16, pp. 137–148,
2005.  
\[10\] F. Sun and T. Zhang, "Defect and Transient Fault Tolerant System
Design for Hybrid CMOS/Nanodevice Digital Memories," *IEEE Transactions
on Nanotechnology*, vol. 6, no. 3, pp. 341–351, May 2007.  
\[11\] D. B. Strukov and K. K. Likharev, "Architectures for
defect-tolerant nanoelectronic crossbar memories," *Nanotechnology*,
vol. 7, pp. 151–167, 2007.  
\[12\] J. D. Sun and H. Krishna, "A coding theory approach to error
control in redundant residue number system — Part II: multiple error
detection and correction," *IEEE Transactions on Circuits and Systems*,
vol. 39, pp. 18–34, Jan. 1992.  
\[13\] L. Yang and L. Hanzo, "Redundant Residue Number System Based
Error Correction Codes," in *Proceedings of the IEEE Vehicular
Technology Conference*, pp. 1472–1476, Oct. 2001.  
\[14\] Xilinx Inc., *Vivado Design Suite User Guide: Synthesis*, UG901,
v2023.2, San Jose, CA, USA, 2023.  
\[15\] Digilent Inc., *Arty A7 Reference Manual*, Pullman, WA, USA,
2023. \[Online\]. Available:
<https://digilent.com/reference/programmable-logic/arty-a7/reference-manual>

# Appendices

## Appendix A: Algorithm Overview and Comparison

The following table provides a consolidated reference for all ECC
algorithms implemented in this work.

| Algorithm | Moduli Set | Codeword (bits) | Data (bits) | Overhead (bits) | Error Correction | Decoder Architecture |
|----|----|----|----|----|----|----|
| 2NRM-RRNS | {257, 256, 61, 59, 55, 53} | 41 | 16 | 25 | t=2 residues | Parallel MLD / Serial FSM |
| 3NRM-RRNS | {64, 63, 65, 31, 29, 23, 19, 17, 11} | 48 | 16 | 32 | t=3 residues | Sequential FSM MLD |
| C-RRNS | {64, 63, 65, 67, 71, 73, 79, 83, 89} | 61 | 16 | 45 | t=3 residues (MLD) / None (MRC, CRT) | MLD / MRC / CRT |
| RS(12,4) | GF(2⁴), generator polynomial | 48 | 16 | 32 | t=4 symbols | BM + Chien + Forney |

**Notation used in pseudocode below:**

- `mod` denotes the modulo operation
- `Inv(a, m)` denotes the modular inverse of `a` modulo `m`, i.e., the
  value `x` such that `a·x ≡ 1 (mod m)`
- `argmin` denotes the argument that minimises the given expression
- `HammingDist(a, b)` counts the number of positions where vectors `a`
  and `b` differ

## Appendix B: 2NRM-RRNS Encoder

The 2NRM-RRNS encoder computes the residue representation of a 16-bit
data word with respect to the moduli set {257, 256, 61, 59, 55, 53}.

    Algorithm B.1: 2NRM-RRNS Encoding
    ─────────────────────────────────────────────────────────────────
    Input:  data ∈ [0, 65535]  (16-bit unsigned integer)
    Output: codeword = (r₀, r₁, r₂, r₃, r₄, r₅)
            where rᵢ = data mod mᵢ

    Moduli set: m₀=257, m₁=256, m₂=61, m₃=59, m₄=55, m₅=53

    1.  r₀ ← data mod 257        // 9-bit residue, range [0, 256]
    2.  r₁ ← data mod 256        // 8-bit residue, range [0, 255]
    3.  r₂ ← data mod 61         // 6-bit residue, range [0, 60]
    4.  r₃ ← data mod 59         // 6-bit residue, range [0, 58]
    5.  r₄ ← data mod 55         // 6-bit residue, range [0, 54]
    6.  r₅ ← data mod 53         // 6-bit residue, range [0, 52]
    7.  return (r₀, r₁, r₂, r₃, r₄, r₅)

    Codeword packing (41 bits, right-aligned in 64-bit bus):
      bits [40:32] = r₀  (9 bits)
      bits [31:24] = r₁  (8 bits)
      bits [23:18] = r₂  (6 bits)
      bits [17:12] = r₃  (6 bits)
      bits [11:6]  = r₄  (6 bits)
      bits [5:0]   = r₅  (6 bits)
    ─────────────────────────────────────────────────────────────────

**FPGA implementation note:** The modulo operations are implemented as
pipelined combinational logic. The modulo by 256 is trivial (lower 8
bits). The modulo by 257 uses the identity 256 ≡ −1 (mod 257),
decomposed into a two-step pipeline to meet 50 MHz timing. Total encoder
latency: 7 clock cycles.

## Appendix C: 2NRM-RRNS Decoder — Parallel MLD Implementation

The parallel MLD decoder instantiates 15 independent CRT channels, one
for each pair of moduli from C(6,2)=15. Each channel reconstructs a
candidate value and computes its Hamming distance to the received
residues. The channel with minimum distance wins.

    Algorithm C.1: 2NRM-RRNS Parallel MLD Decoding (Final Verified Implementation)
    ─────────────────────────────────────────────────────────────────
    Input:  received = (r̃₀, r̃₁, r̃₂, r̃₃, r̃₄, r̃₅)  (possibly corrupted)
    Output: data_out  (recovered 16-bit integer)
            uncorrectable  (flag: true if min distance > 2)

    Pre-computed constants for each pair (i, j):
      Inv_ij = Inv(mᵢ mod mⱼ, mⱼ)   (modular inverse)
      PERIOD_ij = mᵢ × mⱼ

      Verified pair constants (15 pairs from C(6,2)):
      Pair (0,1): M1=257, M2=256, Inv=1,  PERIOD=65792
      Pair (0,2): M1=257, M2=61,  Inv=47, PERIOD=15677  [Note: Inv=47, not 48]
      Pair (0,3): M1=257, M2=59,  Inv=45, PERIOD=15163
      Pair (0,4): M1=257, M2=55,  Inv=3,  PERIOD=14135
      Pair (0,5): M1=257, M2=53,  Inv=33, PERIOD=13621
      Pair (1,2): M1=256, M2=61,  Inv=56, PERIOD=15616
      Pair (1,3): M1=256, M2=59,  Inv=3,  PERIOD=15104
      Pair (1,4): M1=256, M2=55,  Inv=26, PERIOD=14080
      Pair (1,5): M1=256, M2=53,  Inv=47, PERIOD=13568
      Pair (2,3): M1=61,  M2=59,  Inv=30, PERIOD=3599
      Pair (2,4): M1=61,  M2=55,  Inv=46, PERIOD=3355
      Pair (2,5): M1=61,  M2=53,  Inv=20, PERIOD=3233
      Pair (3,4): M1=59,  M2=55,  Inv=14, PERIOD=3245
      Pair (3,5): M1=59,  M2=53,  Inv=9,  PERIOD=3127
      Pair (4,5): M1=55,  M2=53,  Inv=27, PERIOD=2915

    Step 1 — CRT Reconstruction (for each of 15 pairs in parallel):
      For each pair (i, j) where 0 ≤ i < j ≤ 5:
        // Bug #101 fix: add 5×mⱼ before subtraction to prevent unsigned underflow
        // when r̃ᵢ > mⱼ (e.g., r̃ᵢ=200, mⱼ=53: 10+53-200=-137 wraps incorrectly)
        diff_wide ← r̃ⱼ + 5×mⱼ − r̃ᵢ        // always positive: max = (mⱼ-1)+5mⱼ = 6mⱼ-1
        diff      ← diff_wide mod mⱼ         // range [0, mⱼ-1]
        coeff_raw ← diff × Inv_ij            // LUT multiply (8-bit × 6-bit = 14-bit)
        coeff     ← coeff_raw mod mⱼ         // range [0, mⱼ-1]
        // Bug #39 fix: clamp x_cand to 16-bit range
        x_cand_raw ← r̃ᵢ + mᵢ × coeff       // may exceed 65535 for large mᵢ
        X_base     ← min(x_cand_raw, 65535)

    Step 2 — Multi-Candidate Enumeration (for each pair):
      // Bug #102 fix: extend from k=0..4 to k=0..22 to cover all 16-bit X values
      // for small-PERIOD pairs (e.g., pair (4,5): PERIOD=2915, needs k up to 22)
      For k = 0, 1, 2, ..., 22:
        X_k ← X_base + k × PERIOD_ij
        if X_k > 65535: break  // out of 16-bit range

    Step 3 — Hamming Distance Computation (for each valid candidate X_k):
      cand_r ← (X_k mod 257, X_k mod 256, X_k mod 61,
                 X_k mod 59,  X_k mod 55,  X_k mod 53)
      dist_k ← HammingDist(cand_r, received)

    Step 4 — MLD Selection (across all 15 × up-to-23 = up-to-345 candidates):
      (best_X, min_dist) ← argmin_{all valid X_k} dist_k
      // Tie-breaking: lower pair index (lower k) wins

    Step 5 — Output:
      if min_dist ≤ 2:
        return best_X, uncorrectable=false
      else:
        return 0, uncorrectable=true
    ─────────────────────────────────────────────────────────────────

**FPGA implementation note:** All 15 CRT channels are instantiated
simultaneously as independent pipeline instances. Each channel
implements a multi-stage pipeline (Stages 1a through 3b). The deep
pipeline structure was necessitated by the original 100 MHz timing
target: the parallel MLD architecture with 15 simultaneous CRT channels
creates long combinational paths (modular arithmetic, Hamming distance
reduction trees) that required iterative pipeline splitting across
approximately 30 optimisation rounds. Despite these efforts, 100 MHz
timing closure could not be achieved, and the operating frequency was
reduced to 50 MHz. The pipeline depth therefore reflects the complexity
of the 100 MHz design intent rather than a requirement of 50 MHz
operation. The diff_raw computation uses 5×P_M2 addition before
subtraction to prevent unsigned arithmetic underflow (Bug \#101 fix).
Candidate enumeration extends to k=0..22 to cover all valid 16-bit X
values for small-PERIOD modulus pairs (Bug \#102 fix). The MLD selection
uses a balanced binary reduction tree across all 23 candidates per
channel. Total decoder latency: 24 clock cycles.

## Appendix D: 2NRM-RRNS Decoder — Serial FSM Implementation

The serial FSM decoder implements the same MLD algorithm as Appendix C,
but processes the 15 modulus pairs sequentially using a single shared
CRT engine.

    Algorithm D.1: 2NRM-RRNS Serial FSM MLD Decoding
    ─────────────────────────────────────────────────────────────────
    Input:  received = (r̃₀, r̃₁, r̃₂, r̃₃, r̃₄, r̃₅)
    Output: data_out, uncorrectable

    Initialise: min_dist ← 6,  best_X ← 0

    For pair_idx = 0 to 14:  // iterate over all 15 modulus pairs
      (i, j) ← pair_table[pair_idx]
      mᵢ, mⱼ, Inv_ij, PERIOD_ij ← lut[pair_idx]

      // CRT reconstruction (same as Algorithm C.1, Steps 1-2)
      diff   ← (r̃ⱼ − r̃ᵢ + mⱼ) mod mⱼ
      coeff  ← (diff × Inv_ij) mod mⱼ
      X_base ← r̃ᵢ + mᵢ × coeff

      For k = 0 to 4:  // enumerate up to 5 candidates
        X_k ← X_base + k × PERIOD_ij
        if X_k > 65535: break

        // Compute Hamming distance
        cand_r ← (X_k mod 257, X_k mod 256, X_k mod 61,
                   X_k mod 59,  X_k mod 55,  X_k mod 53)
        dist_k ← HammingDist(cand_r, received)

        // Update best candidate
        if dist_k < min_dist:
          min_dist ← dist_k
          best_X   ← X_k

    // Output
    if min_dist ≤ 2:
      return best_X, uncorrectable=false
    else:
      return 0, uncorrectable=true
    ─────────────────────────────────────────────────────────────────

**Architectural comparison with parallel implementation:**

| Property           | Parallel (Appendix C) | Serial (Appendix D) |
|--------------------|-----------------------|---------------------|
| Hardware instances | 15 CRT channels       | 1 shared CRT engine |
| Decoder latency    | ~24 cycles            | ~1047 cycles        |
| LUT utilisation    | ~51%                  | ~4%                 |
| BER performance    | Identical             | Identical           |

The serial implementation trades latency for resource efficiency.

## Appendix E: 3NRM-RRNS Encoder and Decoder

### E.1 Encoder

    Algorithm E.1: 3NRM-RRNS Encoding
    ─────────────────────────────────────────────────────────────────
    Input:  data ∈ [0, 65535]
    Output: codeword = (r₀, r₁, ..., r₈)

    Moduli set: m₀=64, m₁=63, m₂=65, m₃=31, m₄=29, m₅=23,
                m₆=19, m₇=17, m₈=11

    For i = 0 to 8:
      rᵢ ← data mod mᵢ

    return (r₀, r₁, r₂, r₃, r₄, r₅, r₆, r₇, r₈)

    Codeword packing (48 bits):
      bits [47:42] = r₀ (6 bits, mod 64)
      bits [41:36] = r₁ (6 bits, mod 63)
      bits [35:29] = r₂ (7 bits, mod 65)
      bits [28:24] = r₃ (5 bits, mod 31)
      bits [23:19] = r₄ (5 bits, mod 29)
      bits [18:14] = r₅ (5 bits, mod 23)
      bits [13:9]  = r₆ (5 bits, mod 19)
      bits [8:4]   = r₇ (5 bits, mod 17)
      bits [3:0]   = r₈ (4 bits, mod 11)
    ─────────────────────────────────────────────────────────────────

### E.2 Decoder (Sequential FSM MLD)

    Algorithm E.2: 3NRM-RRNS Sequential FSM MLD Decoding (Final Verified Implementation)
    ─────────────────────────────────────────────────────────────────
    Input:  received = (r̃₀, ..., r̃₈)
    Output: data_out, uncorrectable

    Initialise: min_dist ← 9,  best_X ← 0

    For trip_idx = 0 to 83:  // iterate over all C(9,3)=84 triplets
      (i, j, k) ← triplet_table[trip_idx]
      mᵢ, mⱼ, mₖ, Inv_ij, Inv_ijk ← lut[trip_idx]
      PERIOD ← mᵢ × mⱼ × mₖ   // Bug #104 fix: pre-computed per triplet

      // MRC reconstruction using 3 moduli
      // Bug #100 fix: use 6×mⱼ and 6×mₖ additions before subtraction to prevent
      // unsigned underflow when r̃ᵢ > mⱼ or mₖ (e.g., r̃ᵢ=60, mₖ=11: 5+11-60=-44 wraps)
      a₁ ← r̃ᵢ
      diff₂ ← (r̃ⱼ + 6×mⱼ − r̃ᵢ) mod mⱼ   // always positive: ceil(64/11)=6 copies
      a₂ ← (diff₂ × Inv_ij) mod mⱼ
      diff₃ ← (r̃ₖ + 6×mₖ − r̃ᵢ) mod mₖ   // always positive
      a₃ ← ((diff₃ + 6×mₖ − a₂ × mᵢ mod mₖ) × Inv_ijk) mod mₖ
      X_base ← a₁ + a₂ × mᵢ + a₃ × mᵢ × mⱼ

      // Bug #104 fix: enumerate k>0 candidates X_k = X_base + k×PERIOD
      // The original implementation only computed k=0 (X_base), missing correct
      // solutions for large X values. For small-modulus triplets (e.g., (19,17,11)
      // with PERIOD=3553), k_max can be up to 18 (needs 19 candidates).
      X ← X_base
      While X ≤ 65535:
        // Compute Hamming distance against all 9 received residues
        cand_r ← (X mod m₀, X mod m₁, ..., X mod m₈)
        dist   ← HammingDist(cand_r, received)

        if dist < min_dist:
          min_dist ← dist
          best_X   ← X

        X ← X + PERIOD   // advance to next candidate

    if min_dist ≤ 3:
      return best_X, uncorrectable=false
    else:
      return 0, uncorrectable=true
    ─────────────────────────────────────────────────────────────────

**FPGA implementation note:** The FSM iterates through 84 triplets. For
each triplet, it first computes X_base (MRC reconstruction), then
enumerates k\>0 candidates by repeatedly adding PERIOD until X \> 65535
(Bug \#104 fix). The PERIOD for each triplet is pre-computed and stored
in a 84-entry LUT (`lut_period[0:83]`). The FSM uses a dedicated
`ST_CAND_NEXT` state to advance to the next candidate without
recomputing the MRC. Total decoder latency: ~2048 clock cycles (decoder
only, measured on hardware at 50 MHz; total trial latency including
overhead is ~3231 cycles). The Bug \#104 fix adds k\>0 candidate
enumeration for small-PERIOD triplets, which accounts for the higher
latency compared to C-RRNS-MLD (928 decoder cycles, 995 total). This is
significantly higher than the C-RRNS-MLD decoder (~928 cycles) despite
both processing 84 triplets, because: (1) 3NRM-RRNS uses small redundant
moduli (11, 17, 19, 23, 29, 31), giving small PERIOD values (e.g.,
PERIOD=3553 for triplet (19,17,11)), requiring up to 18 k\>0 candidates
per triplet; (2) C-RRNS-MLD uses large redundant moduli (67, 71, 73, 79,
83, 89), giving large PERIOD values (e.g., PERIOD=262080 for triplet
(64,63,65)), so X_base + PERIOD always exceeds 65535 and no k\>0
candidates are needed. The C-RRNS-MLD decoder therefore evaluates
exactly 1 candidate per triplet (84 total), while 3NRM-RRNS evaluates an
average of ~4 candidates per triplet (~347 total).

## Appendix F: C-RRNS Encoder and Decoder Variants

### F.1 Encoder (Shared by All C-RRNS Variants)

    Algorithm F.1: C-RRNS Encoding
    ─────────────────────────────────────────────────────────────────
    Input:  data ∈ [0, 65535]
    Output: codeword = (r₀, r₁, ..., r₈)

    Moduli set: m₀=64, m₁=63, m₂=65, m₃=67, m₄=71, m₅=73,
                m₆=79, m₇=83, m₈=89
    Non-redundant moduli: {64, 63, 65}  (product = 64×63×65 = 261,120 > 65,535)
    Redundant moduli:     {67, 71, 73, 79, 83, 89}

    For i = 0 to 8:
      rᵢ ← data mod mᵢ

    return (r₀, r₁, r₂, r₃, r₄, r₅, r₆, r₇, r₈)

    Codeword packing (61 bits):
      bits [60:55] = r₀ (6 bits, mod 64)
      bits [54:49] = r₁ (6 bits, mod 63)
      bits [48:42] = r₂ (7 bits, mod 65)
      bits [41:35] = r₃ (7 bits, mod 67)
      bits [34:28] = r₄ (7 bits, mod 71)
      bits [27:21] = r₅ (7 bits, mod 73)
      bits [20:14] = r₆ (7 bits, mod 79)
      bits [13:7]  = r₇ (7 bits, mod 83)
      bits [6:0]   = r₈ (7 bits, mod 89)
    ─────────────────────────────────────────────────────────────────

### F.2 C-RRNS-MLD Decoder

    Algorithm F.2: C-RRNS-MLD Decoding (Sequential FSM MLD)
    ─────────────────────────────────────────────────────────────────
    Input:  received = (r̃₀, ..., r̃₈)  (9 residues, possibly corrupted)
    Output: data_out, uncorrectable

    Initialise: min_dist ← 9,  best_X ← 0

    For trip_idx = 0 to 83:  // iterate over all C(9,3)=84 triplets
      (i, j, k) ← triplet_table[trip_idx]
      mᵢ, mⱼ, mₖ, Inv_ij, Inv_ijk ← lut[trip_idx]

      // MRC reconstruction using 3 moduli (same structure as Algorithm E.2)
      a₁ ← r̃ᵢ
      diff₂ ← (r̃ⱼ + 6×mⱼ − r̃ᵢ) mod mⱼ
      a₂ ← (diff₂ × Inv_ij) mod mⱼ
      diff₃ ← (r̃ₖ + 6×mₖ − r̃ᵢ) mod mₖ
      a₃ ← ((diff₃ + 6×mₖ − a₂ × mᵢ mod mₖ) × Inv_ijk) mod mₖ
      X  ← a₁ + a₂ × mᵢ + a₃ × mᵢ × mⱼ

      if X > 65535: continue  // invalid candidate

      // Compute Hamming distance against all 9 received residues
      cand_r ← (X mod m₀, X mod m₁, ..., X mod m₈)
      dist   ← HammingDist(cand_r, received)

      if dist < min_dist:
        min_dist ← dist
        best_X   ← X

    if min_dist ≤ 3:
      return best_X, uncorrectable=false
    else:
      return 0, uncorrectable=true
    ─────────────────────────────────────────────────────────────────

The C-RRNS-MLD decoder uses the same sequential FSM MLD structure as the
3NRM-RRNS decoder (Appendix E.2), but operates on the C-RRNS moduli set
{64, 63, 65, 67, 71, 73, 79, 83, 89} with the corresponding pre-computed
triplet look-up table. The algorithm iterates over all C(9,3)=84
triplets and selects the candidate with minimum Hamming distance across
all 9 residues. Error correction capability: t=3 residues. Total decoder
latency: ~928 clock cycles.

**Why C-RRNS-MLD (928 cycles) is faster than 3NRM-RRNS (1892 cycles)
despite both processing 84 triplets:** The key difference lies in the
candidate enumeration step. C-RRNS uses large redundant moduli {67, 71,
73, 79, 83, 89}, so PERIOD = mi×mj×mk is always large (minimum PERIOD =
67×71×73 = 347,381 \>\> 65,535). Therefore X_base + PERIOD always
exceeds 65,535, and no k\>0 candidates need to be evaluated — each
triplet produces exactly 1 candidate. In contrast, 3NRM-RRNS uses small
redundant moduli {11, 17, 19, 23, 29, 31}, giving small PERIOD values
(minimum PERIOD = 19×17×11 = 3,553), requiring up to 18 additional k\>0
candidates per triplet. C-RRNS-MLD therefore evaluates 84 candidates
total, while 3NRM-RRNS evaluates approximately 347 candidates total.

### F.3 C-RRNS-MRC Decoder (Direct Mixed Radix Conversion)

    Algorithm F.3: C-RRNS-MRC Decoding (no error correction)
    ─────────────────────────────────────────────────────────────────
    Input:  received = (r̃₀, r̃₁, r̃₂, ...)  (uses only r̃₀, r̃₁, r̃₂)
    Output: data_out  (no error correction; assumes r̃₀, r̃₁, r̃₂ are correct)

    Non-redundant moduli: m₀=64, m₁=63, m₂=65
    Pre-computed: Inv(m₀ mod m₁, m₁) = Inv(1, 63) = 1
                  Inv(m₀×m₁ mod m₂, m₂) = Inv(64×63 mod 65, 65) = Inv(33, 65) = 33

    // Mixed Radix Conversion
    a₁ ← r̃₀
    diff₂ ← (r̃₁ − r̃₀ + m₁) mod m₁
    a₂ ← (diff₂ × 1) mod m₁  = diff₂
    diff₃ ← (r̃₂ − r̃₀ + m₂) mod m₂
    a₃ ← ((diff₃ − a₂ × m₀ mod m₂ + m₂) × 33) mod m₂

    data_out ← a₁ + a₂ × m₀ + a₃ × m₀ × m₁
    return data_out, uncorrectable=false
    ─────────────────────────────────────────────────────────────────

**Note:** This decoder provides no error correction. It reconstructs the
data directly from the three non-redundant residues, assuming they are
error-free. Total decoder latency: ~9 clock cycles.

### F.4 C-RRNS-CRT Decoder (Direct Chinese Remainder Theorem)

    Algorithm F.4: C-RRNS-CRT Decoding (no error correction)
    ─────────────────────────────────────────────────────────────────
    Input:  received = (r̃₀, r̃₁, r̃₂, ...)  (uses only r̃₀, r̃₁, r̃₂)
    Output: data_out

    Non-redundant moduli: m₀=64, m₁=63, m₂=65
    M = m₀ × m₁ × m₂ = 261,120
    Mᵢ = M / mᵢ:  M₀=4080, M₁=4160, M₂=4032
    yᵢ = Inv(Mᵢ, mᵢ):  y₀=Inv(4080,64)=16, y₁=Inv(4160,63)=32, y₂=Inv(4032,65)=9

    // CRT reconstruction
    data_out ← (r̃₀ × M₀ × y₀ + r̃₁ × M₁ × y₁ + r̃₂ × M₂ × y₂) mod M
    return data_out, uncorrectable=false
    ─────────────────────────────────────────────────────────────────

**Note:** This decoder provides no error correction. It is
mathematically equivalent to MRC but uses the CRT formula directly.
Total decoder latency: ~7 clock cycles.

## Appendix G: RS(12,4) Encoder and Decoder

### G.1 Encoder

    Algorithm G.1: RS(12,4) Systematic Encoding over GF(2⁴)
    ─────────────────────────────────────────────────────────────────
    Input:  data = (d₀, d₁, d₂, d₃)  (4 data symbols, each 4-bit, GF(2⁴))
    Output: codeword = (d₀, d₁, d₂, d₃, p₀, p₁, ..., p₇)
            (4 data + 8 parity symbols = 12 symbols × 4 bits = 48 bits)

    Generator polynomial: g(x) = ∏ᵢ₌₁⁸ (x − αⁱ)  where α is a primitive element of GF(2⁴)

    // Systematic encoding: divide x⁸ × d(x) by g(x)
    // The remainder gives the 8 parity symbols
    d(x) ← d₃x³ + d₂x² + d₁x + d₀
    shifted ← x⁸ × d(x)
    remainder ← shifted mod g(x)  // polynomial division in GF(2⁴)
    (p₀, p₁, ..., p₇) ← coefficients of remainder

    return (d₀, d₁, d₂, d₃, p₀, p₁, ..., p₇)
    ─────────────────────────────────────────────────────────────────

**FPGA implementation note:** The polynomial division is implemented as
a 3-stage pipeline using GF(2⁴) multipliers (implemented as LUT-based
constant multipliers). Total encoder latency: 4 clock cycles.

### G.2 Decoder

    Algorithm G.2: RS(12,4) Decoding — Berlekamp-Massey + Chien + Forney
    ─────────────────────────────────────────────────────────────────
    Input:  received = (r₀, r₁, ..., r₁₁)  (12 received symbols)
    Output: data_out = (d₀, d₁, d₂, d₃), uncorrectable

    Phase 1 — Syndrome Computation:
      For i = 1 to 8:
        Sᵢ ← Σⱼ rⱼ × αⁱʲ  (evaluated in GF(2⁴))
      If all Sᵢ = 0: no errors, return received data symbols directly

    Phase 2 — Error Locator Polynomial (Berlekamp-Massey):
      σ(x) ← BerlekampMassey(S₁, S₂, ..., S₈)
      // σ(x) = 1 + σ₁x + σ₂x² + ... has roots at α⁻ʲ for each error position j
      If deg(σ) > 4: return uncorrectable=true  // more than 4 errors

    Phase 3 — Error Location (Chien Search):
      For each symbol position j = 0 to 11:
        If σ(α⁻ʲ) = 0: position j contains an error
      error_positions ← {j : σ(α⁻ʲ) = 0}

    Phase 4 — Error Values (Forney Algorithm):
      Ω(x) ← S(x) × σ(x) mod x⁸  // error evaluator polynomial
      For each error position j:
        eⱼ ← −Ω(α⁻ʲ) / σ'(α⁻ʲ)  // σ'(x) is formal derivative of σ(x)

    Phase 5 — Correction:
      For each error position j:
        rⱼ ← rⱼ ⊕ eⱼ  // XOR correction in GF(2⁴)

    return (r₀, r₁, r₂, r₃), uncorrectable=false
    ─────────────────────────────────────────────────────────────────

**FPGA implementation note:** The decoder is implemented as a sequential
FSM with separate states for each phase. The Berlekamp-Massey algorithm
iterates up to 8 times. The Chien search evaluates σ(x) at all 12
positions. Total decoder latency: ~127 clock cycles.

## Appendix H: 1st round MATLAB simulation

**Simulation architecture**  
Prior to the FPGA implementation, a MATLAB-based Monte Carlo simulation
was conducted to validate the theoretical error correction capabilities
of the four ECC algorithms and to establish baseline performance
benchmarks. The simulation framework follows a standard
encode–inject–decode–analyse pipeline, as illustrated in Figure H.1 .

MATLAB_simulation_architecture.png  
**Figure H.1** MATLAB simulation architecture.

The key simulation parameters are summarised in Table H.1.

**Table H.1** MATLAB simulation parameters.

| Parameter | Value |
|----|----|
| Number of Monte Carlo trials | 1,000 per fault rate point |
| Test data words | 15 random integers in \[0, 65,535\] per trial |
| Fault rate range | 0 % to 15 %, step 0.5 % |
| Fault injection model | Random bit flips uniformly distributed across the full codeword |
| Algorithms evaluated | RS(12,4), C-RRNS (MRC), 3NRM-RRNS (MLD), 2NRM-RRNS (MLD) |

The fault injection model in the MATLAB simulation applies random bit
flips uniformly across the entire codeword, including any zero-padding
bits. This differs from the FPGA implementation described in Section
3.2.2, where fault injection is strictly confined to the valid codeword
bits. This distinction is important when comparing the two sets of
results, as discussed in Section 3.1.4.

**Decoding Success Rate Comparison**  
Figure H.2 shows the average decoding success rate as a function of
fault rate for all four algorithms, with C-RRNS using the Mixed Radix
Conversion (MRC) decoder.  
decoding performance mrc.png  
**Figure H.2** Average decoding success rate vs. fault rate for RS,
C-RRNS (MRC), 3NRM-RRNS (MLD), and 2NRM-RRNS (MLD).

The key findings from this simulation are as follows:

1.  **RS(12,4) exhibits the highest robustness at elevated fault
    rates.** The RS code maintains a 100% decoding success rate up to
    approximately 9.5% fault rate, after which it degrades rapidly. Even
    at 14% fault rate, it retains approximately 6–8% success,
    demonstrating strong resilience in high-error environments.

2.  **C-RRNS (MRC) performs well at low fault rates but degrades
    rapidly.** C-RRNS achieves 100% success below approximately 6% fault
    rate. Beyond this threshold, performance drops sharply, falling
    below 20% at 12%. This behaviour is consistent with the MRC
    decoder's lack of error correction capability — it reconstructs data
    directly from the three non-redundant residues without exploiting
    the redundant moduli.

3.  **3NRM-RRNS shows stronger resilience than 2NRM-RRNS.** With t=3
    correction capability, 3NRM-RRNS sustains over 60% success until
    approximately 11% fault rate, then gradually declines. 2NRM-RRNS,
    with t=2 correction capability, stabilises at approximately 35–37%
    success between 8–11% fault rate.

4.  **Maximum fault rate for 100% success** (Table H.2):

**Table H.2** Maximum fault rate achieving 100% decoding success across
1,000 trials (MATLAB simulation).

| Algorithm | Max fault rate for 100% success | Error correction capability |
|----|----|----|
| RS(12,4) | ~9.5% | t=4 symbols |
| C-RRNS (MRC) | ~6% | None (direct reconstruction) |
| 3NRM-RRNS (MLD) | ~7% | t=3 residues |
| 2NRM-RRNS (MLD) | ~6% | t=2 residues |

**Decoding Latency Comparison**

Figure H.3 shows the average decoding latency (measured in MATLAB
execution time) for all four algorithms, with C-RRNS using the MRC
decoder.  
decoding time mrc.png  
**Figure H.3** Average decoding latency (MATLAB seconds) vs. fault rate
for RS, C-RRNS (MRC), 3NRM-RRNS (MLD), and 2NRM-RRNS (MLD).

The key findings are:

1.  **C-RRNS (MRC) exhibits significantly higher latency** than all
    other algorithms, particularly at low fault rates, due to the
    exhaustive subset enumeration and majority voting in the MRC
    decoding procedure. Latency reaches approximately 10–12 ms at low
    fault rates.

2.  **2NRM-RRNS, 3NRM-RRNS, and RS exhibit much faster and more stable
    decoding times**, with RS showing minimal variation across fault
    rates. This highlights the computational efficiency of the MLD-based
    RRNS decoders relative to the MRC approach.

3.  **The latency ranking** (fastest to slowest) is: RS ≈ 2NRM-RRNS ≈
    3NRM-RRNS ≪ C-RRNS (MRC). This is consistent with the FPGA hardware
    results presented in Section 4.5, where C-RRNS-MLD (928 cycles) is
    the slowest correcting decoder and 2NRM-RRNS Parallel (24 cycles) is
    the fastest among all error-correcting decoders (noting that
    C-RRNS-MRC achieves 9 cycles but provides no error correction
    capability). 3NRM-RRNS achieves 844 cycles.

## Appendix I: Hierarchical Module Structure of FPGA platform

The system is organised into two major domains — a PC-side Python
application and an FPGA-side Verilog implementation — as shown in
following table.

| **PC Side (Python host application)**​ |  |
|----|----|
| `py_controller_main.py` | Main controller: user CLI, command framing, result parsing, CSV export, auto-plotting |
| `gen_rom.py` | Offline ROM generator: pre-computes 10,605 BER threshold entries → `threshold_table.coe`and 8,192 error-pattern entries → `error_lut.coe` |
| `compare_ber_curves.py` | Multi-algorithm BER success-rate comparison |
| `plot_utilisation.py` | FPGA resource utilisation comparison |
| `plot_latency.py` | Encoder/decoder latency comparison |
| `plot_storage_efficiency.py` | Codeword storage overhead comparison |
| **FPGA Side (Verilog / SystemVerilog, Xilinx Artix‑7 xc7a100t)**​ |  |
| **UART Communication Layer**​ |  |
| `uart_rx_module` | Serial-to-parallel byte receiver (16× oversampling) |
| `uart_tx_module` | Parallel-to-serial byte transmitter |
| `protocol_parser` | Frame synchronisation, XOR checksum verification, parameter extraction from 12‑byte command frame |
| `ctrl_register_bank` | Atomic parameter latch; auto-asserts `test_active`upon receipt of a valid configuration frame |
| **Seed Lock Unit**​ | Captures free‑running 32‑bit counter at test start; holds seed constant across all 101 BER points to ensure statistical consistency |
| **Main Scan FSM**​ | Top‑level test orchestrator; iterates over 101 BER points (0 % to 10 %, step 0.1 %), invokes Auto Scan Engine for each point, accumulates statistics, and triggers the result upload phase |
| `rom_threshold_ctrl` | Retrieves the 32‑bit LFSR injection threshold from Block RAM (`threshold_table.coe`, depth 10,605 entries) |
| **Auto Scan Engine**​ | Single‑trial execution core |
| **PRBS Generator (LFSR)**​ | 32‑bit Galois LFSR, seeded by Seed Lock Unit |
| **Encoder Wrapper**​ | Compile‑time algorithm selection; routes to the active encoder (2NRM / 3NRM / C‑RRNS / RS) |
| **Error Injector Unit**​ | ROM‑based burst/random‑bit fault injection; error patterns pre‑computed in `error_lut.coe` |
| **Decoder Wrapper**​ | Compile‑time algorithm selection; routes to the active decoder |
| **Result Comparator**​ | Compares original vs. decoded symbol; records pass/fail, actual flip count, encoder latency, and decoder latency in clock cycles |
| **Result Buffer & Reporter**​ |  |
| `mem_stats_array` | True dual‑port Block RAM; stores 101 × 30‑byte per‑point statistics (240‑bit entries, RAMB36) |
| `tx_packet_assembler` | Serialises BRAM contents into a 3,039‑byte UART response frame with XOR checksum |

## Appendix J: Algorithm : 32-bit Galois LFSR

**Algorithm : 32-bit Galois LFSR — Single-Cycle Update and Dual-Use
Output**

    Algorithm 3.1: 32-bit Galois LFSR Update
    ─────────────────────────────────────────────────────────────────
    Polynomial: x^32 + x^22 + x^2 + x + 1  (taps at bits [31, 21, 1, 0])
    Period:     2^32 - 1 = 4,294,967,295 cycles

    Inputs:
      lfsr_q[31:0]   -- current LFSR state (must be non-zero)
      load_seed      -- 1: load new seed; 0: advance LFSR
      seed_in[31:0]  -- seed value (forced to 1 if zero)

    Outputs:
      lfsr_next[31:0]  -- next LFSR state
      inject_trigger   -- 1 if fault should be injected this cycle
      offset[5:0]      -- random bit position for error mask lookup

    Step 1 -- Galois right-shift update (combinational, single cycle):
      feedback         := lfsr_q[0]                    // outgoing LSB
      lfsr_next[31]    := feedback                      // tap 31: shift-in
      lfsr_next[30:22] := lfsr_q[31:23]                // plain shift (9 bits)
      lfsr_next[21]    := lfsr_q[22] XOR feedback      // tap 21: XOR
      lfsr_next[20:2]  := lfsr_q[21:3]                 // plain shift (19 bits)
      lfsr_next[1]     := lfsr_q[2]  XOR feedback      // tap 1: XOR
      lfsr_next[0]     := lfsr_q[1]  XOR feedback      // tap 0: XOR

    Step 2 -- Sequential register update (on rising clock edge):
      if load_seed:
        lfsr_q := (seed_in != 0) ? seed_in : 1         // zero-seed guard
      else:
        lfsr_q := lfsr_next

    Step 3 -- Dual-use output extraction (combinational):
      inject_trigger := (lfsr_next[31:0] < T)           // compare full 32-bit value
                                                         // against threshold T
      offset[5:0]    := lfsr_next[5:0]                  // lower 6 bits -> error position
    ─────────────────────────────────────────────────────────────────

The Galois LFSR update (Step 1) is a purely combinational operation: the
next state is computed in a single clock cycle by XOR-ing the feedback
bit (outgoing LSB) into the tap positions \[21, 1, 0\] while shifting
all other bits right by one position. This single-cycle update is the
key advantage of the Galois topology over the Fibonacci topology, which
would require a multi-stage XOR chain. The injection decision (Step 3)
uses the full 32-bit output for maximum resolution, while the error
position uses only the lower 6 bits, ensuring that both decisions are
made within the same clock cycle with no additional latency.
