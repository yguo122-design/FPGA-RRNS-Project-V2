import serial
import serial.tools.list_ports
import argparse
import time
import struct
import csv
import os
from datetime import datetime
from typing import Optional, List, Dict, Tuple

# ================= Configuration Constants =================
DEFAULT_PORT = 'COM8'       # Default serial port (Linux: /dev/ttyUSB0)
DEFAULT_BAUDRATE = 921600   # Baud rate
TIMEOUT_SEC = 100.0          # Receive timeout (seconds). FPGA may need time for large sample counts.

# Algorithm Mapping (User Specified Order)
# 0: 2NRM, 1: 3NRM, 2: C-RRNS, 3: RS
ALGO_MAP = {
    0: "2NRM-RRNS",
    1: "3NRM-RRNS",
    2: "C-RRNS",
    3: "RS"
}

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

# Uplink: Header(2) + CmdID(1) + Length(2) + GlobalInfo(3) + Data(91*22) + Checksum(1) = 2011 Bytes
# Length field value = GlobalInfo(3) + PerPointData(91*22=2002) = 2005 = 0x07D5
# (Note: Spec v1.7 doc example shows 0x077A=1914 which was for 21-byte/point version.
#  With 22-byte/point: 3+2002=2005=0x07D5. This implementation uses 0x07D5.)
FRAME_LEN_RESP = 2011
PAYLOAD_DATA_POINTS = 91
EXPECTED_LENGTH_FIELD = 0x07D5  # 2005: GlobalInfo(3) + 91*22(2002)

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
                total_trials = success_cnt + fail_cnt
                ber_rate     = fail_cnt / total_trials if total_trials > 0 else 0.0
                avg_clk      = clk_cnt  / total_trials if total_trials > 0 else 0.0

                point_res = {
                    'Point_ID':      i + 1,
                    'BER_Index':     ber_idx,
                    'Success_Count': success_cnt,
                    'Fail_Count':    fail_cnt,
                    'Flip_Count':    flip_cnt,
                    'Clk_Count':     clk_cnt,
                    'Total_Trials':  total_trials,
                    'BER_Rate':      ber_rate,
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
    """Save results to a CSV file (v2.0 format: 22-byte/point statistical aggregation)."""
    if not data:
        return

    global_info = data['global']
    points = data['points']

    # Add timestamp to filename to avoid overwriting
    base_name = os.path.splitext(filename)[0]
    ext = os.path.splitext(filename)[1]
    final_filename = f"{base_name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}{ext}"

    try:
        with open(final_filename, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            # Write header info
            writer.writerow(["Test Report (v2.0 Statistical Aggregation, 22-byte/point)"])
            writer.writerow(["Timestamp",    data['timestamp']])
            writer.writerow(["Algorithm",    ALGO_MAP.get(global_info['algo_used'], "Unknown")])
            writer.writerow(["Error Mode",   ERROR_MODE_MAP.get(global_info['mode_used'], "Unknown")])
            writer.writerow(["Total Points", global_info['total_points']])
            writer.writerow([])  # Empty row

            # Write column headers (v2.0 format)
            writer.writerow([
                "Point_ID", "BER_Index",
                "Success_Count", "Fail_Count", "Total_Trials",
                "BER_Rate", "Flip_Count", "Clk_Count", "Avg_Clk_Per_Trial"
            ])

            # Write data rows
            for p in points:
                writer.writerow([
                    p['Point_ID'],
                    p['BER_Index'],
                    p['Success_Count'],
                    p['Fail_Count'],
                    p['Total_Trials'],
                    f"{p['BER_Rate']:.6f}",
                    p['Flip_Count'],
                    p['Clk_Count'],
                    f"{p['Avg_Clk']:.2f}"
                ])

        print(f"\n[OK] Data saved to: {final_filename}")
    except Exception as e:
        print(f"[ERROR] Failed to save CSV: {e}")

def print_results_table(data: Dict):
    """Print a summary table of results to the terminal (v2.0 statistical aggregation format)."""
    if not data:
        return

    global_info = data['global']
    points = data['points']

    algo_name = ALGO_MAP.get(global_info['algo_used'], f"ID={global_info['algo_used']}")
    mode_name = ERROR_MODE_MAP.get(global_info['mode_used'], f"Mode={global_info['mode_used']}")

    print("\n" + "="*110)
    print(f"Test Results Summary — Algorithm: {algo_name}  Mode: {mode_name}  "
          f"(v2.0 Statistical Aggregation, 22-byte/point)")
    print("="*110)
    # Column header
    print(f"{'ID':<4} {'BER_Idx':<8} {'Success':<10} {'Fail':<10} {'Total':<10} "
          f"{'BER_Rate':<12} {'Flip_Sum':<10} {'Clk_Sum':<16} {'Avg_Clk':<10}")
    print("-"*110)

    total_success = 0
    total_fail    = 0
    total_trials  = 0

    for p in points:
        print(f"{p['Point_ID']:<4} {p['BER_Index']:<8} "
              f"{p['Success_Count']:<10} {p['Fail_Count']:<10} {p['Total_Trials']:<10} "
              f"{p['BER_Rate']:<12.6f} {p['Flip_Count']:<10} "
              f"{p['Clk_Count']:<16} {p['Avg_Clk']:<10.2f}")
        total_success += p['Success_Count']
        total_fail    += p['Fail_Count']
        total_trials  += p['Total_Trials']

    print("-"*110)
    overall_ber = total_fail / total_trials if total_trials > 0 else 0.0
    print(f"Summary: Total_Success={total_success}  Total_Fail={total_fail}  "
          f"Total_Trials={total_trials}  Overall_BER={overall_ber:.6f}")
    print("="*110)

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

            # 6. Save to CSV
            save_to_csv(result_data, "test_results.csv")
        else:
            print("No valid data received. Report generation skipped.")

    except KeyboardInterrupt:
        print("\n[WARNING] Test interrupted by user.")
    finally:
        controller.close()

if __name__ == "__main__":
    main()
