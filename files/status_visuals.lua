-- World-space status symbols (hearts, confusion stars, berserk/protection
-- particles) are emitted separately from the stained body. Compensate their
-- spawn orientation and send emissive symbols through the rotated world.
-- Native overhead icons are handled separately by overhead_icons.lua.
-- This particle module leaves UIIconComponent flags and HUD shaders untouched.
local M = {}
local owned = {}
local prefix = "flat_earth_status_visual_"
local function close(a, b) return a and b and math.abs(a - b) < 0.00001 end

local function walk(player, root_offset, visit)
    local function children(parent, parent_offset, status_branch)
        for _, child in ipairs(EntityGetAllChildren(parent) or {}) do
            local status = status_branch or EntityGetFirstComponent(child, "GameEffectComponent") or
                EntityGetFirstComponent(child, "UIIconComponent")
            if status then
                local offset = 0
                local inherit = EntityGetFirstComponent(child, "InheritTransformComponent")
                if inherit and ComponentGetValue2(inherit, "rotate_based_on_x_scale") ~= true then
                    if ComponentGetValue2(inherit, "always_use_immediate_parent_rotation") == true then
                        offset = parent_offset
                    elseif ComponentGetValue2(inherit, "only_position") ~= true then
                        offset = ComponentGetValue2(inherit, "use_root_parent") == true and root_offset or parent_offset
                    end
                end
                visit(child, offset)
                children(child, offset, true)
            end
        end
    end
    children(player, root_offset, false)
end

local function marker(entity, index, create)
    local tag = prefix .. tostring(index)
    local component = EntityGetFirstComponentIncludingDisabled(entity, "VariableStorageComponent", tag)
    if not component and create then
        component = EntityAddComponent2(entity, "VariableStorageComponent", {
            _tags = tag, name = tag, value_bool = false, value_float = 0, value_int = 0, value_string = ""
        })
    end
    return component
end

local function restore(entity, emitter, lease)
    if not EntityGetIsAlive(entity) or not lease or ComponentGetEntity(lease) ~= entity or
        ComponentGetValue2(lease, "value_bool") ~= true then return end
    local written, file = (ComponentGetValue2(lease, "value_string") or ""):match("^([^|]+)|(.+)$")
    -- Serialized component ordering plus sprite identity permits recovery after
    -- a save/polymorph changes component IDs. Never restore onto a replaced FX.
    if emitter and ComponentGetEntity(emitter) == entity and
        ComponentGetValue2(emitter, "sprite_file") == file then
        if close(ComponentGetValue2(emitter, "rotation"), tonumber(written)) then
            ComponentSetValue2(emitter, "rotation", ComponentGetValue2(lease, "value_float"))
        end
        if ComponentGetValue2(lease, "value_int") == 1 and ComponentGetValue2(emitter, "emissive") == false then
            ComponentSetValue2(emitter, "emissive", true)
        end
    end
    ComponentSetValue2(lease, "value_bool", false)
end

function M.restore()
    for _, entry in ipairs(owned) do restore(entry.entity, entry.emitter, entry.lease) end
    owned = {}
end

function M.recover(player)
    walk(player, 0, function(entity)
        for index, emitter in ipairs(EntityGetComponentIncludingDisabled(entity, "SpriteParticleEmitterComponent") or {}) do
            restore(entity, emitter, marker(entity, index, false))
        end
    end)
end

function M.prepare(player, camera_angle, native_pose_offset, upright)
    M.restore()
    if not player or not EntityGetIsAlive(player) then return end
    M.recover(player)
    walk(player, native_pose_offset, function(entity, inherited_offset)
        for index, emitter in ipairs(EntityGetComponentIncludingDisabled(entity, "SpriteParticleEmitterComponent") or {}) do
            if ComponentGetIsEnabled(emitter) then
                local file = ComponentGetValue2(emitter, "sprite_file") or ""
                local old = ComponentGetValue2(emitter, "rotation") or 0
                local correction = 0
                local entity_file = ComponentGetValue2(emitter, "entity_file") or ""
                -- Velocity-aligned effects and spawned gameplay entities retain
                -- their native bearings. Only cosmetic symbol orientation changes.
                if upright and entity_file == "" and
                    ComponentGetValue2(emitter, "use_velocity_as_rotation") ~= true and
                    ComponentGetValue2(emitter, "use_rotation_from_velocity_component") ~= true then
                    correction = camera_angle
                    if ComponentGetValue2(emitter, "use_rotation_from_entity") == true then
                        correction = correction - inherited_offset -- no double compensation
                    end
                end
                local emissive = ComponentGetValue2(emitter, "emissive") == true
                if file ~= "" and (math.abs(correction) > 0.000001 or emissive) then
                    local lease = marker(entity, index, true)
                    ComponentSetValue2(lease, "value_float", old)
                    ComponentSetValue2(lease, "value_int", emissive and 1 or 0)
                    ComponentSetValue2(lease, "value_string", tostring(old + correction) .. "|" .. file)
                    ComponentSetValue2(lease, "value_bool", true)
                    owned[#owned + 1] = {entity = entity, emitter = emitter, lease = lease}
                    ComponentSetValue2(emitter, "rotation", old + correction)
                    if emissive then ComponentSetValue2(emitter, "emissive", false) end
                end
            end
        end
    end)
end

return M
