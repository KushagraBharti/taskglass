#!/usr/bin/env python3
"""Tiny deterministic Core ML convolution fixture, using only Python's stdlib.
Wire fields follow Apple's coremltools mlmodel/format protobuf schemas.
No third-party model, generated source, network access or Python packages.
"""
from pathlib import Path
import struct

def varint(n):
    out = bytearray()
    while n > 127:
        out.append((n & 127) | 128)
        n >>= 7
    return bytes(out) + bytes([n])

def number(field, value):
    return varint(field << 3) + varint(value)

def message(field, data):
    if isinstance(data, str):
        data = data.encode()
    return varint((field << 3) | 2) + varint(len(data)) + data

def feature(name):
    array = b''.join(number(1, n) for n in [32, 64, 64]) + number(2, 65568)
    return message(1, name) + message(3, message(5, array))

layers = b''
for i in range(8):
    # Positive nonzero weights prevent a constant-zero network being optimized away.
    weights = b''.join(struct.pack('<f', ((j * 17 % 31) + 1) / 9000) for j in range(32 * 32 * 9))
    convolution = number(1, 32) + number(2, 32) + number(10, 1)
    convolution += number(20, 3) * 2 + number(30, 1) * 2 + message(51, b'')
    convolution += message(90, message(1, weights))
    layer = message(1, f'conv{i}') + message(2, 'input' if i == 0 else f'x{i}')
    layer += message(3, 'output' if i == 7 else f'x{i+1}') + message(100, convolution)
    layers += message(1, layer)
model = number(1, 4) + message(2, message(1, feature('input')) + message(10, feature('output'))) + message(500, layers)
path = Path('.build/checks/neural-fixture.mlmodel')
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(model)
