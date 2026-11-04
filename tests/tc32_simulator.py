"""TC32 UDP/TCP boundary fixture for the unmodified ULDAQ public API.

Frames follow ULDAQ v1.2.1 NetDiscovery, NetDaqDevice, AiETc32 and DioETc32.
Only commands used by the reconnect test are supported; unknown commands fail.
"""
import socket
import struct
import threading
import time


class TC32:
    def __init__(self, address="192.0.2.2", port=54211):
        self.address, self.port = address, port
        self.online = False
        self.temperature = 22.5
        self.types = bytes([1] * 64)
        self.measure = b"\0\0"
        self.fault = None
        self.errors = []
        self.connections = 0
        self.requests = 0
        self.faults = []
        self.stopped = threading.Event()
        self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp.bind((address, port))
        self.udp.settimeout(0.1)
        self.tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.tcp.bind((address, port))
        self.tcp.listen()
        self.tcp.settimeout(0.1)
        self.clients = set()
        for function in (self._udp, self._accept):
            threading.Thread(target=function, daemon=True).start()

    def discovery(self):
        return b"D" + struct.pack(
            "<6sHH16sHHHH4sHB22s", b"\x02\x00\x00\x00\x00\x32", 0x132,
            0x100, b"TC32-TEST       ", self.port, self.port + 1, 0, 0,
            socket.inet_aton(self.address), 0x100, 0, bytes(22))

    def _udp(self):
        while not self.stopped.is_set():
            try:
                data, source = self.udp.recvfrom(512)
                if self.online:
                    if data == b"D":
                        self.udp.sendto(self.discovery(), source)
                    elif data[:1] == b"C":
                        self.udp.sendto(b"C\0", source)
                    else:
                        self.errors.append(f"unknown UDP command {data.hex()}")
            except socket.timeout:
                pass
            except OSError:
                return

    def _accept(self):
        while not self.stopped.is_set():
            try:
                client, _ = self.tcp.accept()
                if not self.online:
                    client.close()
                    continue
                self.connections += 1
                self.clients.add(client)
                threading.Thread(target=self._client, args=(client,), daemon=True).start()
            except socket.timeout:
                pass
            except OSError:
                return

    @staticmethod
    def _read(client, count):
        data = b""
        while len(data) < count:
            part = client.recv(count - len(data))
            if not part:
                raise EOFError
            data += part
        return data

    def _response(self, command, data):
        if command == 0x52:
            return bytes(2)
        if command == 0x53:
            return struct.pack("<6H", *([0x100] * 6))
        if command == 0x14:
            return self.types
        if command == 0x15:
            if len(data) != 64:
                raise ValueError("invalid TC configuration length")
            self.types = data
            return b""
        if command == 0x18:
            return self.measure
        if command == 0x19:
            self.measure = data
            return b""
        if command == 0x1B:
            return b""
        if command in (0x3A, 0x3C):
            return bytes([24, 1, 1, 0, 0, 0]) * (2 if command == 0x3A else 4)
        if command == 0x20:
            return bytes(576)
        if command == 0x00:
            return bytes(2)
        if command == 0x02:
            return bytes(8)
        if command == 0x12:
            _, scale, base, expansion = struct.unpack("<BBII", data)
            if expansion:
                raise ValueError("driver queried absent EXP-32 channels")
            value = self.temperature
            if scale != 0:
                raise ValueError("unexpected temperature scale")
            return struct.pack("<f", value) * base.bit_count()
        raise ValueError(f"unknown TCP command 0x{command:02x}")

    def _client(self, client):
        try:
            while self.online and not self.stopped.is_set():
                header = self._read(client, 6)
                delimiter, command, frame, status, count = struct.unpack("<BBBBH", header)
                payload = self._read(client, count + 1)
                if delimiter != 0xDB or sum(header + payload) % 256 != 255:
                    raise ValueError("invalid request frame")
                self.requests += 1
                selected = self.fault and command == self.fault[0]
                if selected and command == 0x12:
                    # Target the final channel so no later read can mask a bad sample.
                    selected = struct.unpack("<BBII", payload[:-1])[2] == (1 << 31)
                if selected:
                    mode = self.fault[1]
                    self.fault = None
                    self.online = False
                    self.faults.append((command, mode, time.monotonic()))
                    if mode == "short":
                        client.sendall(b"\xdb\x92\x01")
                    elif mode == "timeout":
                        self.stopped.wait(10)
                    client.shutdown(socket.SHUT_WR)
                    return
                response = self._response(command, payload[:-1])
                reply = struct.pack("<BBBBH", 0xDB, command | 0x80, frame, 0, len(response)) + response
                client.sendall(reply + bytes([(255 - sum(reply)) & 255]))
        except (EOFError, ConnectionError, OSError):
            pass
        except Exception as error:
            self.errors.append(str(error))
        finally:
            self.clients.discard(client)
            client.close()

    def close(self):
        self.stopped.set()
        self.udp.close()
        self.tcp.close()
        for client in list(self.clients):
            try:
                client.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            client.close()
