# FLAT EARTH

## Overhead stain/status indicators

**Rotate overhead status indicators** uses only Noita's safe mod API. Unrestricted
API access remains disabled; there are no runtime native hooks or DLLs.

- Native overhead stain icons are suppressed using zero-scale sprite XML
  wrappers. The native HUD supplies its own scale, so its icons, layout, fill,
  tooltips and timers remain native.
- Lua redraws overhead icons with the camera transform and stock fill shading.
  The player's row follows **Keep the player upright**. NPC rows rotate with the
  world. Gameplay stain amounts, effects and timers are never modified.
- Explicit `UIIconComponent` overhead flags are temporarily leased during native
  simulation and restored afterward, with serialized markers for recovery.
- Nearby status-bearing entities are discovered every 10 frames rather than
  scanning all world sprites every frame. Newly loaded NPC indicators can take
  up to 10 frames to appear. Unavailable/non-PNG stain icons remain native.

**Fully quit and restart Noita after updating or changing this setting.** Sprite
and status-definition caches cannot reliably be refreshed during a running game.
Disable the setting and restart to return to native overhead indicators.

### Verification

Run `python3 tests/run.py` (requires `liblua5.4`) for Lua syntax and mocked API
regressions: rotation/coverage, fill shading, HUD isolation, NPCs, recovery and
scan cadence. Production code remains Lua 5.1-compatible.

An optional **offline** native behavior probe is available with Python's
`unicorn` package:

```sh
python3 tests/native_sprite_scale.py /path/to/noita.exe
```

It reads a recognized executable into an emulator to check zero-scale suppression,
unscaled HUD dimensions and the GUI scale override. It does not run or modify
Noita, and is not loaded by the mod. This is not an in-game visual test.

In-game check: acquire wet/oiled/bloody stains, tilt both ways, toggle upright
player, inspect the normal HUD, then test a status-bearing polymorph and a nearby
stained enemy. Check a save/reload and inventory pause as well
