# Settings, rendering, native input-lock and recharge regressions

Run from the mod directory with Python 3.10+ and `lupa` / `moderngl` installed:

```text
python tests/test_regressions.py
```
The runner also finds dependencies in the git-ignored `task/test-tools` directory.
It uses Lua 5.1, the installed Noita `data.wak` and loose data files, and a
standalone compatibility OpenGL context. It does not launch Noita or modify saves.
The game is found automatically when the mod is under `Noita/mods` or beside a
`Noita` directory. Otherwise set `NOITA_DIR` to the game installation directory.
For only the settings checks, run `python tests/test_regressions.py SettingsTests -v`.

## Automated coverage

- Settings load with all mod-local script imports unavailable, using the real
  vanilla settings library. All eight settings render in main-menu and in-game
  contexts. Saved values, 10 ms buttons, slider bounds/reset and float32
  round-off are covered.
- The real input relay, aim and input guard are exercised (not stubs): frozen,
  electrocuted, confused/dazed, delayed-input and native action locks do not
  forward movement buttons, rewrite aim, or force a cast. A healthy-player
  positive control verifies that the fixture actually reaches those writes.
- Status-only camera hold keeps the input target inactive, does not re-enable
  controls, and does not release/reacquire the camera every frozen frame.
  Death and unmarked disabled controls still release normally.
- Stale pre-stun input is discarded; freeze arriving during an owned input
  frame prevents takeover on the following frame.
- Invalid native position/ground-angle samples cannot poison the camera, and
  invalid rotation uniforms fall back to the unrotated world on the GPU.

- Stock high/low quality shaders, with and without the TRIPPY variant, compile.
- Vignettes stay in screen space at 0, 45 and 90 degrees, with native/expanded
  coverage and liquid/status distortion.
- The world-coverage mask cannot overwrite the later screen tint.
- Gamma input and blindness blending do not produce invalid/negative output.
- Native-coverage rendering without spatial distortion matches the stock shader.
- Startup actually installs and draws the recharge replacement; native coverage
  retains the native message. Startup failures do not commit partial changes.
- Localizations, GUI size/position, attempted-use detection, expiry, item changes,
  inventory, status locks, pause and player loss are checked with a read-only ECS
  fixture. No cooldown or input component is modified by the notice.

## Still required before publishing

These tests exercise real Lua lifecycle/input code against an ECS fixture and
real shaders with synthetic textures/uniforms, not an actual ice-skull attack.
The camera-hold/finite-value changes fix specific unsafe rendering paths; the
GIF alone does not establish that either path caused that captured blackout.
In-game confirmation is still required:

1. Fully quit Noita (shader V7 requires a fresh shader load). Enable the local
   FLAT_EARTH mod, not the unchanged subscribed Workshop copy.
2. Take hits from an ice skull on flat ground and a tilted slope. Check that the
   world remains visible during freezing, and that freezing still prevents
   movement/actions normally. Repeat with low health and in liquid.
3. Attempt to fire a slow-reloading wand: the localized recharge notice should
   be normally sized above the player. Check flat/tilted views, holding/releasing
   fire, wand switching, inventory, and at two display resolutions.
4. Restart with extra coverage disabled and verify native recharge text remains.

Local edits do not update Steam Workshop. Publish only after in-game validation.
`task` and `tests` are excluded in both upload manifests.

For the settings fix, also check the subscribed Workshop copy's mod settings in
the main menu and during a run, with no local `mods/FLAT_EARTH` copy installed.
The automated loader models that missing mod path; it does not run Steam's loader.

## Scope of this patch

The original `controllable()`/`find_player()` eligibility checks and the code in
`input_guard.lua` / `late_aim.lua` are unchanged. A failed player lookup can now
hold only the camera of the previous, living, explicitly incapacitated player;
that branch publishes `FLAT_EARTH.active_player = 0`, discards the input packet,
and never calls input preparation or reattaches the player. It does not clear
statuses, change damage, or substitute healthy controls.

The native overhead stain/status icon row is not changed by this patch. It is
separate from both the body stain UV map and the existing particle correction.
