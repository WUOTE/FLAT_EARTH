dofile("data/scripts/lib/mod_settings.lua")
local mod_id = "FLAT_EARTH"
mod_settings_version = 9
mod_settings = {{
    id = "enabled",
    ui_name = "Rotate to match the ground",
    value_default = true,
    ui_description = "Player centering stays on when rotation is off.",
    scope = MOD_SETTING_SCOPE_RUNTIME
}, {
    id = "upright_player",
    ui_name = "Keep the player upright",
    value_default = true,
    ui_description = "Counter-rotate the normal player by the camera angle. Does not change gravity or projectile velocity. Animal polymorphs retain their normal orientation.",
    scope = MOD_SETTING_SCOPE_RUNTIME
}, {
    id = "smoothing",
    ui_name = "Rotation smoothing",
    value_default = 0.14,
    value_min = 0,
    value_max = 0.6,
    value_display_formatting = " $0 s",
    ui_description = "Lower values follow slopes faster. Zero snaps exactly to the measured slope.",
    scope = MOD_SETTING_SCOPE_RUNTIME
}, {
    id = "max_angle",
    ui_name = "Maximum tilt",
    value_default = 75,
    value_min = 15,
    value_max = 90,
    value_display_formatting = " $0 degrees",
    ui_description = "Limits rotation in either direction. Walking left never turns the view upside down.",
    scope = MOD_SETTING_SCOPE_RUNTIME
}, {
    id = "follow_airborne",
    ui_name = "Also follow airborne movement",
    value_default = false,
    ui_description = "Off: hold the ground angle during jumps and falls. On: also level the flight path.",
    scope = MOD_SETTING_SCOPE_RUNTIME
}, {
    id = "correct_aim",
    ui_name = "Compensate aiming",
    value_default = true,
    ui_description = "Keep mouse aiming aligned with the rotated world. Keyboard and mouse only. Buttons are relayed with one simulation frame of latency while a wand is held.",
    scope = MOD_SETTING_SCOPE_RUNTIME
}, {
    id = "extra_coverage",
    ui_name = "Render extra world to fill corners",
    value_default = true,
    ui_description = "Render extra off-screen world at a fixed visible scale. Requires a sufficiently large game backbuffer to retain sharpness and increases GPU load. Restart after changing. Off restores native buffers and uncovered corners.",
    scope = MOD_SETTING_SCOPE_RUNTIME_RESTART
}, {
    id = "route_world_sprites",
    ui_name = "Route world glow sprites through the world",
    value_default = true,
    ui_description = "Startup-only fix for known vanilla emissive sprites and sprite-particle emitters. Keeps additive blending and light components, but brightness can differ. No per-frame searches. Requires restart and a NEW RUN; saved entities may retain old flags.",
    scope = MOD_SETTING_SCOPE_RUNTIME_RESTART
}}

function ModSettingsUpdate(init_scope)
    ModSettingRemove(mod_id .. ".cast_diagnostics")
    mod_settings_update(mod_id, mod_settings, init_scope)
end
function ModSettingsGuiCount()
    return mod_settings_gui_count(mod_id, mod_settings)
end
function ModSettingsGui(gui, in_main_menu)
    mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end

