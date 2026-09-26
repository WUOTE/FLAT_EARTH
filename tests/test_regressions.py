"""Regression tests using Lua 5.1 and the installed game's unmodified data.wak.
Run from the mod root: python tests/test_regressions.py
Dependencies: lupa, moderngl (GPU tests); local task/test-tools is also supported.
No game/save files are written and Noita does not need to be running.
"""
import math
import os
from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'task/test-tools'))
from lupa.lua51 import LuaRuntime
import moderngl

class Assets:
    def __init__(self):
        configured = os.environ.get('NOITA_DIR')
        candidates = [Path(configured)] if configured else [ROOT.parents[1], ROOT.parent / 'Noita']
        self.root = next((path for path in candidates if (path / 'data/data.wak').is_file()), None)
        if self.root is None:
            raise FileNotFoundError('Set NOITA_DIR to the Noita directory containing data/data.wak')
        self.path = self.root / 'data/data.wak'
        self.entries = {}
        with self.path.open('rb') as f:
            _, count, _, _ = struct.unpack('<4I', f.read(16))
            for _ in range(count):
                offset, size, length = struct.unpack('<3I', f.read(12))
                self.entries[f.read(length).decode()] = (offset, size)

    def read(self, name):
        if name.startswith('mods/FLAT_EARTH/'):
            return (ROOT / name.removeprefix('mods/FLAT_EARTH/')).read_text(encoding='utf-8-sig')
        loose = self.root / name
        if loose.is_file():
            return loose.read_text(encoding='utf-8-sig')
        offset, size = self.entries[name]
        with self.path.open('rb') as f:
            f.seek(offset)
            return f.read(size).decode('utf-8-sig')

ASSETS = Assets()
FRAGMENT = ASSETS.read('data/shaders/post_final.frag')
SCALE = 427 / 960

def runtime(overrides=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    modules = dict(overrides or {})
    def load(path):
        if path not in modules:
            modules[path] = lua.execute(ASSETS.read(path))
        return modules[path]
    lua.globals().dofile_once = load
    lua.globals().ModTextFileGetContent = ASSETS.read
    return lua, load, modules

class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((ROOT / 'tests/settings_fixture.lua').read_text())
        self.gui = self.lua.globals().settings_test
        self.loaded = []
        def builtin_only(path):
            self.assertTrue(path.startswith('data/'), 'Workshop settings cannot resolve ' + path)
            self.loaded.append(path)
            return self.lua.execute(ASSETS.read(path))
        self.lua.globals().dofile = builtin_only
        self.lua.globals().dofile_once = builtin_only
        self.lua.execute((ROOT / 'settings.lua').read_text())

    def draw(self, in_main_menu=True):
        self.lua.globals().ModSettingsGui(1, in_main_menu)

    def test_workshop_settings_register_and_render_without_mod_file_loading(self):
        api = self.lua.globals()
        api.ModSettingsUpdate(api.MOD_SETTING_SCOPE_NEW_GAME)
        self.assertEqual(api.ModSettingsGuiCount(), 8)
        self.assertEqual(self.gui.current['FLAT_EARTH.smoothing'], .2)
        for in_main_menu in (True, False):
            self.gui.labels = self.lua.table()
            self.draw(in_main_menu)
            labels = list(self.gui.labels.values())
            self.assertEqual(len(labels), 8)
            self.assertIn('Rotation smoothing: 200 ms', labels)
            self.assertTrue(any(label.startswith('Compensate aiming:') for label in labels))
        self.assertIn('data/scripts/lib/mod_settings.lua', self.loaded)

    def test_existing_values_survive_update_and_float32_slider_roundoff(self):
        api = self.lua.globals()
        self.gui.next['FLAT_EARTH.smoothing'] = .237
        self.gui.next['FLAT_EARTH.enabled'] = False
        self.gui.next['FLAT_EARTH.correct_aim'] = False
        api.ModSettingsUpdate(api.MOD_SETTING_SCOPE_RUNTIME)
        self.gui.edits = 0
        self.draw()
        self.assertAlmostEqual(self.gui.next['FLAT_EARTH.smoothing'], .237)
        self.assertFalse(self.gui.current['FLAT_EARTH.enabled'])
        self.assertFalse(self.gui.current['FLAT_EARTH.correct_aim'])
        self.assertEqual(self.gui.edits, 0)

    def test_smoothing_buttons_slider_endpoints_and_reset(self):
        api = self.lua.globals()
        api.ModSettingsUpdate(api.MOD_SETTING_SCOPE_NEW_GAME)
        for start, button, expected in [(0, '-10 ms', 0), (0, '+10 ms', .01),
                                        (.2, '-10 ms', .19), (1.99, '+10 ms', 2),
                                        (2, '+10 ms', 2)]:
            self.gui.next['FLAT_EARTH.smoothing'] = start
            self.gui.click = button
            self.draw()
            self.assertAlmostEqual(self.gui.next['FLAT_EARTH.smoothing'], expected)
        self.gui.click = None
        for position, expected in [(0, 0), (10000, 2)]:
            self.gui.slider = position
            self.draw()
            self.assertAlmostEqual(self.gui.next['FLAT_EARTH.smoothing'], expected)
        self.gui.slider = None
        self.gui.reset_slider = True
        self.draw()
        self.assertAlmostEqual(self.gui.next['FLAT_EARTH.smoothing'], .2)

class ShaderTests(unittest.TestCase):
    def setUp(self):
        self.lua, load, _ = runtime()
        self.patch = load('mods/FLAT_EARTH/files/shader_patch.lua')

    def test_build_real_shader_both_coverage_modes(self):
        for scale, world in [(1, 1), (SCALE, 2.25)]:
            result = self.patch.build(FRAGMENT, scale, world)
            self.assertIsInstance(result, str)
            self.assertEqual(result, self.patch.build(result, scale, world))
            self.assertNotIn('sc_uv_shift', result)
            self.assertIn('length(sc_screen_uv - vec2(0.5))', result)
            self.assertIn('length(sc_screen_uv - vec2(0.5,0.5))', result)
            self.assertLess(result.index('color = vec3(0.0);'), result.index('color = mix( color, vec3(1.0,0.0,0.0)'))
            self.assertLess(result.index('color = vec3(0.0);'), result.index('color.rgb = mix( color, overlay_color.rgb'))
            self.assertIn('pow( max(color, vec3(0.0)), gamma )', result)

    def test_incompatible_shaders_fail_without_partial_output(self):
        result, err = self.patch.build(FRAGMENT.replace('color = pow( color, gamma );', ''), SCALE, 2.25)
        self.assertIsNone(result)
        self.assertIn('missing shader anchor', err)
        result, err = self.patch.build('// FLAT_EARTH_FRAGMENT_V5\n' + FRAGMENT, SCALE, 2.25)
        self.assertIsNone(result)
        self.assertIn('fully restart', err)

    def test_all_lua_files_parse_as_lua51(self):
        compile_lua = self.lua.eval('function(s, name) local f, e = loadstring(s, name); assert(f, e) end')
        for path in [*ROOT.glob('*.lua'), *ROOT.joinpath('files').glob('*.lua')]:
            compile_lua(path.read_text(encoding='utf-8-sig'), str(path))

class RechargeTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.load, self.modules = runtime()
        self.lua.execute((ROOT / 'tests/recharge_fixture.lua').read_text(encoding='utf-8-sig'))
        self.fake = self.lua.globals().fake
        self.notice = self.load('mods/FLAT_EARTH/files/recharge_text.lua')
        self.notice.configure(True)

    def update(self, angle=0):
        self.notice.update(1, angle, SCALE)
        return self.fake.draws

    def test_preserves_localizations_and_suppresses_only_native_notice(self):
        original = ASSETS.read('data/translations/common.csv')
        patched = self.notice.prepare(ASSETS.read, SCALE)['data/translations/common.csv']
        old_rows = original.splitlines()
        original_row = next(row for row in old_rows if row.startswith('log_recharging,'))
        rows = patched.splitlines()
        self.assertIn(original_row.replace('log_recharging,', 'flat_earth_log_recharging,', 1), rows)
        native = next(row for row in rows if row.startswith('log_recharging,'))
        self.assertFalse(native.removeprefix('log_recharging,').strip(','))
        self.assertEqual([r for r in old_rows if not r.startswith('log_recharging,')],
                         [r for r in rows if not r.startswith(('log_recharging,', 'flat_earth_log_recharging,'))])
        self.assertEqual(patched, self.notice.prepare(lambda _: patched, SCALE)['data/translations/common.csv'])
        self.assertEqual(0, len(list(self.notice.prepare(ASSETS.read, 1).items())))

    def test_scaled_position_is_above_player_with_fixed_font_size(self):
        for angle in [0, math.pi / 4, math.pi / 2, -math.pi / 4]:
            self.fake.px, self.fake.py = 124, 211
            draw = self.update(angle)[1]
            dx, dy = self.fake.px - self.fake.cx, self.fake.py - self.fake.cy
            sx = (math.cos(angle) * dx + math.sin(angle) * dy) / SCALE
            sy = (-math.sin(angle) * dx + math.cos(angle) * dy) / SCALE
            self.assertAlmostEqual(draw.x, self.fake.gui_w * (0.5 + sx / self.fake.world_w) - 30)
            self.assertAlmostEqual(draw.y, self.fake.gui_h * (0.5 + sy / self.fake.world_h) - 23)
            self.assertEqual(draw.scale, 1)

    def test_reload_requires_attempt_and_notice_expires(self):
        self.fake.fields[11].mButtonDownFire = False
        self.assertEqual(len(self.update()), 0)
        self.fake.fields[11].mButtonDownFire = True
        self.assertEqual(len(self.update()), 1)
        self.fake.fields[11].mButtonDownFire = False
        self.fake.frame = 115
        self.assertEqual(len(self.update()), 1)
        self.assertGreater(self.fake.alpha, 0)
        self.fake.frame = 120
        self.assertEqual(len(self.update()), 0)

    def test_clears_on_status_inventory_death_switch_and_pause(self):
        cases = [
            'fake.effect = 1', 'fake.inventory_open = true', 'fake.alive = false',
            'fake.tags.polymorphed_player = true', 'fake.fields[11].enabled = false',
            'fake.fields[12].mActualActiveItem = 3', 'fake.fields[12].mThrowItem = 3',
            'fake.world_w = 0'
        ]
        for change in cases:
            self.setUp()
            self.assertEqual(len(self.update()), 1)
            self.lua.execute(change)
            self.assertEqual(len(self.update()), 0, change)
        self.setUp()
        self.update()
        self.fake.fields[12].mActiveItem = 3
        self.fake.fields[12].mActualActiveItem = 3
        self.fake.fields[11].mButtonDownFire = False
        self.assertEqual(len(self.update()), 0)
        self.notice.clear()
        self.assertEqual(len(self.fake.draws), 0)

    def startup(self):
        noop = self.lua.eval('function() end')
        def stub(**methods):
            return self.lua.table_from({key: noop for key in methods})
        self.modules['mods/FLAT_EARTH/files/player_pose.lua'] = stub(restore=1, apply=1, prepare=1)
        self.modules['mods/FLAT_EARTH/files/status_visuals.lua'] = stub(restore=1, recover=1, prepare=1)
        self.modules['mods/FLAT_EARTH/files/late_aim.lua'] = stub(recover=1, attach=1, capture_input=1, restore=1, release=1, prepare=1, transition_pending=1, invalidate_input=1)
        self.modules['mods/FLAT_EARTH/files/terrain.lua'] = stub(reset=1, measure=1)
        self.lua.execute((ROOT / 'init.lua').read_text())
        self.lua.globals().OnModPostInit()

    def test_freeze_and_stun_keep_camera_and_rotation_without_enabling_controls(self):
        # Real init/camera_math/shader; only external ECS systems
        # are stubbed. Previously enabled=false called release_camera here.
        for component_disabled in [False, True]:
            self.setUp()
            self.lua.execute("""
                fake.camera_releases = 0
                function GameSetCameraFree(free)
                    if not free then fake.camera_releases = fake.camera_releases + 1 end
                end
                function GameSetPostFxParameter(name, x, y, z, w)
                    fake.rotation = {x, y, z, w}
                end
            """)
            self.startup()
            self.lua.globals().OnPlayerSpawned(1)
            self.fake.fields[11].enabled = False
            self.fake.effect = 1
            if component_disabled:
                self.lua.execute("""
                    local original = EntityGetFirstComponent
                    function EntityGetFirstComponent(entity, kind)
                        if kind == 'ControlsComponent' then return nil end
                        return original(entity, kind)
                    end
                """)
            for frame in range(101, 151):
                self.fake.frame = frame
                self.lua.globals().OnWorldPreUpdate()
                self.lua.globals().OnWorldPostUpdate()
                self.assertEqual(self.fake.globals['FLAT_EARTH.active_player'], '0')
                self.assertEqual(self.fake.rotation[4], 1)
                self.assertFalse(self.fake.fields[11].enabled)
            self.assertEqual(self.fake.camera_releases, 0)

    def test_invalid_hitbox_falls_back_without_publishing_nan_camera(self):
        self.startup()
        self.lua.globals().OnPlayerSpawned(1)
        self.lua.execute('function EntityGetFirstHitboxCenter() return 0/0, math.huge end')
        self.lua.globals().OnWorldPostUpdate()
        self.assertEqual((self.fake.cx, self.fake.cy), (100, 200))
        # With both sources invalid, retain the last valid camera, not a NaN.
        self.fake.px = float('nan')
        self.fake.py = float('inf')
        self.fake.effect = 1
        self.lua.globals().OnWorldPostUpdate()
        self.assertEqual((self.fake.cx, self.fake.cy), (100, 200))
        self.assertTrue(math.isfinite(float(self.fake.globals['FLAT_EARTH.view_angle'])))

    def test_unmarked_disabled_controls_without_status_still_release_camera(self):
        self.startup()
        self.lua.globals().OnPlayerSpawned(1)
        self.fake.fields[11].enabled = False
        self.lua.globals().OnWorldPostUpdate()
        self.assertEqual(self.fake.globals['FLAT_EARTH.active_player'], '0')
        self.assertFalse(self.fake.fields[11].enabled)

    def test_death_still_releases_camera(self):
        self.startup()
        self.lua.globals().OnPlayerSpawned(1)
        self.fake.alive = False
        self.lua.globals().OnWorldPostUpdate()
        self.assertEqual(self.fake.globals['FLAT_EARTH.active_player'], '0')

    def test_real_init_installs_and_draws_replacement(self):
        self.startup()
        self.assertIn('flat_earth_log_recharging,', self.fake.writes['data/translations/common.csv'])
        self.assertIsNotNone(self.fake.bounds)
        self.lua.globals().OnPlayerSpawned(1)
        self.lua.globals().OnWorldPostUpdate()
        self.assertEqual(len(self.fake.draws), 1)
        self.lua.globals().OnPausedChanged(True, False)
        self.assertEqual(len(self.fake.draws), 0)

    def test_native_coverage_leaves_native_notice_alone(self):
        self.fake.extra_coverage = False
        self.startup()
        self.assertIsNone(self.fake.writes['data/translations/common.csv'])
        self.assertIsNone(self.fake.bounds)
        self.lua.globals().OnPlayerSpawned(1)
        self.lua.globals().OnWorldPostUpdate()
        self.assertEqual(len(self.fake.draws), 0)

    def test_translation_failure_does_not_commit_shaders_or_bounds(self):
        original = self.lua.globals().ModTextFileGetContent
        self.lua.globals().ModTextFileGetContent = lambda path: '' if path == 'data/translations/common.csv' else original(path)
        self.startup()
        self.assertEqual(len(list(self.fake.writes.items())), 0)
        self.assertIsNone(self.fake.bounds)

class InputLockTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.load, self.modules = runtime()
        self.lua.execute((ROOT / 'tests/input_fixture.lua').read_text())
        self.relay = self.lua.globals().relay
        noop = self.lua.eval('function() end')
        # Use the real input relay/guard/aim, stub only unrelated visual systems.
        self.modules['mods/FLAT_EARTH/files/player_pose.lua'] = self.lua.table_from(
            dict(restore=noop, restore_entity=noop, apply=noop, prepare=noop))
        self.modules['mods/FLAT_EARTH/files/status_visuals.lua'] = self.lua.table_from(
            dict(restore=noop, recover=noop, prepare=noop))
        self.input = self.load('mods/FLAT_EARTH/files/late_aim.lua')
        self.input.attach(1)
        self.relay.globals['FLAT_EARTH.active_player'] = '1'
        self.relay.globals['FLAT_EARTH.view_angle'] = '.5'
        self.relay.globals['FLAT_EARTH.view_scale'] = str(SCALE)
        self.lua.globals().relay_reset_writes()

    def gameplay_writes(self):
        return list(self.lua.globals().relay_gameplay_writes().values())

    def prime_fire_and_movement_packet(self):
        self.input.capture_input(1)
        self.relay.frame = 101
        self.lua.globals().relay_reset_writes()

    def test_healthy_relay_really_forwards_movement_and_forces_cast(self):
        self.prime_fire_and_movement_packet()
        record, reason = self.input.tick(1)
        self.assertIsNotNone(record)
        self.assertEqual(reason, 'pre-update aim ready')
        fields = self.relay.components[11].fields
        self.assertTrue(fields.mButtonDownFire)
        self.assertTrue(fields.mButtonDownRight)
        self.assertTrue(fields.mButtonDownFly)
        self.assertTrue(self.relay.components[13].fields.mForceFireOnNextUpdate)
        self.input.restore()
        self.assertTrue(fields.enabled)
        self.assertFalse(self.relay.components[13].fields.mForceFireOnNextUpdate)

    def test_statuses_do_not_write_buttons_controls_aim_or_force_cast(self):
        for effect in ['FROZEN', 'ELECTROCUTION', 'CONFUSION']:
            self.setUp()
            self.prime_fire_and_movement_packet()
            self.relay.effects[effect] = 1
            for frame in range(101, 111):
                self.relay.frame = frame
                result, reason = self.input.prepare(1)
                self.assertIsNone(result)
                self.assertEqual(reason, 'native effect: ' + effect)
                self.input.capture_input(1)
                self.input.restore()
            self.assertEqual(self.gameplay_writes(), [])
            self.assertFalse(self.relay.components[13].fields.mForceFireOnNextUpdate)

    def test_all_existing_native_locks_still_block_real_relay(self):
        for change in [
            'relay.components[11].fields.enabled = false',
            'relay.component_disabled = true',
            'relay.components[11].fields.input_latency_frames = 10',
            'relay.components[13].fields.mRequireTriggerPull = true',
            'relay.components[13].fields.mItemTemporarilyHidden = 10',
            'relay.components[13].fields.mCessationDo = true',
            "EntityAddComponent2(1, 'GameEffectComponent', {disable_movement=true, frames=20})",
            "relay.children={4}; EntityAddComponent2(4, 'GameEffectComponent', {disable_movement=true, frames=20})"
        ]:
            self.setUp()
            self.prime_fire_and_movement_packet()
            self.lua.execute(change)
            result, reason = self.input.prepare(1)
            self.assertIsNone(result, change)
            self.input.restore()
            self.assertEqual(self.gameplay_writes(), [], change)

    def test_pre_stun_packet_is_not_replayed_after_recovery(self):
        self.prime_fire_and_movement_packet()
        self.relay.effects.FROZEN = 1
        self.input.prepare(1)
        self.relay.effects.FROZEN = 0
        self.input.prepare(1)
        fields = self.relay.components[11].fields
        self.assertFalse(fields.mButtonDownFire)
        self.assertFalse(fields.mButtonDownRight)
        self.assertFalse(fields.mButtonDownFly)
        self.assertFalse(self.relay.components[13].fields.mForceFireOnNextUpdate)

    def test_freeze_arriving_during_owned_frame_cannot_force_next_cast(self):
        self.prime_fire_and_movement_packet()
        self.input.prepare(1)
        self.assertTrue(self.relay.components[13].fields.mForceFireOnNextUpdate)
        # Native update consumes the pending cast and applies a new freeze.
        # Release our old lease, then the unchanged guard must reject takeover.
        self.relay.components[13].fields.mForceFireOnNextUpdate = False
        self.relay.effects.FROZEN = 1
        self.input.capture_input(1)
        self.input.restore()
        self.relay.frame += 1
        self.lua.globals().relay_reset_writes()
        result, reason = self.input.prepare(1)
        self.assertIsNone(result)
        self.assertEqual(reason, 'native effect: FROZEN')
        self.assertEqual(self.gameplay_writes(), [])
        self.assertFalse(self.relay.components[13].fields.mForceFireOnNextUpdate)

    def test_real_init_camera_hold_never_calls_input_takeover(self):
        noop = self.lua.eval('function() end')
        self.modules['mods/FLAT_EARTH/files/terrain.lua'] = self.lua.table_from(dict(reset=noop, measure=noop))
        self.modules['mods/FLAT_EARTH/files/recharge_text.lua'] = self.lua.table_from(
            dict(clear=noop, configure=noop, update=noop, prepare=self.lua.eval('function() return {} end')))
        self.lua.execute((ROOT / 'init.lua').read_text())
        self.lua.globals().OnModPostInit()
        self.lua.globals().OnPlayerSpawned(1)
        self.relay.effects.FROZEN = 1
        self.relay.components[11].fields.enabled = False
        self.lua.globals().relay_reset_writes()
        for frame in range(101, 151):
            self.relay.frame = frame
            self.lua.globals().OnWorldPreUpdate()
            self.lua.globals().OnWorldPostUpdate()
        self.assertEqual(self.gameplay_writes(), [])
        self.assertEqual(self.relay.globals['FLAT_EARTH.active_player'], '0')
        self.assertEqual(self.relay.camera_releases, 0)
        self.assertTrue(self.relay.camera_free)
        self.assertEqual(self.relay.rotation[4], 1)
        self.assertFalse(self.relay.components[11].fields.enabled)
        self.assertFalse(self.relay.components[13].fields.mForceFireOnNextUpdate)
        self.relay.dead = True
        self.lua.globals().OnWorldPostUpdate()
        self.assertEqual(self.relay.camera_releases, 1)

class CameraMathTests(unittest.TestCase):
    def setUp(self):
        self.lua, load, _ = runtime()
        self.math = load('mods/FLAT_EARTH/files/camera_math.lua')

    def test_tracker_rejects_invalid_samples_and_recovers(self):
        opts = self.lua.table_from(dict(enabled=True, locked=False, follow_airborne=False,
                                        max_angle=math.pi/2, smoothing=0))
        tracker = self.math.new_tracker()
        self.math.update_tracker(tracker, 100, 200, 1, True, .5, opts)
        for bad in [float('nan'), float('inf'), -float('inf')]:
            self.assertEqual(self.math.update_tracker(tracker, bad, 200, 2, True, .5, opts), .5)
            self.assertTrue(math.isfinite(self.math.update_tracker(tracker, 100, 200, 2, True, bad, opts)))
        self.assertEqual(self.math.update_tracker(tracker, 101, 200, 3, True, -.3, opts), -.3)
        tracker.angle = float('nan')
        tracker.target = float('nan')
        self.assertTrue(math.isfinite(self.math.update_tracker(tracker, 101, 200, 4, True, .2, opts)))

VERTEX = '''#version 110
attribute vec2 in_position;
varying vec2 tex_coord_, tex_coord_y_inverted_, tex_coord_glow_, world_pos, tex_coord_skylight, tex_coord_fogofwar;
void main() {
    gl_Position = vec4(in_position, 0.0, 1.0);
    vec2 uv = in_position * 0.5 + 0.5;
    gl_TexCoord[0] = vec4(uv, uv.x, 1.0 - uv.y);
    tex_coord_ = uv; tex_coord_y_inverted_ = vec2(uv.x, 1.0 - uv.y);
    tex_coord_glow_ = tex_coord_y_inverted_;
    world_pos = vec2(0.0); tex_coord_skylight = vec2(0.5); tex_coord_fogofwar = vec2(0.5);
}'''

class GpuTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ctx = moderngl.create_standalone_context(require=210)
        _, load, _ = runtime()
        cls.patch = load('mods/FLAT_EARTH/files/shader_patch.lua')
        cls.vbo = cls.ctx.buffer(struct.pack('8f', -1,-1, 1,-1, -1,1, 1,1))
        cls.size = (96, 54)
        cls.target = cls.ctx.texture(cls.size, 4, dtype='f4')
        cls.fbo = cls.ctx.framebuffer([cls.target])

    @classmethod
    def tearDownClass(cls):
        cls.fbo.release(); cls.target.release(); cls.vbo.release(); cls.ctx.release()

    def render(self, scale=SCALE, angle=0, radial=False, source=None, textured_world=False, **uniforms):
        fragment = source or self.patch.build(FRAGMENT, scale, 1 if scale == 1 else 2.25)
        if radial:
            fragment = fragment.replace('//extra_define0', '#define TRIPPY')
            fragment = fragment.replace('gl_FragColor.rgb  = color;', 'gl_FragColor.rgb = vec3(edge_dist);')
        program = self.ctx.program(vertex_shader=VERTEX, fragment_shader=fragment)
        default = dict(window_size=self.size, world_viewport_size=(960,542), camera_inv_zoom_ratio=1.0,
                       color_grading=(1,1,1,0), brightness_contrast_gamma=(0,1,0.4545,0),
                       sky_light_color=(1,1,1,1), FLAT_EARTH_rotation=(math.cos(angle),math.sin(angle),scale,1))
        default.update(uniforms)
        for name, value in default.items():
            if name in program: program[name].value = value
        textures = []
        samples = dict(tex_bg=(0.6,0.6,0.6,1), tex_fg=(0.6,0.6,0.6,1), tex_lights=(1,1,1,0),
                       tex_skylight=(0,0,0,0), tex_noise=(0.5,0.5,0.5,0.5), tex_perlin_noise=(1,1,1,1),
                       tex_glow_unfiltered=(0,0,0,1 if radial else 0), tex_glow=(0,0,0,0), tex_fog=(0,0,0,0),
                       tex_debug=(0,0,0,0), tex_debug2=(0,0,0,0))
        for name, value in samples.items():
            if name not in program: continue
            if textured_world and name in ['tex_bg', 'tex_fg']:
                # A 1x1 source conceals broken UVs: even NaN/out-of-range samples
                # may return the same color. Use real spatial detail here.
                data = b''.join(struct.pack('4f', (x+.5)/16, (y+.5)/16,
                                            .2 if (x+y)%2 else .8, 1)
                                for y in range(16) for x in range(16))
                texture = self.ctx.texture((16,16), 4, data, dtype='f4')
                texture.repeat_x = texture.repeat_y = False
                texture.filter = (moderngl.NEAREST, moderngl.NEAREST)
            else:
                texture = self.ctx.texture((1,1), 4, struct.pack('4f', *value), dtype='f4')
            texture.use(len(textures)); program[name].value = len(textures); textures.append(texture)
        vao = self.ctx.simple_vertex_array(program, self.vbo, 'in_position')
        self.fbo.use(); self.ctx.viewport = (0,0,*self.size)
        vao.render(moderngl.TRIANGLE_STRIP)
        result = list(struct.iter_unpack('4f', self.fbo.read(components=4, dtype='f4')))
        vao.release(); program.release()
        for texture in textures: texture.release()
        return result

    def test_all_stock_quality_and_status_variants_compile(self):
        for scale in [1,SCALE]:
            for hiq in [True,False]:
                for trippy in [True,False]:
                    frag = self.patch.build(FRAGMENT, scale, 1 if scale == 1 else 2.25)
                    if not hiq: frag = frag.replace('#define HIQ','')
                    if trippy: frag = frag.replace('//extra_define0','#define TRIPPY')
                    program = self.ctx.program(vertex_shader=ASSETS.read('data/shaders/post_final.vert'), fragment_shader=frag)
                    program.release()

    def test_vignette_is_screen_space_under_rotation_refraction_and_distortion(self):
        width,height = self.size
        expected = [min(1,math.hypot((x+.5)/width-.5,(y+.5)/height-.5)*2)
                    for y in range(height) for x in range(width)]
        for scale in [1,SCALE]:
            for angle in [0,math.pi/4,math.pi/2]:
                pixels = self.render(scale,angle,radial=True,drugged_distortion_amount=1.0,time=1.0)
                self.assertLess(max(abs(p[0]-e) for p,e in zip(pixels,expected)), 0.00001)

    def test_coverage_mask_does_not_overwrite_screen_tint(self):
        pixels = self.render(scale=1, angle=math.pi/2, overlay_color=(0.2,0.45,1.0,0.3))
        # At 90 degrees these native-coverage corners have no world source, but
        # still must receive the late screen tint rather than be painted black.
        for index in [0,95,len(pixels)-96,len(pixels)-1]:
            for actual, expected in zip(pixels[index][:3], (0.06,0.135,0.3)):
                self.assertAlmostEqual(actual, expected, places=6)

    def test_status_tint_and_blindness_have_finite_output_and_visible_center(self):
        for scale in [1,SCALE]:
            for angle in [0,math.pi/4,math.pi/2]:
                for blindness in [0,0.1,0.7]:
                    pixels = self.render(scale,angle,overlay_color=(0.2,0.45,1.0,0.3),
                                         overlay_color_blindness=(0,0,0,blindness))
                    self.assertTrue(all(math.isfinite(c) and 0 <= c <= 1 for pixel in pixels for c in pixel))
                    self.assertGreater(pixels[27*96+48][2],0.1)

    def test_native_coverage_matches_vanilla_without_spatial_distortion(self):
        for tint in [(0,0,0,0), (0.2,0.45,1,0.3)]:
            stock = self.render(scale=1, source=FRAGMENT, overlay_color=tint)
            patched = self.render(scale=1, overlay_color=tint)
            self.assertLess(max(abs(a-b) for p,q in zip(stock,patched) for a,b in zip(p,q)), 0.00001)

    def test_invalid_rotation_uniform_cannot_black_out_world(self):
        for scale in [1, SCALE]:
            reference = self.render(scale=scale, textured_world=True)
            for xy in [(float('nan'), 0), (0, float('inf')), (0, 0), (10, 10)]:
                pixels = self.render(scale=scale, textured_world=True, FLAT_EARTH_rotation=(*xy, scale, 1))
                self.assertTrue(all(math.isfinite(c) for pixel in pixels for c in pixel))
                self.assertLess(max(abs(a-b) for p,q in zip(reference,pixels) for a,b in zip(p,q)), .00001)

    def test_negative_pre_gamma_color_does_not_produce_nan(self):
        pixels = self.render(brightness_contrast_gamma=(-2,1,0.4545,0),overlay_color=(0.2,0.45,1.0,0.3))
        self.assertTrue(all(math.isfinite(c) for pixel in pixels for c in pixel))
        self.assertGreater(pixels[27*96+48][2],0.29)

if __name__ == '__main__':
    unittest.main(verbosity=2)
