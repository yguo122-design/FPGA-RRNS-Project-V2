# FPGA Evaluation Platform Summary

## Overview

This document provides a concise dissertation-ready summary of the FPGA evaluation platform developed for benchmarking RRNS-based and RS-based error-correcting codes under random and cluster fault models. It is intended as a shorter companion to the full engineering specification in the high-level design document.

The platform is implemented on a Xilinx Artix-7 Arty A7-100T FPGA and is designed to evaluate decoding success rate, processing latency, resource utilisation, and storage efficiency under a unified experimental framework. The evaluated algorithm configurations include 2NRM-RRNS, 3NRM-RRNS, C-RRNS, and RS, with additional architectural comparison between parallel and serial implementations where applicable.

## System Purpose

The primary purpose of the platform is to provide a hardware-validated, reproducible, and statistically rigorous method for comparing fault-tolerant coding schemes under realistic fault injection conditions. In contrast to algorithm-only simulation, the FPGA platform exposes implementation-level trade-offs such as latency, logic utilisation, BRAM consumption, and timing closure.

The design supports two fault models:

1. Random single-bit fault injection.
2. Cluster burst fault injection with configurable burst length from 1 to 15 bits.

For each experiment, the platform sweeps 101 BER points from 0% to 10% in steps of 0.1% and repeats each point for a configurable number of trials. This allows statistically meaningful hardware measurements over a wide operating range.

## Top-Level Architecture

The system is divided into two major subsystems:

1. **PC-side control software**, written in Python.
2. **FPGA-side execution logic**, written in Verilog.

The two subsystems communicate through a full-duplex UART interface. The PC is responsible for test configuration, experiment orchestration, result collection, and visualisation. The FPGA is responsible for deterministic high-speed execution of the fault injection, encoding, decoding, comparison, and statistics-reporting flow.

At a high level, the FPGA platform contains the following functional blocks:

- `uart_comm`: receives commands and returns results.
- `ctrl_register_bank`: atomically latches configuration parameters and launches the test.
- `main_scan_fsm`: controls the full 101-point BER sweep.
- `seed_lock_unit`: captures and holds the pseudo-random seed for a full experiment.
- `rom_threshold_ctrl`: performs threshold lookup for BER-controlled fault injection.
- `auto_scan_engine`: executes encoding, error injection, decoding, and result evaluation for one BER point.
- `mem_stats_array`: stores per-point statistics in BRAM.
- `tx_packet_assembler`: serialises final results into a UART response frame.

## Communication Model

The communication protocol follows a configuration-implies-start model. The PC sends a compact binary configuration frame that includes algorithm ID, error mode, burst length, and per-point sample count. Once the FPGA verifies the frame checksum, it latches the parameters and starts the full experiment automatically.

The downlink configuration frame is 12 bytes long. The uplink response frame is 3039 bytes long and contains complete per-point statistics for all 101 BER points, including:

- BER index.
- Success count.
- Failure count.
- Actual flip count.
- Total cycle count.
- Encoder cycle count.
- Decoder cycle count.

This one-shot reporting model reduces protocol overhead and ensures that measurements are not distorted by frequent software interaction during the test run.

## Fault Injection Strategy

The platform uses a probabilistic fault injection engine driven by a 32-bit Galois LFSR. Two injection models are supported.

### Random Single-Bit Injection

When `burst_len = 1`, the design uses a bit-scan Bernoulli model. Each valid codeword bit is examined independently, and a flip decision is made by comparing the LFSR output against a threshold derived from the target BER. This approach avoids the saturation problem of earlier single-trigger models and allows the measured BER to track the target BER more accurately.

### Cluster Burst Injection

When `burst_len > 1`, the design uses a single-burst probabilistic model. A trigger decision is first made from the BER-derived threshold. If triggered, a contiguous burst mask is read from a precomputed ROM and XORed with the encoded codeword. This allows efficient hardware realisation of cluster-fault injection without run-time computation of burst masks.

Two ROM-based lookup structures are used:

1. A threshold ROM for BER-dependent trigger thresholds.
2. An error-pattern LUT for burst-mask generation.

This design keeps the run-time hardware simple while preserving accurate and configurable fault injection behaviour.

## Seed Consistency and Statistical Fairness

To ensure fair comparison across all BER points within one experiment, the random seed is captured once at the start of the test and held constant throughout the full BER sweep. This is implemented by the `seed_lock_unit`, which snapshots a free-running counter when a valid command is received.

This seed-lock mechanism prevents different BER points from using unrelated pseudo-random sequences and avoids statistical bias caused by repeated reseeding. In addition, the LFSR advances only during injection windows, ensuring that decoder latency does not alter the effective error pattern. This was a critical design refinement for cross-algorithm fairness.

## Scan and Reporting Flow

The full experiment proceeds in three stages:

1. **Configuration delivery**: the PC sends one binary command frame.
2. **Autonomous BER sweep**: the FPGA executes all 101 BER points internally without host intervention.
3. **Final reporting**: the FPGA packs the complete result set into one UART response frame and returns it to the PC.

For each BER point, the `auto_scan_engine` repeats the encode-inject-decode-compare loop for the configured sample count. The accumulated statistics are stored in BRAM and later packetised by `tx_packet_assembler`. This architecture ensures deterministic execution and clean separation between fast hardware measurement and slower host-side visualisation.

## Architectural Decisions

Several design decisions were made to improve fairness, robustness, and implementation efficiency.

### Single-Algorithm Build Strategy

Each synthesis build contains only one active decoder configuration. This avoids artificial resource contention between algorithms and allows direct, defensible comparison of LUT, FF, DSP, BRAM, and Fmax results.

### Atomic Configuration Latching

The `ctrl_register_bank` latches all parameters on one configuration-update pulse and raises the run-enable signal on the same clock edge. This prevents partial parameter updates and race conditions between command reception and experiment launch.

### TX Busy Lock

New configuration frames are ignored while the result packet is being transmitted. This protects the integrity of the current report and prevents corruption of the UART response path.

### Watchdog Protection

A watchdog timer in `auto_scan_engine` monitors decoder busy duration. If a decoder stalls beyond the configured threshold, the point is marked as a hardware error and the system advances safely to the next BER point instead of deadlocking.

## Resource and Implementation Efficiency

The platform is designed to be lightweight relative to the capacity of the Artix-7 100T device. The core control and reporting infrastructure occupies only a small portion of available logic and BRAM resources. This leaves sufficient headroom for implementing multiple algorithm variants while maintaining timing closure at 100 MHz.

The reporting subsystem uses BRAM-backed statistics storage and a one-shot UART uplink frame, which reduces control complexity and minimises communication overhead. The fault injection engine also avoids expensive run-time arithmetic by relying on precomputed ROM contents, further improving implementation efficiency.

## Dissertation Relevance

From a dissertation perspective, the platform is important for three reasons.

1. It provides the experimental infrastructure required to convert theoretical algorithm claims into hardware-validated evidence.
2. It makes it possible to compare algorithm families across multiple dimensions rather than BER performance alone.
3. It exposes architectural trade-offs that are invisible in software-only simulation, especially the latency-resource trade-off between parallel and serial decoding architectures.

The platform therefore serves not only as a testbench, but as a core research contribution in its own right.

## Suggested Use in the Dissertation

This summary is suitable for adaptation into:

- A short introductory subsection in the FPGA methodology chapter.
- A platform-overview section preceding the detailed module description.
- A concise explanation of the experimental infrastructure in the abstract or conclusion.

For full implementation details, protocol tables, interface definitions, and version-history notes, refer to the full high-level design document.