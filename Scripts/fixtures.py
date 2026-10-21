"""Small shared fixtures for isolated integration scripts; no production state."""
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import struct
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def create_admin(home):
    password, salt = secrets.token_urlsafe(24), secrets.token_bytes(32)
    record = dict(salt=base64.b64encode(salt).decode(), hash=base64.b64encode(hashlib.pbkdf2_hmac('sha256', password.encode(), salt, 600000)).decode(), iterations=600000)
    target = home/'state/admin.json'
    target.write_text(json.dumps(record))
    target.chmod(0o600)
    return password


def browser_environment(env):
    env = dict(env)
    brave = Path('/Applications/Brave Browser.app/Contents/MacOS/Brave Browser')
    if not env.get('AELAB_TEST_BROWSER') and brave.exists():
        env['AELAB_TEST_BROWSER'] = str(brave)
    return env


def stop_process(process, timeout=8):
    process.terminate()
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def exact(sock, count):
    data = b''
    while len(data) < count:
        part = sock.recv(count - len(data))
        if not part: raise EOFError('WebSocket closed')
        data += part
    return data

class Wire:
    def __init__(self, pairing, token=None, origin=None, trusted=True, hostname='localhost'):
        ctx = ssl.create_default_context(cadata=pairing['certificate']) if trusted else ssl.create_default_context()
        self.socket = ctx.wrap_socket(socket.create_connection(('127.0.0.1', int(pairing['endpoint'].split(':')[-1])), timeout=5), server_hostname=hostname)
        key = base64.b64encode(os.urandom(16)).decode()
        headers = f'GET /connect HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\nAuthorization: Bearer {token or pairing["token"]}\r\n'
        if origin: headers += f'Origin: {origin}\r\n'
        self.socket.sendall((headers + '\r\n').encode())
        response = b''
        while not response.endswith(b'\r\n\r\n'): response += exact(self.socket, 1)
        self.accepted = response.startswith(b'HTTP/1.1 101 ')
    def send(self, message):
        data = json.dumps(dict(version=1, **message)).encode(); mask = os.urandom(4)
        length = bytes([0x80 | len(data)]) if len(data) < 126 else b'\xfe' + struct.pack('!H', len(data)) if len(data) <= 65535 else b'\xff' + struct.pack('!Q', len(data))
        self.socket.sendall(b'\x81' + length + mask + bytes(byte ^ mask[n % 4] for n, byte in enumerate(data)))
    def receive(self):
        data = b''
        while True:
            first, second = exact(self.socket, 2); length = second & 127
            if length == 126: length = struct.unpack('!H', exact(self.socket, 2))[0]
            if length == 127: length = struct.unpack('!Q', exact(self.socket, 8))[0]
            payload = exact(self.socket, length)
            if first & 15 == 8: raise EOFError('WebSocket closed')
            if first & 15 == 9:
                mask = os.urandom(4); self.socket.sendall(b'\x8a' + bytes([0x80 | len(payload)]) + mask + bytes(b ^ mask[n % 4] for n, b in enumerate(payload))); continue
            data += payload
            if first & 128: return json.loads(data)
    def close(self): self.socket.close()

