-- Counter-rotate the normal player, never gravity or creature polymorphs.
local M = {}
local owner, original_rotation, storage
local tag = "flat_earth_native_pose"

local function is_normal_player(player)
    return player and EntityGetIsAlive(player) and EntityHasTag(player, "player_unit") and
               not EntityHasTag(player, "polymorphed_player")
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

function M.restore_entity(player)
    if not is_normal_player(player) then
        return
    end
    local value = baseline(player, false)
    if value == nil and owner == player then
        value = original_rotation
    end
    if value == nil then
        return
    end
    local x, y, _, sx, sy = EntityGetTransform(player)
    EntitySetTransform(player, x, y, value, sx or 1, sy or 1)
end

function M.restore()
    if owner and EntityGetIsAlive(owner) then
        local x, y, _, sx, sy = EntityGetTransform(owner)
        EntitySetTransform(owner, x, y, original_rotation or 0, sx or 1, sy or 1)
    end
    owner, original_rotation, storage = nil, nil, nil
end

function M.apply(player, camera_angle, enabled)
    if not enabled or not is_normal_player(player) then
        M.restore();
        return
    end
    if owner ~= player then
        M.restore()
        original_rotation, storage = baseline(player, true)
        GlobalsSetValue("FLAT_EARTH.native_player_rotation_" .. tostring(player), tostring(original_rotation))
        owner = player
    end
    local x, y, _, sx, sy = EntityGetTransform(player)
    EntitySetTransform(player, x, y, original_rotation + camera_angle, sx or 1, sy or 1)
end

function M.rotation_offset(player)
    if owner ~= player or not EntityGetIsAlive(player) then
        return 0
    end
    local _, _, rotation = EntityGetTransform(player)
    return (rotation or 0) - (original_rotation or 0)
end

return M
