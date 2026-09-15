local geometry = dofile_once("mods/FLAT_EARTH/files/camera_math.lua")
local M = {}

local function set_vector(record, field, x, y, component, component_type)
    component = component or record.component
    component_type = component_type or "ControlsComponent"
    local old_x, old_y = ComponentGetValue2(component, field)
    if type(old_x) ~= "number" or type(old_y) ~= "number" then
        return
    end
    ComponentSetValue2(component, field, x, y)
    local written_x, written_y = ComponentGetValue2(component, field)
    record.fields[#record.fields + 1] = {
        field = field,
        component = component,
        component_type = component_type,
        old_x = old_x,
        old_y = old_y,
        written_x = written_x,
        written_y = written_y
    }
end

function M.restore(record)
    if not record or not EntityGetIsAlive(record.player) then
        return
    end
    for _, entry in ipairs(record.fields) do
        if EntityGetFirstComponent(record.player, entry.component_type) == entry.component then
            local x, y = ComponentGetValue2(entry.component, entry.field)
            -- Respect any newer native input/other mod update. Otherwise remove
            -- our last correction once, at the NEXT pre-update (not pre-render).
            if x == entry.written_x and y == entry.written_y then
                ComponentSetValue2(entry.component, entry.field, entry.old_x, entry.old_y)
            end
        end
    end
end

function M.origin(player)
    -- Match native controls and EZWand: mouse world position and the aim vector
    -- share the holder origin. A previous-frame muzzle is not a stable origin
    -- while the native hand/wand is turning during this update.
    local x, y = EntityGetTransform(player)
    return x, y
end
function M.apply(player, pivot_x, pivot_y, angle, view_scale, force_mouse, aim_frame_rotation, mouse_x, mouse_y,
    allow_disabled)
    if GameIsInventoryOpen() then
        return nil
    end
    local controls = EntityGetFirstComponent(player, "ControlsComponent")
    if not controls or (ComponentGetValue2(controls, "enabled") == false and not allow_disabled) then
        return nil
    end
    local ax, ay = ComponentGetValue2(controls, "mAimingVector")
    if type(ax) ~= "number" or type(ay) ~= "number" then
        return nil
    end
    local record = {
        player = player,
        component = controls,
        fields = {}
    }
    local platform = EntityGetFirstComponent(player, "PlatformShooterPlayerComponent")
    local gamepad = not force_mouse and platform and ComponentGetValue2(platform, "mHasGamepadControlsPrev") == true
    local new_ax, new_ay
    if gamepad then
        -- Stick strength is not a distance in the enlarged world render.
        new_ax, new_ay = geometry.rotate(ax, ay, angle)
        local gx, gy = ComponentGetValue2(controls, "mGamepadAimingVectorRaw")
        if type(gx) == "number" and type(gy) == "number" then
            gx, gy = geometry.rotate(gx, gy, angle)
            set_vector(record, "mGamepadAimingVectorRaw", gx, gy)
        end
    else
        local mx, my = mouse_x, mouse_y
        if mx == nil or my == nil then
            mx, my = ComponentGetValue2(controls, "mMousePosition")
        end
        if type(mx) ~= "number" or type(my) ~= "number" then
            return nil
        end
        local camera_x, camera_y = GameGetCameraPos()
        local dx, dy = geometry.screen_to_world(mx - camera_x, my - camera_y, angle, view_scale)
        local target_x, target_y = pivot_x + dx, pivot_y + dy
        local origin_x, origin_y = M.origin(player)
        -- Native holder-to-target direction; no previous-frame muzzle offset.
        new_ax, new_ay = target_x - origin_x, target_y - origin_y
        record.target_x, record.target_y = target_x, target_y
        record.origin_x, record.origin_y = origin_x, origin_y
        record.camera_angle = angle
        record.aim_frame_rotation = 0
        record.raw_mouse_x, record.raw_mouse_y = mx, my
        -- Native inputs are WORLD coordinates. The upright body is not an
        -- additional input-frame rotation; keep the actual cursor target.
        set_vector(record, "mMousePosition", target_x, target_y)
        -- Raw/RawPrev are UI pixels and must never be rotated or scaled.
    end
    set_vector(record, "mAimingVector", new_ax, new_ay)
    local length = math.sqrt(new_ax * new_ax + new_ay * new_ay)
    if length > 0.00001 then
        set_vector(record, "mAimingVectorNormalized", new_ax / length, new_ay / length)
        set_vector(record, "mAimingVectorNonZeroLatest", new_ax, new_ay)
    end
    if platform then
        -- Do not leave the player's cached aim pointing at the old horizon
        -- while controls/casting already point into the rotated world.
        set_vector(record, "mSmoothedAimingVector", new_ax, new_ay, platform, "PlatformShooterPlayerComponent")
    end
    return record
end

return M

