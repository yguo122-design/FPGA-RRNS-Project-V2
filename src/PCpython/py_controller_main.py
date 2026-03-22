import serial
import serial.tools.list_ports
import argparse
import time
import struct
import csv
import os
import sys
from datetime import datetime
from typing import Optional, List, Dict, Tuple

# Script directory (used for result output path)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RESULT_DIR = os.path.join(SCRIPT_DIR, 'result')

# ================= Configuration Constants =================
DEFAULT_PORT = 'COM8'       # Default serial port (Linux: /dev/ttyUSB0)
DEFAULT_BAUDRATE = 921600   # Baud rate
TIMEOUT_SEC = 300.0          # Receive timeout (seconds). FPGA may need time for large sample counts.

# Algorithm Mapping (User Specified Order)
# 0: 2NRM, 1: 3NRM, 2: C-RRNS-MLD, 3: C-RRNS-MRC, 4: C-RRNS-CRT, 5: RS
ALGO_MAP = {
    0: "2NRM-RRNS",
    1: "3NRM-RRNS",
    2: "C-RRNS-MLD",   # C-RRNS with Maximum Likelihood Decoding
    3: "C-RRNS-MRC",   # C-RRNS with Mixed Radix Conversion (reserved)
    4: "C-RRNS-CRT",   # C-RRNS with Chinese Remainder Theorem (reserved)
    5: "RS"
}

# Valid codeword bit widths per algorithm (W_valid)
# Used for computing actual BER from Flip_Count:
#   BER_actual = Flip_Count / (Total_Trials * W_valid)
ALGO_W_VALID = {
    0: 41,   # 2NRM-RRNS: {257,256,61,59,55,53} → 9+8+6+6+6+6 = 41 bits
    1: 48,   # 3NRM-RRNS: {64,63,65,31,29,23,19,17,11} → 6+6+7+5+5+5+5+5+4 = 48 bits
    2: 61,   # C-RRNS-MLD: {64,63,65,67,71,73,79,83,89} → 6+6+7+7+7+7+7+7+7 = 61 bits
    3: 61,   # C-RRNS-MRC: same encoder as MLD, W_valid=61
    4: 61,   # C-RRNS-CRT: same encoder as MLD, W_valid=61
    5: 48,   # RS:        48 bits
}

# Decoder pipeline latency reference (clock cycles, start → valid)
# Used for estimating test throughput and watchdog timeout sizing.
# Note: auto_scan_engine.v DEC_WAIT state polls dec_valid, so latency is
# absorbed automatically. These values are for documentation only.
ALGO_DEC_LATENCY_CYCLES = {
    0: 27,   # 2NRM-RRNS: ~27 cycles (15 parallel CRT channels + MLD)
    1: 842,  # 3NRM-RRNS: 842 cycles (FSM sequential MLD, 84 triplets)
    2: 842,  # C-RRNS-MLD: 842 cycles (FSM sequential MLD, 84 triplets)
    3: 10,   # C-RRNS-MRC: ~10 cycles (direct MRC with 3 non-redundant moduli)
    4: 5,    # C-RRNS-CRT: ~5 cycles (direct CRT with 3 non-redundant moduli)
    5: 0,    # RS: TBD (depends on Xilinx IP core)
}

# BER test point mapping: index → BER value
# BER_Index 0 → 0.000 (baseline, no injection), 1 → 0.001, ..., 100 → 0.100
BER_START  = 0.0
BER_STEP   = 0.001

# Error Mode Mapping
ERROR_MODE_MAP = {
    0: "Random Single Bit",
    1: "Cluster (Burst)"
}

# Protocol Constants (Based on Doc Sections 2.1.3.1 & 2.1.3.2)
CMD_REQ_ID = 0x01
CMD_RESP_ID = 0x81
HEADER_REQ = bytes([0xAA, 0x55])
HEADER_RESP = bytes([0xBB, 0x66])

# ─────────────────────────────────────────────────────────────────────────────
# Uplink Frame Per-Point Data Layout (22 Bytes / 176 bits per entry)
# Matches mem_stats_array.vh v2.0 + tx_packet_assembler.v v2.0
#
# FPGA sends each entry as 22 bytes (Big-Endian, MSB first):
#   Byte  0:     BER_Index          (1 Byte,  Uint8,  value = 0~90)
#   Bytes 1..4:  Success_Count      (4 Bytes, Uint32, Big-Endian)
#   Bytes 5..8:  Fail_Count         (4 Bytes, Uint32, Big-Endian)
#   Bytes 9..12: Actual_Flip_Count  (4 Bytes, Uint32, Big-Endian)
#   Bytes 13..20:Clk_Count          (8 Bytes, Uint64, Big-Endian)
#   Byte  21:    Reserved           (1 Byte,  0x00)
#
# Corresponds to 176-bit BRAM entry layout:
#   [175:168] BER_Index
#   [167:136] Success_Count
#   [135:104] Fail_Count
#   [103:72]  Actual_Flip_Count
#   [71:8]    Clk_Count
#   [7:0]     Reserved
# ─────────────────────────────────────────────────────────────────────────────
POINT_DATA_SIZE = 22   # 22 Bytes per BER point (176-bit entry)

# Frame Length Definitions
# Downlink: Header(2) + CmdID(1) + Len(1) + Payload(7) + Checksum(1) = 12 Bytes
FRAME_LEN_REQ = 12

# Uplink: Header(2) + CmdID(1) + Length(2) + GlobalInfo(3) + Data(101*22) + Checksum(1) = 2231 Bytes
# Length field value = GlobalInfo(3) + PerPointData(101*22=2222) = 2225 = 0x08B1
FRAME_LEN_RESP = 2231
PAYLOAD_DATA_POINTS = 101
EXPECTED_LENGTH_FIELD = 0x08B1  # 2225: GlobalInfo(3) + 101*22(2222)

class FpgaController:
    def __init__(self, port: str, baudrate: int):
        self.port_name = port
        self.baudrate = baudrate
        self.serial_conn = None

    def open(self) -> bool:
        """Initialize and open the serial connection."""
        try:
            self.serial_conn = serial.Serial(
                port=self.port_name,
                baudrate=self.baudrate,
                timeout=TIMEOUT_SEC,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE
            )
            print(f"[OK] Serial port {self.port_name} opened successfully ({self.baudrate}bps)")
            return True
        except Exception as e:
            print(f"[ERROR] Failed to open serial port {self.port_name}: {e}")
            # Print available ports to help user identify the correct port
            available = [p.device for p in serial.tools.list_ports.comports()]
            if available:
                print(f"[INFO] Available serial ports: {', '.join(available)}")
            else:
                print(f"[INFO] No serial ports detected. Check USB-UART bridge connection.")
            return False

    def close(self):
        """Close the serial connection."""
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.close()
            print("[OK] Serial port closed")

    def _calculate_checksum(self, data: bytes) -> int:
        """Calculate XOR checksum from Header to the end of Payload."""
        checksum = 0
        for byte in data:
            checksum ^= byte
        return checksum & 0xFF

    def send_command(self, algo_id: int, error_mode: int, burst_len: int, sample_count: int) -> bool:
        """
        Construct and send the downlink command frame (per Section 2.1.3.1).

        Payload Structure (7 Bytes):
          Offset 4 (Payload[0]): cfg_burst_len (1B)
          Offset 5 (Payload[1]): cfg_algo_ID   (1B)
          Offset 6 (Payload[2]): cfg_error_mode(1B)
          Offset 7-10 (Payload[3:7]): cfg_sample_count (4B, Big-Endian)

        BUG FIX #22: Call reset_input_buffer() before write() to discard any
        stale bytes accumulated in the OS receive buffer (e.g., FPGA power-on
        garbage, residual data from a previous test, or USB-UART bridge init
        bytes). Without this, receive_response() may read stale bytes as the
        first bytes of the response frame, causing a header mismatch error even
        when the FPGA correctly sends the 2011-byte response.
        """
        # 1. Construct Payload
        payload = bytearray(7)
        payload[0] = burst_len & 0xFF           # Offset 4 relative to frame start
        payload[1] = algo_id & 0xFF             # Offset 5 relative to frame start
        payload[2] = error_mode & 0xFF          # Offset 6 relative to frame start

        # Sample Count (4 Bytes, Big-Endian)
        sample_bytes = struct.pack('>I', sample_count)
        payload[3:7] = sample_bytes

        # 2. Construct Full Frame Header part
        # Header (2) + CmdID (1) + Length (1) + Payload (7)
        length_byte = len(payload) # Should be 7
        frame_header = HEADER_REQ + bytes([CMD_REQ_ID, length_byte])
        frame_data = frame_header + bytes(payload)

        # 3. Calculate Checksum (covers Header to Payload end)
        checksum = self._calculate_checksum(frame_data)

        # 4. Assemble Full Frame
        full_frame = frame_data + bytes([checksum])

        if len(full_frame) != FRAME_LEN_REQ:
            print(f"[ERROR] Internal Error: Downlink frame length should be {FRAME_LEN_REQ}, got {len(full_frame)}")
            return False

        # 5. Send Data
        print(f"\n[Transmit] Sending test configuration...")
        print(f"   Frame Content (Hex): {full_frame.hex()}")
        try:
            # BUG FIX #22: Flush the OS receive buffer before sending the command.
            # This discards any stale bytes (FPGA power-on noise, previous test
            # residuals, USB-UART bridge init bytes) so that receive_response()
            # always starts reading from a clean buffer aligned to the response
            # frame header 0xBB66.
            self.serial_conn.reset_input_buffer()
            self.serial_conn.write(full_frame)
            self.serial_conn.flush()
            return True
        except Exception as e:
            print(f"[ERROR] Transmission failed: {e}")
            return False

    def receive_response(self) -> Optional[Dict]:
        """
        Receive and parse the uplink response frame (per Section 2.1.3.2).
        Returns a dictionary containing global info and detailed data for 91 points.

        BUG FIX #23: Replace fixed-length read with a frame-header sync search.
        Previous implementation called serial_conn.read(2011) and assumed the
        first 2 bytes were always 0xBB 0x66. Any stale bytes in the buffer
        (even 1 byte) would shift the frame, causing a permanent header mismatch
        error and returning None even when the FPGA sent a valid response.

        New implementation:
          Step 1 — Byte-by-byte search for the 0xBB 0x66 sync word (with timeout).
          Step 2 — Once sync found, read the remaining 2009 bytes in one call.
          Step 3 — Reassemble full 2011-byte frame and proceed with parsing.
        This makes reception robust against any number of stale bytes in the
        OS receive buffer.
        """
        print(f"[Receive] Waiting for FPGA response (Timeout: {TIMEOUT_SEC}s)...")
        start_time = time.time()

        try:
            # ─────────────────────────────────────────────────────────────────
            # Step 1: Search for frame header 0xBB 0x66 (BUG FIX #23)
            #
            # Read one byte at a time until we see the two-byte sequence
            # [0xBB, 0x66]. This tolerates any number of stale bytes that may
            # be sitting in the OS receive buffer before the real response frame.
            #
            # Timeout guard: if we have consumed more than FRAME_LEN_RESP bytes
            # without finding the header, the FPGA likely did not respond at all.
            # ─────────────────────────────────────────────────────────────────
            sync_buf = bytearray()
            header_found = False

            while time.time() - start_time < TIMEOUT_SEC:
                byte = self.serial_conn.read(1)
                if not byte:
                    # read(1) returned empty — timeout on this single-byte read.
                    # The outer while-loop will check the overall timeout.
                    continue

                sync_buf.append(byte[0])

                # Check if the last two bytes match the response frame header
                if len(sync_buf) >= 2 and sync_buf[-2] == 0xBB and sync_buf[-1] == 0x66:
                    header_found = True
                    if len(sync_buf) > 2:
                        # Stale bytes were present before the header
                        print(f"[WARNING] Discarded {len(sync_buf) - 2} stale byte(s) before frame header.")
                    break

                # Safety guard: if we have consumed more bytes than a full frame
                # without finding the header, the FPGA is not responding.
                if len(sync_buf) > FRAME_LEN_RESP:
                    print(f"[ERROR] Frame header 0xBB66 not found after reading "
                          f"{len(sync_buf)} bytes. FPGA may not have responded.")
                    return None

            if not header_found:
                elapsed = time.time() - start_time
                print(f"[ERROR] Timeout ({elapsed:.1f}s): Frame header 0xBB66 not received. "
                      f"Scanned {len(sync_buf)} byte(s).")
                return None

            # ─────────────────────────────────────────────────────────────────
            # Step 2: Read remaining 2009 bytes
            # (CmdID(1) + Length(2) + GlobalInfo(3) + Data(2002) + Checksum(1))
            # ─────────────────────────────────────────────────────────────────
            remaining_len = FRAME_LEN_RESP - 2   # 2009 bytes
            remaining = self.serial_conn.read(remaining_len)

            if len(remaining) < remaining_len:
                print(f"[ERROR] Incomplete frame body: expected {remaining_len} bytes, "
                      f"received {len(remaining)} bytes (timeout or FPGA stopped sending).")
                return None

            # ─────────────────────────────────────────────────────────────────
            # Step 3: Reassemble full 2011-byte frame
            # ─────────────────────────────────────────────────────────────────
            raw_data = bytes([0xBB, 0x66]) + remaining

            elapsed = time.time() - start_time
            print(f"[OK] Reception complete ({FRAME_LEN_RESP} bytes), elapsed time: {elapsed:.2f}s")

            # ─────────────────────────────────────────────────────────────────
            # Parsing Process
            # ─────────────────────────────────────────────────────────────────

            # 1. Header already verified by sync search above (0xBB 0x66 confirmed)

            # 2. Verify CmdID
            if raw_data[2] != CMD_RESP_ID:
                print(f"[ERROR] Command ID mismatch: Expected {CMD_RESP_ID:#04x}, "
                      f"received {raw_data[2]:#04x}")
                return None

            # 3. Read Length Field (2 Bytes, Big-Endian)
            len_field = struct.unpack('>H', raw_data[3:5])[0]
            if len_field != EXPECTED_LENGTH_FIELD:
                print(f"[WARNING] Length field value: {len_field} (0x{len_field:04X}), "
                      f"expected {EXPECTED_LENGTH_FIELD} (0x{EXPECTED_LENGTH_FIELD:04X}). "
                      f"Continuing parse...")

            # 4. Verify Checksum (Last 1 Byte)
            received_checksum = raw_data[-1]
            calc_checksum = self._calculate_checksum(raw_data[:-1])
            if received_checksum != calc_checksum:
                print(f"[ERROR] Checksum error: Expected {calc_checksum:#04x}, "
                      f"received {received_checksum:#04x}")
                return None

            # 5. Parse Global Info (3 Bytes)
            # Offset: Header(2) + Cmd(1) + Len(2) = 5
            offset = 5
            global_info = {
                'total_points': raw_data[offset],
                'algo_used':    raw_data[offset + 1],
                'mode_used':    raw_data[offset + 2]
            }
            offset += 3

            # 6. Parse 91 Data Points (22 Bytes each, v2.0 format)
            # ─────────────────────────────────────────────────────────────────
            # Each 22-byte entry layout (Big-Endian):
            #   Byte  0:     BER_Index         (Uint8)
            #   Bytes 1..4:  Success_Count     (Uint32, Big-Endian)
            #   Bytes 5..8:  Fail_Count        (Uint32, Big-Endian)
            #   Bytes 9..12: Actual_Flip_Count (Uint32, Big-Endian)
            #   Bytes 13..20:Clk_Count         (Uint64, Big-Endian)
            #   Byte  21:    Reserved          (0x00, ignored)
            # ─────────────────────────────────────────────────────────────────
            results = []
            for i in range(PAYLOAD_DATA_POINTS):
                entry_bytes = raw_data[offset : offset + POINT_DATA_SIZE]
                if len(entry_bytes) < POINT_DATA_SIZE:
                    print(f"[WARNING] Truncated data at point {i+1}, stopping parse.")
                    break

                # Parse 22-byte entry fields (Big-Endian)
                ber_idx     = entry_bytes[0]                                   # Byte 0
                success_cnt = struct.unpack('>I', entry_bytes[1:5])[0]         # Bytes 1..4
                fail_cnt    = struct.unpack('>I', entry_bytes[5:9])[0]         # Bytes 5..8
                flip_cnt    = struct.unpack('>I', entry_bytes[9:13])[0]        # Bytes 9..12
                clk_cnt     = struct.unpack('>Q', entry_bytes[13:21])[0]       # Bytes 13..20
                # entry_bytes[21] = Reserved (0x00), ignored

                # Compute derived statistics
                total_trials  = success_cnt + fail_cnt
                success_rate  = success_cnt / total_trials if total_trials > 0 else 0.0
                avg_clk       = clk_cnt     / total_trials if total_trials > 0 else 0.0

                # BER_Value: target BER for this test point (index → value)
                ber_value = BER_START + ber_idx * BER_STEP

                point_res = {
                    'BER_Index':     ber_idx,
                    'BER_Value':     ber_value,
                    'Success_Count': success_cnt,
                    'Fail_Count':    fail_cnt,
                    'Flip_Count':    flip_cnt,
                    'Clk_Count':     clk_cnt,
                    'Total_Trials':  total_trials,
                    'Success_Rate':  success_rate,
                    'Avg_Clk':       avg_clk,
                }
                results.append(point_res)
                offset += POINT_DATA_SIZE

            return {
                'global':    global_info,
                'points':    results,
                'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }

        except Exception as e:
            print(f"[ERROR] Exception during reception/parsing: {e}")
            return None

def get_user_input() -> Tuple[int, int, int, int]:
    """
    Interactively get user input and perform validation.
    Returns: (algo_id, error_mode, burst_len, sample_count)
    """
    print("\n" + "="*60)
    print("FPGA Fault-Tolerant Test System - Parameter Configuration")
    print("="*60)

    # Input: Algo_Type
    while True:
        print("\nSelect Algorithm Type (Algo_Type):")
        for k, v in ALGO_MAP.items():
            print(f"  [{k}] {v}")
        try:
            algo_id = int(input("Enter index (0-3): "))
            if algo_id not in ALGO_MAP:
                print("[ERROR] Invalid input. Index must be between 0 and 3.")
                continue
        except ValueError:
            print("[ERROR] Input must be an integer.")
            continue
        break

    # Input: Error_Mode
    while True:
        print("\nSelect Error Mode (Error_Mode):")
        print("  [0] Random Single Bit")
        print("  [1] Cluster Mode (Burst Error)")
        try:
            error_mode = int(input("Enter index (0-1): "))
            if error_mode not in [0, 1]:
                print("[ERROR] Invalid input. Index must be 0 or 1.")
                continue
        except ValueError:
            print("[ERROR] Input must be an integer.")
            continue
        break

    # Input: Burst_Len
    while True:
        print("\nEnter Burst Error Length (Burst_Len):")
        print("  Range: 1 ~ 15")
        if error_mode == 0:
            print("  [WARNING] Note: Current mode is Single Bit. Length will be forced to 1.")

        try:
            burst_len = int(input("Enter length (1-15): "))
            if burst_len < 1 or burst_len > 15:
                print("[ERROR] Invalid input. Length must be between 1 and 15.")
                continue

            if error_mode == 0 and burst_len != 1:
                print("[WARNING] Burst_Len must be 1 in Single Bit mode. Auto-corrected to 1.")
                burst_len = 1

        except ValueError:
            print("[ERROR] Input must be an integer.")
            continue
        break

    # Input: Sample_Count
    while True:
        print("\nEnter Sample Count (Sample_Count):")
        print("  Range: > 0 (Recommended: 1000 ~ 100000)")
        try:
            sample_count = int(input("Enter count: "))
            if sample_count <= 0:
                print("[ERROR] Invalid input. Count must be greater than 0.")
                continue
            if sample_count > 10000000:
                confirm = input(f"[WARNING] Count is very large ({sample_count}), test may take a long time. Continue? (y/n): ")
                if confirm.lower() != 'y':
                    continue
        except ValueError:
            print("[ERROR] Input must be an integer.")
            continue
        break

    # Confirmation
    print("\n" + "="*60)
    print("Configuration Confirmation:")
    print(f"  Algorithm: {ALGO_MAP[algo_id]}")
    print(f"  Mode: {ERROR_MODE_MAP[error_mode]}")
    print(f"  Burst Length: {burst_len}")
    print(f"  Sample Count: {sample_count}")
    print("="*60)
    confirm = input("Confirm and send configuration? (y/n): ")
    if confirm.lower() != 'y':
        print("Operation cancelled.")
        return None

    return algo_id, error_mode, burst_len, sample_count

def save_to_csv(data: Dict, filename: str):
    """
    Save results to a CSV file (v2.1 format with post-processing).

    Post-processing changes vs v2.0:
    - Removed Point_ID column
    - Added BER_Value column after BER_Index (target BER = 0.01 + index * 0.001)
    - Renamed BER_Rate → Fail_Rate
    - Added BER_Value_Act column after Flip_Count (actual BER = Flip_Count / (Total_Trials * W_valid))
    - Avg_Clk formatted as integer (no decimal places)
    """
    if not data:
        return

    global_info = data['global']
    points = data['points']
    algo_id = global_info['algo_used']

    # Get W_valid for actual BER calculation
    w_valid = ALGO_W_VALID.get(algo_id, 41)  # Default to 41 (2NRM) if unknown

    # Output to RESULT_DIR (src/PCpython/result/), create if not exists
    os.makedirs(RESULT_DIR, exist_ok=True)
    base_name = os.path.splitext(os.path.basename(filename))[0]
    ext = os.path.splitext(filename)[1] or '.csv'
    final_filename = os.path.join(RESULT_DIR, f"{base_name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}{ext}")

    try:
        with open(final_filename, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            # Write header info
            writer.writerow(["Test Report (v2.0 Statistical Aggregation, 22-byte/point)"])
            writer.writerow(["Timestamp",    data['timestamp']])
            writer.writerow(["Algorithm",    ALGO_MAP.get(algo_id, "Unknown")])
            writer.writerow(["Error Mode",   ERROR_MODE_MAP.get(global_info['mode_used'], "Unknown")])
            writer.writerow(["Burst_Length", data.get('burst_len', 'N/A')])
            writer.writerow(["Total Points", global_info['total_points']])
            writer.writerow([])  # Empty row

            # Write column headers (v2.1 format: no Point_ID, added BER_Value & BER_Value_Act)
            writer.writerow([
                "BER_Index", "BER_Value",
                "Success_Count", "Fail_Count", "Total_Trials",
                "Success_Rate", "Flip_Count", "BER_Value_Act",
                "Clk_Count", "Avg_Clk_Per_Trial"
            ])

            # Write data rows
            for p in points:
                # Actual BER = total flipped bits / (total trials × W_valid)
                ber_act = p['Flip_Count'] / (p['Total_Trials'] * w_valid) if p['Total_Trials'] > 0 else 0.0

                writer.writerow([
                    p['BER_Index'],
                    f"{p['BER_Value']:.3f}",
                    p['Success_Count'],
                    p['Fail_Count'],
                    p['Total_Trials'],
                    f"{p['Success_Rate']:.3f}",     # Success/Total, 3 decimal places
                    p['Flip_Count'],
                    f"{ber_act:.6f}",
                    p['Clk_Count'],
                    f"{int(round(p['Avg_Clk']))}"   # Integer, no decimal
                ])

        print(f"\n[OK] Data saved to: {final_filename}")
        return final_filename   # Return path for auto-plotting
    except Exception as e:
        print(f"[ERROR] Failed to save CSV: {e}")
        return None

def print_results_table(data: Dict):
    """
    Print a summary table of results to the terminal (v2.1 post-processing format).

    Changes vs v2.0:
    - Removed ID column
    - Added BER_Value column
    - Renamed BER_Rate → Fail_Rate
    - Added BER_Act column (actual BER from Flip_Count)
    - Avg_Clk shown as integer
    """
    if not data:
        return

    global_info = data['global']
    points = data['points']
    algo_id = global_info['algo_used']

    algo_name = ALGO_MAP.get(algo_id, f"ID={algo_id}")
    mode_name = ERROR_MODE_MAP.get(global_info['mode_used'], f"Mode={global_info['mode_used']}")
    w_valid   = ALGO_W_VALID.get(algo_id, 41)

    print("\n" + "="*125)
    print(f"Test Results Summary — Algorithm: {algo_name} (W_valid={w_valid})  Mode: {mode_name}")
    print("="*125)
    # Column header (no ID, added BER_Value, Success_Rate and BER_Act)
    print(f"{'BER_Idx':<8} {'BER_Value':<10} {'Success':<10} {'Fail':<10} {'Total':<10} "
          f"{'Succ_Rate':<10} {'Flip_Sum':<10} {'BER_Act':<12} {'Clk_Sum':<16} {'Avg_Clk':<8}")
    print("-"*125)

    total_success = 0
    total_fail    = 0
    total_trials  = 0
    total_flips   = 0

    for p in points:
        ber_act = p['Flip_Count'] / (p['Total_Trials'] * w_valid) if p['Total_Trials'] > 0 else 0.0
        print(f"{p['BER_Index']:<8} {p['BER_Value']:<10.3f} "
              f"{p['Success_Count']:<10} {p['Fail_Count']:<10} {p['Total_Trials']:<10} "
              f"{p['Success_Rate']:<10.3f} {p['Flip_Count']:<10} "
              f"{ber_act:<12.6f} {p['Clk_Count']:<16} {int(round(p['Avg_Clk'])):<8}")
        total_success += p['Success_Count']
        total_fail    += p['Fail_Count']
        total_trials  += p['Total_Trials']
        total_flips   += p['Flip_Count']

    print("-"*125)
    overall_success_rate = total_success / total_trials if total_trials > 0 else 0.0
    overall_ber_act      = total_flips   / (total_trials * w_valid) if total_trials > 0 else 0.0
    print(f"Summary: Total_Success={total_success}  Total_Fail={total_fail}  "
          f"Total_Trials={total_trials}  "
          f"Overall_Success_Rate={overall_success_rate:.3f}  Overall_BER_Act={overall_ber_act:.6f}")
    print("="*125)

def _auto_plot(csv_path: str):
    """
    Automatically plot BER curve after saving CSV.
    Integrates the core logic from plot_ber_curve.py.
    The PNG is saved alongside the CSV file (same directory, same base name).
    """
    try:
        import matplotlib.pyplot as plt
        import matplotlib.ticker as ticker
    except ImportError:
        print("[WARNING] matplotlib not installed. Skipping auto-plot.")
        print("          Install with: pip install matplotlib")
        return

    print(f"\n[Plot] Generating BER curve from: {csv_path}")

    try:
        # ── Parse CSV ──────────────────────────────────────────────────────
        metadata = {}
        data_rows = []

        with open(csv_path, 'r', encoding='utf-8') as f:
            import csv as _csv
            reader = _csv.reader(f)
            rows = list(reader)

        # Parse metadata (rows 1~5)
        for row in rows[1:6]:
            if len(row) >= 2 and row[0].strip():
                metadata[row[0].strip()] = row[1].strip()

        # Find header row
        header_row_idx = None
        for i, row in enumerate(rows):
            if row and 'BER_Index' in row[0]:
                header_row_idx = i
                break

        if header_row_idx is None:
            print("[WARNING] Could not find BER_Index column in CSV. Skipping plot.")
            return

        headers = [h.strip() for h in rows[header_row_idx]]
        for row in rows[header_row_idx + 1:]:
            if not row or not row[0].strip():
                continue
            row_dict = {headers[i]: row[i].strip() for i in range(min(len(headers), len(row)))}
            data_rows.append(row_dict)

        if not data_rows:
            print("[WARNING] No data rows found. Skipping plot.")
            return

        # ── Extract X/Y ────────────────────────────────────────────────────
        ber_act_list     = []
        success_rate_list = []
        for row in data_rows:
            try:
                ber_act      = float(row.get('BER_Value_Act', 0))
                success_rate = float(row.get('Success_Rate', 0))
                ber_act_list.append(ber_act)
                success_rate_list.append(success_rate)
            except (ValueError, KeyError):
                continue

        if not ber_act_list:
            print("[WARNING] Could not extract BER_Value_Act or Success_Rate. Skipping plot.")
            return

        # ── Build title ────────────────────────────────────────────────────
        algo  = metadata.get('Algorithm', 'Unknown Algorithm')
        mode  = metadata.get('Error Mode', 'Unknown Mode')
        burst = metadata.get('Burst_Length', None)
        if ('Cluster' in mode or 'Burst' in mode) and burst and burst != 'N/A':
            title = f"{algo}  |  {mode}  |  Burst Length = {burst}"
        else:
            title = f"{algo}  |  {mode}"

        # ── Plot ───────────────────────────────────────────────────────────
        fig, ax = plt.subplots(figsize=(10, 6))
        ax.plot(ber_act_list, success_rate_list,
                marker='o', markersize=4, linewidth=1.5,
                color='steelblue', label='Success Rate')
        ax.set_xlabel('Actual BER (%)', fontsize=12)
        ax.set_ylabel('Success Rate', fontsize=12)
        ax.set_title(title, fontsize=13, fontweight='bold', pad=12)
        # X-axis: display as percentage, auto-select tick interval based on data range
        ax.xaxis.set_major_formatter(ticker.FuncFormatter(
            lambda x, _: f'{x * 100:.4g}%'   # e.g. 0.005→0.5%, 0.01→1%, 0.1→10%
        ))
        x_max = max(ber_act_list) if ber_act_list else 0.1
        # Choose tick interval: aim for ~5-10 ticks across the range
        if x_max <= 0.02:
            tick_step = 0.005   # 0.5% steps for range ≤ 2%
        elif x_max <= 0.05:
            tick_step = 0.01    # 1% steps for range ≤ 5%
        else:
            tick_step = 0.01    # 1% steps for range > 5%
        ax.xaxis.set_major_locator(ticker.MultipleLocator(tick_step))
        ax.set_xlim(left=0, right=x_max * 1.05)  # X-axis starts from 0, right margin 5%
        ax.set_ylim(-0.02, 1.05)
        ax.yaxis.set_major_formatter(ticker.FuncFormatter(
            lambda y, _: f'{y:.1%}'
        ))
        ax.grid(True, linestyle='--', alpha=0.5)
        ax.set_axisbelow(True)
        ax.legend(fontsize=10)
        # timestamp = metadata.get('Timestamp', '')
        # if timestamp:
        #     ax.annotate(f'Test: {timestamp}',
        #                 xy=(0.99, 0.02), xycoords='axes fraction',
        #                 ha='right', va='bottom', fontsize=8, color='gray')
        plt.tight_layout()

        # Save PNG alongside CSV (non-blocking: save only, do not call plt.show())
        png_path = os.path.splitext(csv_path)[0] + '_curve.png'
        plt.savefig(png_path, dpi=150, bbox_inches='tight')
        plt.close()
        print(f"[OK] BER curve saved to: {png_path}")
        # Open the PNG with the default system viewer (non-blocking)
        try:
            import subprocess
            if sys.platform.startswith('win'):
                os.startfile(png_path)          # Windows: open with default viewer
            elif sys.platform.startswith('darwin'):
                subprocess.Popen(['open', png_path])   # macOS
            else:
                subprocess.Popen(['xdg-open', png_path])  # Linux
        except Exception:
            pass  # If viewer fails, PNG is still saved — user can open manually

    except Exception as e:
        print(f"[WARNING] Auto-plot failed: {e}")


def main():
    # ─────────────────────────────────────────────────────────────────────────
    # BUG FIX (Risk #2): Add --port and --baudrate command-line arguments so
    # the user can specify the correct COM port without editing source code.
    # The default values fall back to DEFAULT_PORT / DEFAULT_BAUDRATE if the
    # arguments are not provided.
    # ─────────────────────────────────────────────────────────────────────────
    parser = argparse.ArgumentParser(
        description='FPGA Fault-Tolerant Test System Controller',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python py_controller_main.py                  # Use default COM8\n"
            "  python py_controller_main.py --port COM3      # Specify COM3\n"
            "  python py_controller_main.py --port /dev/ttyUSB0  # Linux\n"
        )
    )
    parser.add_argument(
        '--port', type=str, default=DEFAULT_PORT,
        help=f'Serial port name (default: {DEFAULT_PORT}). '
             f'Windows: COMx, Linux: /dev/ttyUSBx'
    )
    parser.add_argument(
        '--baudrate', type=int, default=DEFAULT_BAUDRATE,
        help=f'Baud rate (default: {DEFAULT_BAUDRATE})'
    )
    args = parser.parse_args()

    # 1. Get User Input
    params = get_user_input()
    if not params:
        return

    algo_id, error_mode, burst_len, sample_count = params

    # 2. Initialize Serial Port (use CLI args, fall back to defaults)
    controller = FpgaController(port=args.port, baudrate=args.baudrate)

    if not controller.open():
        print("Program exiting.")
        return

    try:
        # 3. Send Command
        if not controller.send_command(algo_id, error_mode, burst_len, sample_count):
            print("Failed to send command. Program exiting.")
            return

        # 4. Receive and Parse Response
        result_data = controller.receive_response()

        if result_data:
            # 5. Display Results
            print_results_table(result_data)

            # 6. Save to CSV (pass burst_len so it appears in the CSV header)
            result_data['burst_len'] = burst_len
            csv_path = save_to_csv(result_data, "test_results.csv")

            # 7. Auto-plot BER curve from the saved CSV
            if csv_path:
                _auto_plot(csv_path)
        else:
            print("No valid data received. Report generation skipped.")

    except KeyboardInterrupt:
        print("\n[WARNING] Test interrupted by user.")
    finally:
        controller.close()

if __name__ == "__main__":
    main()
