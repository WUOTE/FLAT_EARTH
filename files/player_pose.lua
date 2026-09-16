-- Counter-rotate the active player visually, never gravity or creature controls.
local M = {}
local owner, original_rotation, storage, owner_is_creature
local tag = "flat_earth_native_pose"
local creature_tag = "flat_earth_native_creature_pose"
local function close(a, b) return a and b and math.abs(a - b) < 0.00001 end

local function is_player(player)
    return player and EntityGetIsAlive(player) and
        (EntityHasTag(player, "player_unit") or EntityHasTag(player, "polymorphed_player"))
end

-- Keep the release's explicit rotation setter. Do not substitute the immediate
-- component-refresh path here, and never rebuild the body sprite: its native
-- animation and stain state must survive rotation, especially while throwing.
local function set_rotation(player, rotation)
    local x, y, _, sx, sy = EntityGetTransform(player)
    -- Reapply on every pose pass, just like the release, instead of relying on
    -- cached native render state when the entity's stored angle is unchanged.
    EntitySetTransform(player, x, y, rotation, sx or 1, sy or 1)
end

-- Serialized with the player: entity IDs change after polymorph, but this
-- native baseline must not become the previously counter-rotated body angle.
local function baseline(player, create)
    local component = EntityGetFirstComponentIncludingDisabled(player, "VariableStorageComponent", tag)
    if component then
        return ComponentGetValue2(component, "value_float"), component
    end
    if not create then
        return nil
    end
    local _, _, rotation = EntityGetTransform(player)
    local value = tonumber(GlobalsGetValue("FLAT_EARTH.native_player_rotation_" .. tostring(player), ""))
    if value == nil then
        value = rotation or 0
    end
    component = EntityAddComponent2(player, "VariableStorageComponent", {
        _tags = tag,
        name = tag,
        value_float = value
    })
    return value, component
end

local function creature_storage(player, create)
    local component = EntityGetFirstComponentIncludingDisabled(player, "VariableStorageComponent", creature_tag)
    if not component and create then
        component = EntityAddComponent2(player, "VariableStorageComponent", {
            _tags = creature_tag, name = creature_tag, value_bool = false,
            value_float = 0, value_string = ""
        })
    end
    return component
end

local function restore_creature(player)
    local component = creature_storage(player, false)
    if not component or ComponentGetValue2(component, "value_bool") ~= true then return end
    local _, _, current = EntityGetTransform(player)
    local written = tonumber(ComponentGetValue2(component, "value_string"))
    -- Do not overwrite a newer native/other-mod orientation. The marker also
    -- survives serialization, unlike a process-local entity/component ID.
    if close(current, written) then
        set_rotation(player, ComponentGetValue2(component, "value_float"))
    end
    ComponentSetValue2(component, "value_bool", false)
    ComponentSetValue2(component, "value_string", "")
end

function M.restore_entity(player)
    if not is_player(player) then return end
    if EntityHasTag(player, "polymorphed_player") then
        restore_creature(player)
        return
    end
    local value = baseline(player, false)
    if value == nil and owner == player then value = original_rotation end
    if value ~= nil then set_rotation(player, value) end
end

function M.restore()
    if owner and EntityGetIsAlive(owner) then
        if owner_is_creature then
            restore_creature(owner)
        else
            set_rotation(owner, original_rotation or 0)
        end
    end
    owner, original_rotation, storage, owner_is_creature = nil, nil, nil, nil
end

function M.apply(player, camera_angle, enabled)
    if not enabled or not is_player(player) then
        M.restore()
        return
    end
    local creature = EntityHasTag(player, "polymorphed_player")
    if owner ~= player or owner_is_creature ~= creature then
        M.restore()
        owner, owner_is_creature = player, creature
        if creature then
            restore_creature(player)
            storage = creature_storage(player, true)
        else
            original_rotation, storage = baseline(player, true)
            GlobalsSetValue("FLAT_EARTH.native_player_rotation_" .. tostring(player), tostring(original_rotation))
        end
    end
    if creature then
        local _, _, current = EntityGetTransform(player)
        original_rotation = current or 0
        if ComponentGetValue2(storage, "value_bool") == true and
            close(current, tonumber(ComponentGetValue2(storage, "value_string"))) then
            original_rotation = ComponentGetValue2(storage, "value_float")
        end
        -- Retain the creature's changing native pose, not a fixed upright zero.
        ComponentSetValue2(storage, "value_float", original_rotation)
        ComponentSetValue2(storage, "value_string", tostring(original_rotation + camera_angle))
        ComponentSetValue2(storage, "value_bool", true)
    end
    set_rotation(player, original_rotation + camera_angle)
end

-- Normal-player hand/wand aiming still needs its established pre-update pose.
-- A polymorph gets ONLY a post-update display pose, removed before simulation
-- so swimming, flying, AI controls and native turning see the original angle.
function M.prepare(player, camera_angle, enabled)
    if is_player(player) and EntityHasTag(player, "polymorphed_player") then
        if owner ~= player or not enabled then M.restore() end
        restore_creature(player)
        return 0
    end
    M.apply(player, camera_angle, enabled)
    return M.rotation_offset(player)
end

function M.rotation_offset(player)
    if owner ~= player or not EntityGetIsAlive(player) then return 0 end
    if owner_is_creature and ComponentGetValue2(storage, "value_bool") ~= true then return 0 end
    local _, _, rotation = EntityGetTransform(player)
    return (rotation or 0) - (original_rotation or 0)
end

return M
