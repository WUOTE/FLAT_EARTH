-- Prepare the real player's aim BEFORE native input and wand firing run.
-- An input-only receiver (the same ControlsComponent pattern used by vehicles)
-- keeps Noita's configured bindings available while automatic input is disabled
-- on the real player. No second shooter, camera spoofing, or projectile edits.
local aim = dofile_once("mods/FLAT_EARTH/files/aim.lua")
local pose = dofile_once("mods/FLAT_EARTH/files/player_pose.lua")
local M = {}
local prefix = "FLAT_EARTH.late_"
local receiver, receiver_controls, receiver_owner, packet
local last_error
local lease_tag = "flat_earth_input_lease"
local lease, lease_owner

local buttons = {"Fire", "Fire2", "Action", "Throw", "Interact", "Left", "Right", "Up", "Down", "Jump", "Run", "Fly",
                 "Dig", "ChangeItemR", "ChangeItemL", "Inventory", "HolsterItem", "DropItem", "Kick", "Eat",
                 "LeftClick", "RightClick"}
-- Levitation also consumes a WORLD-space target height, not just the fly key.
-- Omitting it left the real player targeting an old height (reported as Y=-90)
-- while native polling was disabled. Forward the receiver's fresh native value;
-- do not invent a ceiling, rotate gravity, or alter velocity/flight charge.
local scalar_fields, frame_fields = {"mFlyingTargetY"}, {}
for _, button in ipairs(buttons) do
    scalar_fields[#scalar_fields + 1] = "mButtonDown" .. button
    frame_fields[#frame_fields + 1] = "mButtonFrame" .. button
end
frame_fields[#frame_fields + 1] = "mButtonLastFrameFire"
scalar_fields[#scalar_fields + 1] = "mButtonCountChangeItemR"
scalar_fields[#scalar_fields + 1] = "mButtonCountChangeItemL"
for _, button in ipairs({"Fire", "Fire2", "Right", "Left", "Up", "Down", "Kick", "Throw", "Jump", "Fly"}) do
    scalar_fields[#scalar_fields + 1] = "mButtonDownDelayLine" .. button
end
local raw_vectors = {"mMousePositionRaw", "mMousePositionRawPrev", "mMouseDelta"}

local function normal_player(player)
    return player and EntityGetIsAlive(player) and EntityHasTag(player, "player_unit") and
               not EntityHasTag(player, "polymorphed_player")
end

local function lease_for(player, create)
    if lease_owner == player and lease then
        return lease
    end
    local component = EntityGetFirstComponentIncludingDisabled(player, "VariableStorageComponent", lease_tag)
    if not component and create then
        component = EntityAddComponent2(player, "VariableStorageComponent", {
            _tags = lease_tag,
            name = lease_tag,
            value_bool = false,
            value_int = 0,
            value_string = ""
        })
    end
    if component then
        lease, lease_owner = component, player
    end
    return component
end

-- Called only after the active player form has been identified. A serialized
-- marker follows a recreated entity; process-local IDs in Globals do not.
function M.recover(player)
    if not normal_player(player) then
        return false
    end
    local controls = EntityGetFirstComponent(player, "ControlsComponent")
    if not controls then
        return false
    end -- do not enable component-level dormancy
    local component = lease_for(player, false)
    if not component or ComponentGetValue2(component, "value_bool") ~= true then
        return false
    end
    ComponentSetValue2(controls, "enabled", true)
    local fire_before = ComponentGetValue2(component, "value_string")
    local platform = EntityGetFirstComponent(player, "PlatformShooterPlayerComponent")
    if platform and (fire_before == "0" or fire_before == "1") then
        if ComponentGetValue2(platform, "mForceFireOnNextUpdate") == true then
            ComponentSetValue2(platform, "mForceFireOnNextUpdate", fire_before == "1")
        end
    end
    ComponentSetValue2(component, "value_bool", false)
    ComponentSetValue2(component, "value_string", "")
    packet = nil
    return true
end

-- Migration for the reported saved player from BEFORE the serializable lease
-- existed. Only called on the first normal player spawn, never to discover NPCs
-- or override controls later disabled by some other system.
function M.recover_legacy_spawn(player)
    if not normal_player(player) then
        return false
    end
    if GlobalsGetValue("FLAT_EARTH.input_lifecycle_version", "") ~= "" then
        return false
    end
    GlobalsSetValue("FLAT_EARTH.input_lifecycle_version", "1")
    local controls = EntityGetFirstComponent(player, "ControlsComponent")
    if not controls or ComponentGetValue2(controls, "enabled") ~= false then
        return false
    end
    if lease_for(player, false) then
        return false
    end
    if not EntityGetFirstComponent(player, "PlatformShooterPlayerComponent") then
        return false
    end
    if (tonumber(GlobalsGetValue(prefix .. "frame", "-1")) or -1) < 0 then
        return false
    end
    if GlobalsGetValue("FLAT_EARTH.view_scale", "") == "" then
        return false
    end
    ComponentSetValue2(controls, "enabled", true)
    -- Old snapshots also retained the display-only body angle under a new ID.
    -- The legacy repair is restricted to the normal player, whose native
    -- orientation is zero unless we already have an explicit saved baseline.
    local value = tonumber(GlobalsGetValue("FLAT_EARTH.native_player_rotation_" .. tostring(player), "")) or 0
    GlobalsSetValue("FLAT_EARTH.native_player_rotation_" .. tostring(player), tostring(value))
    local x, y, _, sx, sy = EntityGetTransform(player)
    EntitySetTransform(player, x, y, value, sx or 1, sy or 1)
    packet = nil
    return true
end

function M.transition_pending(player)
    if tonumber(GlobalsGetValue("FLAT_EARTH.polymorph_source", "0")) ~= player then
        return false
    end
    local age = GameGetFrameNum() - (tonumber(GlobalsGetValue("FLAT_EARTH.polymorph_frame", "-100")) or -100)
    return age >= 0 and age <= 1
end

-- Event-only hook. Release BEFORE serialization where the native callback
-- permits it; the serialized lease above remains the fallback if it does not.
function M.before_polymorph(player)
    if not normal_player(player) then
        return
    end
    GlobalsSetValue("FLAT_EARTH.polymorph_source", tostring(player))
    GlobalsSetValue("FLAT_EARTH.polymorph_frame", tostring(GameGetFrameNum()))
    if tonumber(GlobalsGetValue(prefix .. "player", "0")) == player then
        M.restore()
    end
    M.recover(player)
    pose.restore_entity(player)
    packet = nil
end

function M.enabled()
    local session = GlobalsGetValue("FLAT_EARTH.aim_enabled", "")
    if session ~= "" then
        return session == "1"
    end
    return ModSettingGet("FLAT_EARTH.correct_aim") ~= false
end

function M.restore()
    local player = tonumber(GlobalsGetValue(prefix .. "player", "0"))
    if player == 0 then
        return
    end
    local controls = tonumber(GlobalsGetValue(prefix .. "controls", "0"))
    if controls ~= 0 and EntityGetIsAlive(player) and EntityGetFirstComponent(player, "ControlsComponent") == controls then
        ComponentSetValue2(controls, "enabled", true)
    end
    local platform = tonumber(GlobalsGetValue(prefix .. "platform", "0"))
    if platform ~= 0 and EntityGetIsAlive(player) and EntityGetFirstComponent(player, "PlatformShooterPlayerComponent") ==
        platform then
        if ComponentGetValue2(platform, "mForceFireOnNextUpdate") == true then
            ComponentSetValue2(platform, "mForceFireOnNextUpdate", GlobalsGetValue(prefix .. "force_before", "0") == "1")
        end
    end
    if EntityGetIsAlive(player) then
        local component = lease_for(player, false)
        if component then
            ComponentSetValue2(component, "value_bool", false)
            ComponentSetValue2(component, "value_string", "")
        end
    end
    GlobalsSetValue(prefix .. "platform", "0")
    GlobalsSetValue(prefix .. "player", "0")
    GlobalsSetValue(prefix .. "controls", "0")
end

function M.release()
    M.restore()
    if receiver and EntityGetIsAlive(receiver) then
        EntityKill(receiver)
    end
    receiver, receiver_controls, receiver_owner, packet = nil, nil, nil, nil
    last_error = nil
    lease, lease_owner = nil, nil
end

function M.invalidate_input()
    packet = nil
end

function M.attach(player)
    M.release()
    -- Remove only our obsolete development callbacks retained in old saves.
    -- Include disabled components so the scripts cannot come back on re-enable.
    for _, tag in ipairs({"flat_earth_aim_tick", "FLAT_EARTH_shot_probe"}) do
        local old = EntityGetFirstComponentIncludingDisabled(player, "LuaComponent", tag)
        while old do
            EntityRemoveComponent(player, old)
            old = EntityGetFirstComponentIncludingDisabled(player, "LuaComponent", tag)
        end
    end
    if not normal_player(player) then
        return
    end
    lease_for(player, true)
    local hook = EntityGetFirstComponentIncludingDisabled(player, "LuaComponent", "flat_earth_polymorph_guard")
    if not hook then
        EntityAddComponent2(player, "LuaComponent", {
            _tags = "flat_earth_polymorph_guard",
            script_polymorphing_to = "mods/FLAT_EARTH/files/polymorph_guard.lua",
            execute_every_n_frame = -1
        })
    end
    local x, y = EntityGetTransform(player)
    receiver = EntityLoad("mods/FLAT_EARTH/files/input_receiver.xml", x, y)
    if receiver == 0 then
        receiver = nil
    end
    receiver_controls = receiver and EntityGetFirstComponent(receiver, "ControlsComponent")
    receiver_owner = player
end

-- Read the receiver once AFTER native input. Timestamp rebasing below preserves
-- just-pressed/released events when this packet is consumed on the next update.
-- Buttons have one frame of relay latency; mouse AIM is sampled fresh in tick().
function M.capture_input(player)
    if not player or not EntityGetIsAlive(player) or player ~= receiver_owner or not receiver or
        not EntityGetIsAlive(receiver) or not receiver_controls then
        return
    end
    local frame = GameGetFrameNum()
    -- Ownership remains active until restore() in POST. The native frame count
    -- may advance between PRE and POST,
    -- so equality of frame numbers is not evidence that input was native.
    local manual = tonumber(GlobalsGetValue(prefix .. "player", "0")) == player
    local prepared_frame = tonumber(GlobalsGetValue(prefix .. "frame", tostring(frame))) or frame
    local native_advance = manual and math.max(0, math.min(1, frame - prepared_frame)) or 0
    local sample = {
        frame = frame,
        consumed = not manual,
        native_advance = native_advance,
        values = {},
        vectors = {}
    }
    for _, field in ipairs(scalar_fields) do
        sample.values[field] = ComponentGetValue2(receiver_controls, field)
    end
    for _, field in ipairs(frame_fields) do
        sample.values[field] = ComponentGetValue2(receiver_controls, field)
    end
    for _, field in ipairs(raw_vectors) do
        local x, y = ComponentGetValue2(receiver_controls, field)
        if type(x) == "number" and type(y) == "number" then
            sample.vectors[field] = {x, y}
        end
    end
    -- The receiver has no inventory consumer. Drain wheel counters here so an
    -- accumulated event cannot keep switching items on subsequent frames.
    for _, field in ipairs({"mButtonCountChangeItemR", "mButtonCountChangeItemL"}) do
        if (sample.values[field] or 0) ~= 0 then
            ComponentSetValue2(receiver_controls, field, 0)
        end
    end
    packet = sample
    local x, y = EntityGetTransform(player)
    EntitySetTransform(receiver, x, y)
end

local function forward_input(controls, frame)
    local age = packet and (frame - packet.frame) or -1
    if not packet or age < 0 or age > 1 then
        -- Prime safely after spawn/pause: never replay an old held-fire state.
        for _, button in ipairs(buttons) do
            ComponentSetValue2(controls, "mButtonDown" .. button, false)
        end
        ComponentSetValue2(controls, "mButtonCountChangeItemR", 0)
        ComponentSetValue2(controls, "mButtonCountChangeItemL", 0)
        return
    end
    for _, field in ipairs(scalar_fields) do
        local value = packet.values[field]
        if packet.consumed and (field == "mButtonCountChangeItemR" or field == "mButtonCountChangeItemL") then
            value = 0
        end
        if value ~= nil then
            ComponentSetValue2(controls, field, value)
        end
    end
    for _, field in ipairs(frame_fields) do
        local value = packet.values[field]
        if type(value) == "number" then
            -- Do not replay an edge already handled by native input (e.g.
            -- closing inventory or selecting a wand). Keep negative sentinels.
            -- Target the upcoming native frame, not just PRE's counter value.
            local shift = age + (packet.native_advance or 0)
            ComponentSetValue2(controls, field, not packet.consumed and value >= 0 and value + shift or value)
        end
    end
    for _, field in ipairs(raw_vectors) do
        local value = packet.vectors[field]
        if value then
            ComponentSetValue2(controls, field, value[1], value[2])
        end
    end
end

function M.tick(player)
    if not M.enabled() then
        return nil, "correction disabled"
    end
    if not normal_player(player) then
        return nil, "native creature controls"
    end
    if GameIsInventoryOpen() then
        return nil, "inventory open"
    end
    if tonumber(GlobalsGetValue("FLAT_EARTH.active_player", "0")) ~= player then
        return nil, "inactive player " .. tostring(player)
    end
    local controls = EntityGetFirstComponent(player, "ControlsComponent")
    if not controls then
        return nil, "no ControlsComponent"
    end
    if ComponentGetValue2(controls, "enabled") == false then
        return nil, "controls disabled"
    end
    local inventory = EntityGetFirstComponent(player, "Inventory2Component")
    if not inventory then
        return nil, "no Inventory2Component"
    end
    local wand = ComponentGetValue2(inventory, "mActiveItem")
    if not wand or wand == 0 then
        return nil, "no held item"
    end
    if not EntityGetIsAlive(wand) then
        return nil, "held item is gone"
    end
    -- Held wands in the supplied save have _enabled=0 on AbilityComponent.
    -- Native inventory/gun code still uses them: inspect metadata, not whether
    -- this component participates in its own automatic update system.
    local ability = EntityGetFirstComponentIncludingDisabled(wand, "AbilityComponent")
    if not ability then
        return nil, "no held AbilityComponent"
    end
    if ComponentGetValue2(ability, "use_gun_script") ~= true then
        return nil, "held item is not a wand"
    end
    if receiver_owner ~= player or not receiver or not EntityGetIsAlive(receiver) then
        M.attach(player)
    end
    if not receiver or not receiver_controls then
        return nil, "input receiver missing"
    end

    local frame = GameGetFrameNum()
    local angle = tonumber(GlobalsGetValue("FLAT_EARTH.view_angle", "0")) or 0
    local scale = tonumber(GlobalsGetValue("FLAT_EARTH.view_scale", "1")) or 1
    local cx, cy = GameGetCameraPos()
    -- EZMouse also uses this API for world coordinates. Do NOT substitute the
    -- GUI-scaled pixel coordinates or a previously corrected Controls vector.
    local mx, my = DEBUG_GetMouseWorld()
    forward_input(controls, frame)
    GlobalsSetValue(prefix .. "player", tostring(player))
    GlobalsSetValue(prefix .. "controls", tostring(controls))
    local owned = lease_for(player, true)
    if not owned then
        return nil, "input ownership marker unavailable"
    end
    ComponentSetValue2(owned, "value_int", controls)
    ComponentSetValue2(owned, "value_string", "")
    ComponentSetValue2(owned, "value_bool", true)
    ComponentSetValue2(controls, "enabled", false)
    local record = aim.apply(player, cx, cy, angle, scale, true, 0, mx, my, true)
    if not record then
        M.restore();
        return nil, "aim target unavailable"
    end
    GlobalsSetValue(prefix .. "frame", tostring(frame))
    if ComponentGetValue2(controls, "mButtonDownFire") == true then
        local platform = EntityGetFirstComponent(player, "PlatformShooterPlayerComponent")
        if platform then
            GlobalsSetValue(prefix .. "platform", tostring(platform))
            GlobalsSetValue(prefix .. "force_before",
                ComponentGetValue2(platform, "mForceFireOnNextUpdate") and "1" or "0")
            ComponentSetValue2(owned, "value_string",
                ComponentGetValue2(platform, "mForceFireOnNextUpdate") and "1" or "0")
            ComponentSetValue2(platform, "mForceFireOnNextUpdate", true)
        end
    end
    return record, "pre-update aim ready"
end

function M.prepare(player)
    local ok, result, reason = pcall(M.tick, player)
    if ok then
        last_error = nil
        return result, reason
    end
    M.restore()
    local message = tostring(result)
    -- Log actual failures once, without an on-screen debug overlay or per-frame spam.
    if last_error ~= message then
        print("FLAT EARTH input error: " .. message)
    end
    last_error = message
    return nil, "input error"
end

return M

