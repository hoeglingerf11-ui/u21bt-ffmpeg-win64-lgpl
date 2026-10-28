#!/usr/bin/env python3
"""Dependency-free PE import-table inventory for FFmpeg runtime files."""
import hashlib
import json
import struct
import sys
from pathlib import Path


def cstr(data, offset):
    end = data.find(b"\0", offset)
    if end < 0:
        raise ValueError("unterminated PE string")
    return data[offset:end].decode("ascii", "strict")


def imports(path):
    data = path.read_bytes()
    if data[:2] != b"MZ":
        raise ValueError(f"not PE: {path}")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError(f"bad PE signature: {path}")
    machine = struct.unpack_from("<H", data, pe + 4)[0]
    sections_n = struct.unpack_from("<H", data, pe + 6)[0]
    opt_size = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    if magic == 0x20B:
        directory_offset = opt + 112
        image_base = struct.unpack_from("<Q", data, opt + 24)[0]
    elif magic == 0x10B:
        directory_offset = opt + 96
        image_base = struct.unpack_from("<I", data, opt + 28)[0]
    else:
        raise ValueError(f"unsupported PE optional header: {path}")
    import_rva, _ = struct.unpack_from("<II", data, directory_offset + 8)
    section_base = opt + opt_size
    sections = []
    for i in range(sections_n):
        off = section_base + 40 * i
        virtual_size, virtual_address, raw_size, raw_ptr = struct.unpack_from("<IIII", data, off + 8)
        sections.append((virtual_address, max(virtual_size, raw_size), raw_ptr))

    def file_offset(rva):
        for va, size, raw in sections:
            if va <= rva < va + size:
                return raw + rva - va
        raise ValueError(f"RVA outside sections: {rva:#x} in {path}")

    names = []
    if import_rva:
        off = file_offset(import_rva)
        for _ in range(4096):
            original, stamp, chain, name_rva, first = struct.unpack_from("<IIIII", data, off)
            if not any((original, stamp, chain, name_rva, first)):
                break
            names.append(cstr(data, file_offset(name_rva)).lower())
            off += 20
        else:
            raise ValueError(f"unterminated import directory: {path}")
    delay_rva, _ = struct.unpack_from("<II", data, directory_offset + 13 * 8)
    if delay_rva:
        off = file_offset(delay_rva)
        for _ in range(4096):
            descriptor = struct.unpack_from("<IIIIIIII", data, off)
            if not any(descriptor):
                break
            attrs, name_value = descriptor[0], descriptor[1]
            name_rva = name_value if attrs & 1 else name_value - image_base
            names.append(cstr(data, file_offset(name_rva)).lower())
            off += 32
        else:
            raise ValueError(f"unterminated delay-import directory: {path}")
    return machine, sorted(set(names))


root = Path(sys.argv[1])
rows = []
for path in sorted(root.iterdir()):
    if path.is_file() and path.suffix.lower() in (".exe", ".dll"):
        machine, names = imports(path)
        if machine != 0x8664:
            raise SystemExit(f"non-x64 PE in Windows x64 runtime: {path.name} (machine=0x{machine:04x})")
        rows.append({"file": path.name, "machine": "AMD64", "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "imports": names})
if not any(row["file"].lower() == "ffmpeg.exe" for row in rows):
    raise SystemExit("ffmpeg.exe missing from runtime output")
print(json.dumps({"schema": "u21bt-pe-imports-v1", "files": rows}, indent=2))
