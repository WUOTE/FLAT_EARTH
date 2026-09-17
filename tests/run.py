#!/usr/bin/env python3
"""Run the Lua regression tests using liblua5.4; no game or unsafe mod API.

Noita uses LuaJIT/Lua 5.1. Tests and production code avoid 5.4-only syntax.
"""
import ctypes as C
import ctypes.util
import os
from pathlib import Path

os.chdir(Path(__file__).resolve().parents[1])
lib = ctypes.util.find_library("lua5.4")
if not lib:
    raise SystemExit("Install liblua5.4 to run these tests (or run the .lua test with Lua).")
lua = C.CDLL(lib)
lua.luaL_newstate.restype = C.c_void_p
lua.luaL_openlibs.argtypes = [C.c_void_p]
lua.luaL_loadbufferx.argtypes = [C.c_void_p, C.c_char_p, C.c_size_t, C.c_char_p, C.c_char_p]
lua.lua_pcallk.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_ssize_t, C.c_void_p]
lua.lua_tolstring.argtypes = [C.c_void_p, C.c_int, C.c_void_p]
lua.lua_tolstring.restype = C.c_char_p
lua.lua_settop.argtypes = [C.c_void_p, C.c_int]
lua.lua_close.argtypes = [C.c_void_p]
state = lua.luaL_newstate()
try:
    lua.luaL_openlibs(state)
    for path in [*Path(".").glob("*.lua"), *Path("files").glob("*.lua"), *Path("tests").glob("*.lua")]:
        text = path.read_bytes()
        if lua.luaL_loadbufferx(state, text, len(text), str(path).encode(), b"t"):
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
        lua.lua_settop(state, 0)
    text = Path("tests/overhead_icons.lua").read_bytes()
    if lua.luaL_loadbufferx(state, text, len(text), b"overhead_icons tests", b"t") or lua.lua_pcallk(state, 0, 0, 0, 0, None):
        raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
finally:
    lua.lua_close(state)
