#!/usr/bin/env python3
"""Optional OFFLINE probe of the installed game's sprite-scale behavior.

Usage: python native_sprite_scale.py /path/to/noita.exe
Requires the Python unicorn package. Reads the executable into an emulator;
never launches, attaches to, modifies or hooks a running game. Nothing in this
file is imported by the mod. No game code/assets are included in the repo.
"""
import hashlib
import struct
import sys
from pathlib import Path

from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_ECX, UC_X86_REG_ESP

EXPECTED = "808d2a0ab51ea0b46e9ad2aeb3327a4b0ce3feae04f32ba26326bf585b5779bd"
source = Path(sys.argv[1]).read_bytes()
if hashlib.sha256(source).hexdigest() != EXPECTED:
    raise SystemExit("Unrecognized game build: re-audit probe addresses before testing.")
pe = struct.unpack_from("<I", source, 60)[0]
base = struct.unpack_from("<I", source, pe + 52)[0]
sections = struct.unpack_from("<H", source, pe + 6)[0]
optional = struct.unpack_from("<H", source, pe + 20)[0]
u = Uc(UC_ARCH_X86, UC_MODE_32)
u.mem_map(base, 0x1000000)
for i in range(sections):
    _, rva, size, offset = struct.unpack_from("<4I", source, pe + 24 + optional + i * 40 + 8)
    if size:
        u.mem_write(base + rva, source[offset:offset + size])
u.mem_map(0x20000000, 0x10000)
stop, draw, sprite, vtable, out, stack = (0x20000000, 0x20000010, 0x20001000,
                                        0x20002000, 0x20003000, 0x2000f000)
u.mem_write(sprite, struct.pack("<I", vtable))
u.mem_write(vtable + 0x5c, struct.pack("<I", draw))
u.mem_write(sprite + 0x50, struct.pack("<2f", 12, 12))
u.mem_write(sprite + 0x95, b"\x01")
events = []

def observe(uc, address, size, _):
    if address in (stop, draw):
        events.append("draw" if address == draw else "return")
        uc.emu_stop()

u.hook_add(UC_HOOK_CODE, observe)

def call(address, *args):
    events.clear()
    u.mem_write(stack, struct.pack("<" + "I" * (len(args) + 1), stop, *args))
    u.reg_write(UC_X86_REG_ECX, sprite)
    u.reg_write(UC_X86_REG_ESP, stack)
    u.emu_start(address, 0, count=1000)
    assert events, "probe did not reach the expected draw/return"

# The loader writes XML scale_x/y to these transform fields. Native overhead
# copies retain them, and as::Sprite::Draw skips a zero-scale sprite.
u.mem_write(sprite + 0x78, struct.pack("<2f", 0, 0))
call(0x00dae600, 0, 0, 0)
assert events == ["return"], "zero-scale native icon was not suppressed"

# ImGui's size query is independent of XML scale: its HUD layout stays 12x12.
call(0x0044d9d0, out)
assert struct.unpack("<2f", u.mem_read(out, 8)) == (12, 12)

# The audited ImGui queue renderer (0x008279c0) explicitly supplies GUI scale
# before invoking this same drawing routine. Reproduce that override here.
u.mem_write(sprite + 0x78, struct.pack("<2f", 1, 1))
call(0x00dae600, 0, 0, 0)
assert events == ["draw"], "GUI's explicit scale did not restore rendering"
print("Native sprite probe passed: hidden overhead, unchanged HUD dimensions, GUI scale restores drawing")
