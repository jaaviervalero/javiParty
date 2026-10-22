#!/usr/bin/env python3
"""Genera tests/fixtures/dsu_fixtures.json con paquetes DSU de ejemplo y los valores
esperados, usando la implementación Python (zlib.crc32) como referencia.

    python3 tools/gen_fixtures.py
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsu_packets as dsu  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "fixtures", "dsu_fixtures.json")
SERVER_ID = 0xCAFEBABE
CLIENT_ID = 0x12345678
MAC = bytes([0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6])


def f32(v):
    """Redondea a float32 como lo hará el decodificador."""
    return struct.unpack("<f", struct.pack("<f", v))[0]


def main():
    accel = (0.125, -0.98, 0.5)
    gyro = (12.5, -270.25, 3.0)
    data = dsu.data_response(
        SERVER_ID, 1, 4242,
        buttons1=0x80 | 0x10 | 0x01,   # D-pad izq + arriba + Share
        buttons2=0x20 | 0x80 | 0x01,   # A + Y + L2
        home=1, touch=0, sticks=(255, 0, 128, 191),
        analog=bytes(range(1, 13)), touch1=(1, 7, 300, 500), touch2=(0, 0, 0, 0),
        timestamp_us=123456789012, accel=accel, gyro=gyro, mac=MAC, battery=0xEE)
    info = dsu.info_response(SERVER_ID, 2, state=2, model=2, connection=2, mac=MAC, battery=4)
    info_empty = dsu.info_response(SERVER_ID, 3, state=0, model=0, connection=0, battery=0)

    fixtures = {
        "crc_check": {"ascii": "123456789", "crc": 0xCBF43926},
        "data": {
            "hex": data.hex(),
            "expect": {
                "type": dsu.MSG_DATA, "sender_id": SERVER_ID, "slot": 1, "slot_state": 2, "model": 2,
                "connection": 2, "mac": MAC.hex(), "battery": 0xEE, "connected": True,
                "packet_number": 4242,
                # (byte16 << 8 | byte17) | HOME (0x10000)
                "buttons": ((0x80 | 0x10 | 0x01) << 8) | (0x20 | 0x80 | 0x01) | 0x10000,
                "left_stick": [1.0, -1.0], "right_stick": [0.0, (191 - 128) / 127.0],
                "analog": bytes(range(1, 13)).hex(),
                "touch1": {"active": True, "id": 7, "x": 300, "y": 500},
                "motion_timestamp": 123456789012,
                "accel": [f32(v) for v in accel], "gyro": [f32(v) for v in gyro],
            },
        },
        "info": {
            "hex": info.hex(),
            "expect": {"type": dsu.MSG_INFO, "slot": 2, "slot_state": 2, "model": 2, "connection": 2,
                       "mac": MAC.hex(), "battery": 4},
        },
        "info_empty": {
            "hex": info_empty.hex(),
            "expect": {"type": dsu.MSG_INFO, "slot": 3, "slot_state": 0},
        },
        # Peticiones del cliente tal como las debe construir DSUProtocol (GDScript).
        "client_info_request": {
            "client_id": CLIENT_ID, "slots": [0, 1, 2, 3],
            "hex": dsu.build_packet(dsu.MSG_INFO, struct.pack("<i", 4) + bytes([0, 1, 2, 3]),
                                    CLIENT_ID, b"DSUC").hex(),
        },
        "client_data_request": {
            "client_id": CLIENT_ID, "flags": 1, "slot": 2,
            "hex": dsu.build_packet(dsu.MSG_DATA, bytes([1, 2]) + bytes(6), CLIENT_ID, b"DSUC").hex(),
        },
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(fixtures, f, indent=2)
        f.write("\n")
    print(f"Escrito {os.path.normpath(OUT)} (paquete de datos: {len(data)} bytes, info: {len(info)} bytes)")


if __name__ == "__main__":
    main()
