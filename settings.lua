dofile("data/scripts/lib/mod_settings.lua")
local mod_id = "FLAT_EARTH"
local smoothing = dofile("mods/FLAT_EARTH/files/smoothing.lua")

local function smoothing_slider(id, gui, in_main_menu, im_id, setting)
    local key = mod_setting_get_id(id, setting)
    local value = smoothing.clamp(ModSettingGetNextValue(key))
    GuiIdPushString(gui, key)
    GuiText(gui, mod_setting_group_x_offset, 0, setting.ui_name .. string.format(": %.0f ms", value * 1000))
    mod_setting_tooltip(id, gui, in_main_menu, setting)
    GuiLayoutBeginHorizontal(gui, mod_setting_group_x_offset, 0, true)
    local less = GuiButton(gui, 1, 0, 0, "-10 ms")
    -- Logarithmic travel gives fast response times more room than a linear
    -- 0..2 s slider. Drag values snap to 10 ms; buttons reach every step.
    local previous_position = smoothing.to_slider(value)
    local position = GuiSlider(gui, 2, 0, 0, "", previous_position, 0, smoothing.slider_max,
        smoothing.to_slider(setting.value_default), 1, " ", 180)
    local more = GuiButton(gui, 3, 0, 0, "+10 ms")
    GuiLayoutEnd(gui)
    GuiIdPop(gui)
    local new_value = value
    -- GuiSlider returns float32: do not mistake round-off for a user edit and
    -- silently snap an older off-grid saved value just by opening the menu.
    if math.abs(position - previous_position) > 0.001 then
        new_value = smoothing.from_slider(position)
    end
    if less then new_value = smoothing.adjust(new_value, -1) end
    if more then new_value = smoothing.adjust(new_value, 1) end
    if math.abs(new_value - value) > 0.0000001 then
        ModSettingSetNextValue(key, new_value, false)
        mod_setting_handle_change_callback(id, gui, in_main_menu, setting, value, new_value)
    end
end
mod_settings_version = 13
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
    ui_description = "Counter-rotate the player and polymorphed forms visually by the camera angle. Creature turning and controls stay native; gravity and projectile velocity are unchanged.",
    scope = MOD_SETTING_SCOPE_RUNTIME
}, {
    id = "rotate_status_indicators",
    ui_name = "Rotate overhead status indicators",
    value_default = true,
    ui_description = "Safe-mod replacement for overhead stain and status icons. Keeps the native HUD and gameplay effects. Follows the upright-player setting; other creatures follow the world. Fully restart Noita after changing.",
    scope = MOD_SETTING_SCOPE_RUNTIME_RESTART
}, {
    id = "smoothing",
    ui_name = "Rotation smoothing",
    value_default = smoothing.default,
    value_min = smoothing.min,
    value_max = smoothing.max,
    ui_fn = smoothing_slider,
    ui_description = "0 to 2 seconds, adjustable in 10 ms steps. Lower values follow slopes faster; zero snaps to the measured slope. The slider gives faster settings more precision. Right-click the slider to reset to 200 ms.",
    scope = MOD_SETTING_SCOPE_RUNTIME
}, {
    id = "max_angle",
    ui_name = "Maximum tilt",
    value_default = 90,
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
    ui_description = "Keep mouse aiming aligned with the rotated world. Keyboard and mouse only. Buttons are relayed with one simulation frame of latency while a wand is held. Temporarily yields to native input during stun, confusion and action locks.",
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

