#!/usr/bin/env python3
"""Prepare an experimental vibrator lookup patch for the known donor library."""

import argparse
import hashlib
import struct
from pathlib import Path


EXPECTED_SHA256 = "4a434702dd7c9397fe9e38d03ce5fdf5a3a6260dcdb911a904acf707b4e9cd2c"
SUFFIX_OFFSET = 0xAB40
SUFFIX = b"/vibratorfeature\0"
ADR_OFFSETS = {0xD4B8: 0x30FCD901, 0xDCA8: 0x30FC9981}


def patch(data: bytes) -> bytes:
    if hashlib.sha256(data).hexdigest() != EXPECTED_SHA256:
        raise ValueError("Unexpected library; refusing to patch a different build")
    if data[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", data, 18)[0] != 183:
        raise ValueError("Expected a little-endian AArch64 ELF")

    phoff = struct.unpack_from("<Q", data, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", data, 54)
    if phentsize != 56:
        raise ValueError("Unexpected ELF program header size")

    loads = []
    for i in range(phnum):
        offset = phoff + i * phentsize
        kind, flags, fileoff, vaddr, _, filesz, memsz, _ = struct.unpack_from(
            "<IIQQQQQQ", data, offset
        )
        if kind == 1:
            loads.append((offset, flags, fileoff, vaddr, filesz, memsz))
    matches = [
        item for item in loads
        if item[1:] == (4, 0, 0, SUFFIX_OFFSET, SUFFIX_OFFSET)
    ]
    if len(matches) != 1 or any(
        fileoff > 0 and fileoff < SUFFIX_OFFSET + len(SUFFIX)
        for _, _, fileoff, _, _, _ in loads
    ):
        raise ValueError("Unexpected ELF load layout")
    if data[SUFFIX_OFFSET:SUFFIX_OFFSET + len(SUFFIX)] != bytes(len(SUFFIX)):
        raise ValueError("Expected empty padding after the read-only segment")

    result = bytearray(data)
    result[SUFFIX_OFFSET:SUFFIX_OFFSET + len(SUFFIX)] = SUFFIX
    ph = matches[0][0]
    struct.pack_into("<QQ", result, ph + 32, SUFFIX_OFFSET + len(SUFFIX), SUFFIX_OFFSET + len(SUFFIX))
    for offset, original in ADR_OFFSETS.items():
        if struct.unpack_from("<I", data, offset)[0] != original:
            raise ValueError(f"Unexpected instruction at {offset:#x}")
        displacement = SUFFIX_OFFSET - offset
        if not -(1 << 20) <= displacement < (1 << 20):
            raise ValueError("Replacement is outside ADR range")
        immediate = displacement & ((1 << 21) - 1)
        instruction = 0x10000001 | ((immediate & 3) << 29) | ((immediate >> 2) << 5)
        struct.pack_into("<I", result, offset, instruction)
    return bytes(result)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    patched = patch(args.input.read_bytes())
    with args.output.open("xb") as output:
        output.write(patched)
    print(hashlib.sha256(patched).hexdigest(), args.output)


if __name__ == "__main__":
    main()
