"""Paquetes DSU (cemuhook v1001) del lado SERVIDOR, para el simulador y los fixtures.

Implementación independiente de la de GDScript (usa struct + zlib.crc32), para que
los tests comparen dos implementaciones distintas en lugar de una consigo misma.
Referencia: https://v1993.github.io/cemuhook-protocol/
"""
import struct
import zlib

PORT = 26760
VERSION = 1001
MSG_VERSION = 0x100000
MSG_INFO = 0x100001
MSG_DATA = 0x100002


def build_packet(msg_type: int, payload: bytes, sender_id: int, magic: bytes = b"DSUS") -> bytes:
    # Cabecera: magic, u16 versión, u16 longitud (sin cabecera, con message_type),
    # u32 CRC (a 0 para calcularlo), u32 id del emisor; luego u32 message_type.
    body = struct.pack("<I", msg_type) + payload
    header = magic + struct.pack("<HHII", VERSION, len(body), 0, sender_id)
    pkt = bytearray(header + body)
    struct.pack_into("<I", pkt, 8, zlib.crc32(pkt) & 0xFFFFFFFF)
    return bytes(pkt)


def shared(slot: int, state: int, model: int, connection: int, mac: bytes, battery: int) -> bytes:
    """Parte común de las respuestas (11 bytes)."""
    return struct.pack("<BBBB", slot, state, model, connection) + mac[:6].ljust(6, b"\0") + bytes([battery])


def info_response(sender_id: int, slot: int, state: int = 2, model: int = 2, connection: int = 2,
                  mac: bytes = b"\0" * 6, battery: int = 5) -> bytes:
    return build_packet(MSG_INFO, shared(slot, state, model, connection, mac, battery) + b"\0", sender_id)


def data_response(sender_id: int, slot: int, packet_number: int, *, buttons1: int = 0, buttons2: int = 0,
                  home: int = 0, touch: int = 0, sticks=(128, 128, 128, 128), analog=bytes(12),
                  touch1=(0, 0, 0, 0), touch2=(0, 0, 0, 0), timestamp_us: int = 0,
                  accel=(0.0, 0.0, -1.0), gyro=(0.0, 0.0, 0.0), mac: bytes = b"\0" * 6,
                  battery: int = 5, model: int = 2, connection: int = 2) -> bytes:
    p = shared(slot, 2, model, connection, mac, battery)
    p += struct.pack("<BI", 1, packet_number)                 # conectado, nº de paquete
    p += struct.pack("<BBBB", buttons1, buttons2, home, touch)
    p += struct.pack("<BBBB", *sticks)                        # LX, LY, RX, RY
    p += bytes(analog)[:12].ljust(12, b"\0")
    p += struct.pack("<BBHH", *touch1) + struct.pack("<BBHH", *touch2)
    p += struct.pack("<Q", timestamp_us)
    p += struct.pack("<fff", *accel) + struct.pack("<fff", *gyro)
    assert len(p) == 80
    return build_packet(MSG_DATA, p, sender_id)


def parse_client_packet(pkt: bytes):
    """Valida una petición del cliente. Devuelve (msg_type, payload, client_id) o None."""
    if len(pkt) < 20 or pkt[:4] != b"DSUC":
        return None
    version, length, crc, client_id = struct.unpack_from("<HHII", pkt, 4)
    if version != VERSION or len(pkt) < 16 + length:
        return None
    pkt = bytearray(pkt[:16 + length])
    struct.pack_into("<I", pkt, 8, 0)
    if zlib.crc32(pkt) & 0xFFFFFFFF != crc:
        return None
    (msg_type,) = struct.unpack_from("<I", pkt, 16)
    return msg_type, bytes(pkt[20:]), client_id


# --- Lado cliente (para tools/dsu_probe.py) ---

BUTTON_BITS = [  # (nombre, máscara) sobre (byte16 << 8 | byte17), más HOME/TOUCH aparte
    ("LEFT", 0x8000), ("DOWN", 0x4000), ("RIGHT", 0x2000), ("UP", 0x1000),
    ("OPTIONS", 0x0800), ("R3", 0x0400), ("L3", 0x0200), ("SHARE", 0x0100),
    ("Y", 0x0080), ("B", 0x0040), ("A", 0x0020), ("X", 0x0010),
    ("R1", 0x0008), ("L1", 0x0004), ("R2", 0x0002), ("L2", 0x0001),
    ("HOME", 0x10000), ("TOUCH", 0x20000),
]


def client_packet(msg_type: int, payload: bytes, client_id: int) -> bytes:
    return build_packet(msg_type, payload, client_id, b"DSUC")


def info_request(client_id: int) -> bytes:
    return client_packet(MSG_INFO, struct.pack("<i", 4) + bytes([0, 1, 2, 3]), client_id)


def data_request(client_id: int, slot: int) -> bytes:
    return client_packet(MSG_DATA, bytes([1, slot]) + bytes(6), client_id)


def parse_server_packet(pkt: bytes):
    """Valida una respuesta del servidor y devuelve un dict, o None si no es válida."""
    if len(pkt) < 20 or pkt[:4] != b"DSUS":
        return None
    version, length, crc, _sid = struct.unpack_from("<HHII", pkt, 4)
    if version != VERSION or len(pkt) < 16 + length:
        return None
    pkt = bytearray(pkt[:16 + length])
    struct.pack_into("<I", pkt, 8, 0)
    if zlib.crc32(pkt) & 0xFFFFFFFF != crc:
        return None
    (msg_type,) = struct.unpack_from("<I", pkt, 16)
    o = 20
    msg = {"type": msg_type, "slot": pkt[o], "state": pkt[o + 1]}
    if msg_type == MSG_DATA and length >= 84:
        buttons = (pkt[o + 16] << 8) | pkt[o + 17]
        if pkt[o + 18]:
            buttons |= 0x10000
        if pkt[o + 19]:
            buttons |= 0x20000
        msg["buttons"] = buttons
        msg["sticks"] = tuple(pkt[o + 20:o + 24])
        msg["pn"] = struct.unpack_from("<I", pkt, o + 12)[0]
        msg["ts"] = struct.unpack_from("<Q", pkt, o + 48)[0]
        msg["accel"] = struct.unpack_from("<fff", pkt, o + 56)
        msg["gyro"] = struct.unpack_from("<fff", pkt, o + 68)
    return msg


def button_names(buttons: int):
    return [n for n, m in BUTTON_BITS if buttons & m]
