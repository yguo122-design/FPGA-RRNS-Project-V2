# py_uart_driver.py
# FPGA Multi-Algorithm Fault-Tolerant Test System - PC-side UART Driver Layer
# Responsibilities: Serial communication, frame encapsulation/parsing, CRC verification, timeout retries

import serial
import serial.tools.list_ports
import time
import threading
import logging
from typing import Optional, Tuple, List
from dataclasses import dataclass

# ================= Configuration Constants =================
FRAME_HEADER = b'\xAA\x55'  # Frame Header
FRAME_TAIL = b'\x55\xAA'    # Frame Tail (Optional, enhances robustness)
MAX_FRAME_SIZE = 1024       # Maximum frame length (bytes)
DEFAULT_TIMEOUT = 10       # Default timeout (seconds)
MAX_RETRIES = 3             # Maximum retry attempts

# Command ID Definitions
CMD_SET_CONFIG    = 0x01  # Set FPGA configuration (Algo selection, BER target, etc.)
CMD_ECHO          = 0x02  # Loopback test
CMD_START_TEST    = 0x03  # Start automated test
CMD_STOP_TEST     = 0x04  # Stop test
CMD_GET_STATUS    = 0x05  # Get current status
CMD_SEND_DATA     = 0x10  # Send test data (Data In)
CMD_RECV_DATA     = 0x11  # Receive test results (Data Out)
CMD_INJECT_ERROR  = 0x20  # Manually inject errors (Debug use)

# Logging Configuration
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# ================= Utility Function: CRC16-CCITT =================
def calculate_crc16(data: bytes) -> int:
    """
    Calculate CRC16-CCITT (Polynomial 0x1021, Initial Value 0xFFFF)
    Commonly used in communication protocols for integrity check.
    """
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = (crc << 1) ^ 0x1021
            else:
                crc <<= 1
            crc &= 0xFFFF
    return crc

# ================= Data Classes =================
@dataclass
class UartFrame:
    """UART Frame Structure"""
    cmd_id: int
    payload: bytes
    crc: int = 0
    
    def to_bytes(self) -> bytes:
        """Serialize the frame into a byte stream"""
        length = len(self.payload)
        # Frame Structure: Header(2) + Len(1) + Cmd(1) + Payload(N) + CRC(2) + Tail(2)
        # Note: CRC covers Len + Cmd + Payload
        data_for_crc = bytes([length, self.cmd_id]) + self.payload
        self.crc = calculate_crc16(data_for_crc)
        
        frame = FRAME_HEADER
        frame += bytes([length, self.cmd_id])
        frame += self.payload
        frame += self.crc.to_bytes(2, 'big')
        frame += FRAME_TAIL
        return frame

    @staticmethod
    def from_bytes(data: bytes) -> Optional['UartFrame']:
        """Parse frame from byte stream (Header and Tail must be stripped beforehand)"""
        if len(data) < 4: # Min: Len(1) + Cmd(1) + CRC(2)
            return None
        
        length = data[0]
        cmd_id = data[1]
        payload = data[2:2+length]
        received_crc = int.from_bytes(data[2+length:2+length+2], 'big')
        
        # Validate length
        if len(payload) != length:
            logger.warning(f"Frame length mismatch: expected {length}, got {len(payload)}")
            return None
            
        # Validate CRC
        data_for_crc = bytes([length, cmd_id]) + payload
        calc_crc = calculate_crc16(data_for_crc)
        
        if calc_crc != received_crc:
            logger.warning(f"CRC check failed: expected {hex(calc_crc)}, got {hex(received_crc)}")
            return None
            
        return UartFrame(cmd_id=cmd_id, payload=payload, crc=received_crc)

# ================= Core Driver Class =================
class UartDriver:
    # Updated default baudrate to 921600 for high-speed data transfer
    def __init__(self, port: str, baudrate: int = 921600, timeout: float = DEFAULT_TIMEOUT):
        self.port_name = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.serial_conn: Optional[serial.Serial] = None
        self.lock = threading.Lock()
        self._is_open = False
        
        # Receive buffer for handling fragmented packets
        self.rx_buffer = bytearray()

    def list_ports(self) -> List[str]:
        """List available serial ports"""
        ports = serial.tools.list_ports.comports()
        return [f"{p.device} - {p.description}" for p in ports]

    def open(self) -> bool:
        """Open the serial port"""
        try:
            self.serial_conn = serial.Serial(
                port=self.port_name,
                baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=self.timeout
            )
            self._is_open = True
            self.rx_buffer.clear()
            logger.info(f"Serial port opened: {self.port_name} @ {self.baudrate} bps")
            return True
        except Exception as e:
            logger.error(f"Failed to open serial port: {e}")
            return False

    def close(self):
        """Close the serial port"""
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.close()
            self._is_open = False
            logger.info("Serial port closed")

    def _write_raw(self, data: bytes) -> bool:
        """Low-level write operation"""
        if not self._is_open:
            return False
        try:
            with self.lock:
                self.serial_conn.write(data)
                self.serial_conn.flush()
            return True
        except Exception as e:
            logger.error(f"Write failed: {e}")
            return False

    def _read_raw(self, size: int) -> Optional[bytes]:
        """Low-level read operation for a specific number of bytes"""
        if not self._is_open:
            return None
        try:
            with self.lock:
                data = self.serial_conn.read(size)
            return data if len(data) == size else None
        except Exception as e:
            logger.error(f"Read failed: {e}")
            return None

    def _find_frame(self) -> Optional[UartFrame]:
        """
        Search for a complete frame in the receive buffer.
        Handles packet sticking (concatenation) and fragmentation.
        """
        # Search for frame header
        header_idx = self.rx_buffer.find(FRAME_HEADER)
        if header_idx == -1:
            # No header found, clear the first half of buffer to prevent overflow if garbage accumulates
            if len(self.rx_buffer) > MAX_FRAME_SIZE:
                self.rx_buffer = self.rx_buffer[-MAX_FRAME_SIZE:]
            return None
        
        # Discard garbage data before the header
        if header_idx > 0:
            logger.debug(f"Discarding {header_idx} bytes before header")
            self.rx_buffer = self.rx_buffer[header_idx:]
            header_idx = 0
            
        # Check if we have enough bytes for length info
        if len(self.rx_buffer) < 4: # Header(2) + Len(1) + Cmd(1)
            return None
            
        length = self.rx_buffer[2]
        # Total frame length = Header + Len + Cmd + Payload + CRC + Tail
        frame_total_len = 2 + 1 + 1 + length + 2 + 2 
        
        # Check if the full frame has been received
        if len(self.rx_buffer) < frame_total_len:
            return None
            
        # Extract frame data (excluding Header and Tail for parsing)
        # Buffer structure: [Header][Len][Cmd][Payload][CRC][Tail]
        # We pass [Len][Cmd][Payload][CRC] to from_bytes? 
        # Actually from_bytes expects [Len][Cmd][Payload] and checks CRC internally.
        # So we slice from index 2 (after Header) up to before Tail.
        frame_data_content = self.rx_buffer[2 : 2 + 1 + 1 + length + 2] # Len + Cmd + Payload + CRC
        tail_check = self.rx_buffer[frame_total_len-2 : frame_total_len]
        
        if tail_check != FRAME_TAIL:
            logger.warning("Frame tail mismatch, searching for next header...")
            # Tail error, discard current header byte and search again
            self.rx_buffer = self.rx_buffer[1:]
            return self._find_frame()
            
        # Parse the frame content (Len + Cmd + Payload + CRC)
        # Note: from_bytes expects data starting with Length
        frame = UartFrame.from_bytes(frame_data_content)
        
        if frame:
            # Successfully parsed, remove this frame from buffer
            self.rx_buffer = self.rx_buffer[frame_total_len:]
            return frame
        else:
            # CRC error or format error, discard current header byte and search again
            self.rx_buffer = self.rx_buffer[1:]
            return self._find_frame()

    def send_command(self, cmd_id: int, payload: bytes = b'', retries: int = MAX_RETRIES) -> Optional[UartFrame]:
        """
        Send a command and wait for a response.
        Includes automatic retry mechanism.
        """
        tx_frame = UartFrame(cmd_id=cmd_id, payload=payload)
        tx_data = tx_frame.to_bytes()
        
        for attempt in range(retries):
            logger.debug(f"Sending CMD {hex(cmd_id)} (Attempt {attempt+1}/{retries})")
            
            if not self._write_raw(tx_data):
                continue
                
            # Wait for response
            start_time = time.time()
            while time.time() - start_time < self.timeout:
                # Read new data chunks
                new_data = self._read_raw(64) 
                if new_data:
                    self.rx_buffer.extend(new_data)
                    
                    # Try to parse a frame
                    resp_frame = self._find_frame()
                    if resp_frame:
                        # Simple validation: Response CMD ID should match request CMD ID
                        # (In complex systems, use Transaction IDs)
                        if resp_frame.cmd_id == cmd_id:
                            logger.info(f"CMD {hex(cmd_id)} Success")
                            return resp_frame
                        else:
                            logger.debug(f"Received unexpected CMD {hex(resp_frame.cmd_id)}, discarding.")
                            # Frame already removed from buffer by _find_frame, so we just loop
                            
            logger.warning(f"Timeout waiting for CMD {hex(cmd_id)}")
            
        logger.error(f"CMD {hex(cmd_id)} Failed after {retries} retries")
        return None

    def send_data_block(self, data: bytes, chunk_size: int = 64) -> bool:
        """
        Send large data blocks (chunked transmission).
        Used for sending long test vectors to FPGA Data_In.
        """
        total_len = len(data)
        offset = 0
        
        while offset < total_len:
            chunk = data[offset:offset+chunk_size]
            # Construct payload with offset: [Offset_H, Offset_L] + Chunk
            payload = offset.to_bytes(2, 'big') + chunk
            
            resp = self.send_command(CMD_SEND_DATA, payload)
            if not resp:
                logger.error(f"Failed to send chunk at offset {offset}")
                return False
            
            # Optional: Parse response to confirm FPGA acceptance
            offset += len(chunk)
            logger.debug(f"Sent chunk {offset}/{total_len}")
            
        return True

# ================= Test Entry Point =================
if __name__ == "__main__":
    # Update port name as needed (e.g., "COM3" for Windows, "/dev/ttyUSB0" for Linux)
    driver = UartDriver("COM3", baudrate=921600) 
    
    print(f"Initializing Serial Port: {driver.port_name} @ {driver.baudrate} bps")
    print("Available Ports:", driver.list_ports())
    
    if driver.open():
        print("Serial port opened successfully. Sending loopback test...")
        
        # Send a longer payload to test high-speed stability
        test_payload = b'Hello FPGA @ 921600bps! ' * 10 
        resp = driver.send_command(CMD_ECHO, test_payload)
        
        if resp:
            print(f"Response received (Length={len(resp.payload)}): {resp.payload[:20]}...")
            if resp.payload == test_payload:
                print("Data verification passed!")
            else:
                print("Data content mismatch!")
        else:
            print("No response (Please ensure FPGA is configured for 921600 baud rate)")
        
        driver.close()
    else:
        print("Failed to open serial port")