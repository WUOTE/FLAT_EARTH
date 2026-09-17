local mod_path = "mods/FLAT_EARTH/"
local geometry = dofile_once(mod_path .. "files/camera_math.lua")
local smoothing = dofile_once(mod_path .. "files/smoothing.lua")
local terrain = dofile_once(mod_path .. "files/terrain.lua")
local render_pipeline = dofile_once(mod_path .. "files/render_pipeline.lua")
local player_pose = dofile_once(mod_path .. "files/player_pose.lua")
local input = dofile_once(mod_path .. "files/late_aim.lua")
local status_visuals = dofile_once(mod_path .. "files/status_visuals.lua")
local overhead_icons = dofile_once(mod_path .. "files/overhead_icons.lua")
-- Native messages stay native. The overlay in files/recharge_text.lua is kept
-- for future custom UI, but this mod no longer loads or feeds messages to it.

local state = {
    ready = false,
    owns_camera = false,
    tracker = geometry.new_tracker(),
    view_scale = 1,
    setting_cache = {}
}

local function refresh_settings()
    state.setting_cache = {}
    state.options_cache = nil
end

local function setting(name, default)
    local value = state.setting_cache[name]
    if value == nil then
        value = ModSettingGet("FLAT_EARTH." .. name)
        if value == nil then
            value = default
        end
        state.setting_cache[name] = value
    end
    return value
end

local function publish_aim_mode()
    local mode = setting("correct_aim", true) ~= false and "1" or "0"
    if state.published_aim_mode ~= mode then
        GlobalsSetValue("FLAT_EARTH.aim_enabled", mode)
        state.published_aim_mode = mode
    end
end

local function options()
    if not state.options_cache then
        state.options_cache = {
            enabled = setting("enabled", true) == true,
            follow_airborne = setting("follow_airborne", false) == true,
            max_angle = geometry.clamp(tonumber(setting("max_angle", 90)) or 90, 15, 90) * math.pi / 180,
            smoothing = smoothing.clamp(setting("smoothing", smoothing.default)),
            locked = false
        }
    end
    return state.options_cache
end

local function controllable(entity)
    if not entity or entity == 0 or not EntityGetIsAlive(entity) then
        return false
    end
    local controls = EntityGetFirstComponent(entity, "ControlsComponent")
    return controls ~= nil and ComponentGetValue2(controls, "enabled") ~= false
end

local function find_player()
    -- noitamap also discovers both player_unit and polymorphed_player. Keep
    -- the fast path for an active form; invalidate it during a transformation.
    if controllable(state.player) and not input.transition_pending(state.player) and
        (EntityHasTag(state.player, "player_unit") or EntityHasTag(state.player, "polymorphed_player")) then
        return state.player
    end
    -- Prefer a living creature form before inspecting a parked normal player.
    -- Never force-enable the dormant original while a polymorph is active.
    for _, entity in ipairs(EntityGetWithTag("polymorphed_player") or {}) do
        if controllable(entity) then
            return entity
        end
    end
    for _, entity in ipairs(EntityGetWithTag("player_unit") or {}) do
        if EntityGetIsAlive(entity) and not EntityHasTag(entity, "polymorphed_player") then
            -- Recover the serialized input lease BEFORE filtering by enabled.
            -- This only releases a scope explicitly owned by FLAT EARTH.
            input.recover(entity)
            if controllable(entity) then
                return entity
            end
        end
    end
    return nil
end
local function publish(player, angle)
    publish_aim_mode()
    GlobalsSetValue("FLAT_EARTH.active_player", tostring(player))
    GlobalsSetValue("FLAT_EARTH.view_angle", tostring(angle))
    GlobalsSetValue("FLAT_EARTH.view_scale", tostring(state.view_scale))
    local x, y = EntityGetFirstHitboxCenter(player)
    if x == nil then
        x, y = EntityGetTransform(player)
    end
    GameSetCameraFree(true)
    GameSetCameraPos(x, y)
    GameSetPostFxParameter("FLAT_EARTH_rotation", math.cos(angle), math.sin(angle), state.view_scale, 1)
    state.owns_camera = true
end

local function release_camera()
    overhead_icons.clear()
    status_visuals.restore()
    input.release()
    GlobalsSetValue("FLAT_EARTH.active_player", "0")
    player_pose.restore()
    if state.owns_camera then
        GameSetCameraFree(false)
    end
    state.owns_camera = false
    state.player = nil
    state.tracker = geometry.new_tracker()
    GameSetPostFxParameter("FLAT_EARTH_rotation", 1, 0, 0, 0)
end

function OnModPostInit()
    if state.ready then
        return
    end
    refresh_settings()
    -- Remove a saved development option; it is not part of the shipping UI.
    ModSettingRemove("FLAT_EARTH.cast_diagnostics")
    local extra_coverage = setting("extra_coverage", true) == true
    state.view_scale = extra_coverage and (427 / 960) or 1
    local bounds_path = mod_path .. "files/render_bounds.xml"
    if extra_coverage then
        local bounds = ModTextFileGetContent(bounds_path)
        if type(bounds) ~= "string" or not bounds:find('VIRTUAL_RESOLUTION_X="960"', 1, true) or
            not bounds:find('VIRTUAL_RESOLUTION_Y="542"', 1, true) then
            state.error = "FLAT EARTH disabled: source-coverage XML is missing or incompatible"
            print(state.error)
            return
        end
    end
    local files, err = render_pipeline.prepare(ModTextFileGetContent, state.view_scale, extra_coverage and 2.25 or 1)
    if not files then
        state.error = "FLAT EARTH disabled: " .. tostring(err)
        print(state.error)
        return -- Never register larger bounds without the matching shader crop.
    end
    if setting("route_world_sprites", true) then
        local patch = dofile_once(mod_path .. "files/world_sprite_patch.lua")
        local paths = dofile_once(mod_path .. "files/world_sprite_paths.lua")
        local sprite_files, _, missing = patch.prepare(ModTextFileGetContent, paths)
        for path, content in pairs(sprite_files) do
            files[path] = content
        end
        if missing > 0 then
            print("FLAT EARTH: " .. missing .. " sprite definitions unavailable in this game version")
        end
    end
    for path, content in pairs(files) do
        ModTextFileSetContent(path, content)
    end
    if extra_coverage then
        ModMagicNumbersFileAdd(bounds_path)
    end
    if setting("rotate_status_indicators", true) then
        overhead_icons.install()
    end
    state.ready = true
end

function OnPlayerSpawned(player)
    refresh_settings()
    terrain.reset()
    if not state.ready then
        if state.error then
            GamePrint(state.error)
        end
        return
    end
    -- Release only a restored entity's serialized lease before rebinding.
    -- Never guess that unmarked, disabled controls belong to this mod.
    local active_creature = false
    if EntityHasTag(player, "player_unit") and not EntityHasTag(player, "polymorphed_player") then
        for _, entity in ipairs(EntityGetWithTag("polymorphed_player") or {}) do
            if controllable(entity) then
                active_creature = true;
                break
            end
        end
    end
    if active_creature then
        return
    end
    input.recover(player)
    status_visuals.restore()
    status_visuals.recover(player)
    overhead_icons.clear()
    overhead_icons.recover(player)
    state.player = player
    input.attach(player)
    local x, y = EntityGetTransform(player)
    geometry.reset_tracker(state.tracker, x, y, GameGetFrameNum())
    player_pose.apply(player, 0, setting("upright_player", true))
    publish(player, 0)
end

function OnWorldPreUpdate()
    if not state.ready then
        return
    end
    input.restore()
    publish_aim_mode()
    local player = find_player()
    if not player then
        release_camera();
        return
    end
    if player ~= state.player then
        OnPlayerSpawned(player)
    end
    local upright = setting("upright_player", true)
    local native_pose_offset = player_pose.prepare(player, state.tracker.angle, upright)
    status_visuals.prepare(player, state.tracker.angle, native_pose_offset, upright)
    overhead_icons.prepare(player)
    GameSetCameraFree(true)
    -- Prepare corrected input before native movement, hand/wand aiming and casting.
    input.prepare(player)
end

function OnWorldPostUpdate()
    if not state.ready then
        return
    end
    overhead_icons.restore()
    input.capture_input(state.player)
    input.restore()
    status_visuals.restore()
    publish_aim_mode()
    local player = find_player()
    if not player then
        release_camera();
        return
    end
    if player ~= state.player then
        OnPlayerSpawned(player)
    end
    local x, y = EntityGetTransform(player)
    local frame, opts = GameGetFrameNum(), options()
    local grounded, ground_angle = false, nil
    if opts.enabled then
        grounded, ground_angle = terrain.measure(player, frame)
    end
    local angle = geometry.update_tracker(state.tracker, x, y, frame, grounded, ground_angle, opts)
    player_pose.apply(player, angle, setting("upright_player", true))
    publish(player, angle)
    overhead_icons.update(player, angle, state.view_scale, setting("upright_player", true))
end

function OnPausedChanged(is_paused, is_inventory_pause)
    if not state.ready then
        return
    end
    refresh_settings()
    if is_paused then
        overhead_icons.clear()
        status_visuals.restore()
        input.restore();
        input.invalidate_input()
    end
    if is_paused and not is_inventory_pause then
        player_pose.restore()
    elseif not is_paused then
        local player = find_player()
        if player then
            player_pose.apply(player, state.tracker.angle, setting("upright_player", true))
        end
    end
end

function OnModSettingsChanged()
    overhead_icons.restore()
    status_visuals.restore()
    refresh_settings()
    terrain.reset()
    publish_aim_mode()
    if setting("correct_aim", true) == false then
        input.restore()
    end
end

