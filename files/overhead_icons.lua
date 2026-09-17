-- Replaces native overhead indicators using the restricted Lua/GUI API.
-- Stain/game-effect data is read-only; the ordinary HUD stays native.
local geometry = dofile_once("mods/FLAT_EARTH/files/camera_math.lua")
local images = dofile_once("mods/FLAT_EARTH/files/overhead_icon_assets.lua")
local M = {}
local assets, statuses, gui
local entities, child_icons, owned = {}, {}, {}
local last_scan, scan_x, scan_y
local tag = "flat_earth_overhead_icon_lease"

function M.install()
    dofile_once("data/scripts/lib/utilities.lua")
    dofile_once("data/scripts/status_effects/status_list.lua")
    assets, statuses = images.install(status_effects or {})
    ModLuaFileAppend("data/scripts/status_effects/status_list.lua", "mods/FLAT_EARTH/files/overhead_status_list.lua")
    -- Also cover a shared Lua context in which dofile_once has already cached
    -- the definitions. Our runtime metadata was copied before rewriting them.
    dofile("mods/FLAT_EARTH/files/overhead_status_list.lua")
end

local function restore(entry)
    if EntityGetIsAlive(entry.entity) and ComponentGetEntity(entry.lease) == entry.entity and
        ComponentGetValue2(entry.lease, "value_bool") == true then
        if entry.icon and ComponentGetEntity(entry.icon) == entry.entity and
            ComponentGetValue2(entry.icon, "icon_sprite_file") == ComponentGetValue2(entry.lease, "value_string") and
            ComponentGetValue2(entry.icon, "display_above_head") == false then
            ComponentSetValue2(entry.icon, "display_above_head", true)
        end
        ComponentSetValue2(entry.lease, "value_bool", false)
    end
end

local function recover_child(child)
    local lease = EntityGetFirstComponentIncludingDisabled(child, "VariableStorageComponent", tag)
    if lease then
        local icons = EntityGetComponentIncludingDisabled(child, "UIIconComponent") or {}
        local index = ComponentGetValue2(lease, "value_int") or 1
        restore({entity = child, icon = icons[index], lease = lease})
    end
    return lease
end

function M.recover(entity)
    if entity and EntityGetIsAlive(entity) then
        for _, child in ipairs(EntityGetAllChildren(entity) or {}) do recover_child(child) end
    end
end

function M.restore()
    for _, entry in ipairs(owned) do restore(entry) end
    owned = {}
end

function M.clear()
    M.restore()
    entities, child_icons = {}, {}
    last_scan, scan_x, scan_y = nil, nil, nil
    if gui then GuiDestroy(gui); gui = nil end
end

local function discover(player)
    local frame = GameGetFrameNum()
    local cx, cy = GameGetCameraPos()
    local _, _, width, height = GameGetCameraBounds()
    local radius = math.sqrt(width * width + height * height) * 0.5 + 64
    if not last_scan or frame < last_scan or frame - last_scan >= 10 or
        (cx - scan_x)^2 + (cy - scan_y)^2 > (radius * 0.25)^2 then
        entities = {}
        -- Wrappers apply to the global status list, so retain NPC indicators
        -- too. Discover infrequently; only visit cached status-bearing entities
        -- per frame, not every world sprite/particle.
        for _, entity in ipairs(EntityGetInRadius(cx, cy, radius) or {}) do
            if entity ~= player and EntityGetFirstComponent(entity, "StatusEffectDataComponent") then
                entities[#entities + 1] = entity
            end
        end
        last_scan, scan_x, scan_y = frame, cx, cy
    end
    local result = {}
    if player and EntityGetIsAlive(player) then result[1] = player end
    for _, entity in ipairs(entities) do
        if entity ~= player and EntityGetIsAlive(entity) then result[#result + 1] = entity end
    end
    return result
end

function M.prepare(player)
    M.restore()
    child_icons = {}
    M.recover(player)
    if not assets then return end
    entities = discover(player)
    for _, entity in ipairs(entities) do
        if EntityGetFirstComponent(entity, "StatusEffectDataComponent") then
            local row = {}
            -- Native above-head UIIcon lookup uses direct children, and the
            -- first enabled UIIconComponent on each child (not held-item trees).
            for _, child in ipairs(EntityGetAllChildren(entity) or {}) do
                local icon = EntityGetFirstComponent(child, "UIIconComponent")
                local lease = recover_child(child)
                if icon and ComponentGetValue2(icon, "display_above_head") == true then
                    local file = ComponentGetValue2(icon, "icon_sprite_file") or ""
                    if file ~= "" then
                        lease = lease or EntityAddComponent2(child, "VariableStorageComponent", {
                            _tags = tag, name = tag, value_bool = false, value_string = "", value_int = 0
                        })
                        for index, candidate in ipairs(EntityGetComponentIncludingDisabled(child, "UIIconComponent") or {}) do
                            if candidate == icon then ComponentSetValue2(lease, "value_int", index); break end
                        end
                        ComponentSetValue2(lease, "value_string", file)
                        ComponentSetValue2(lease, "value_bool", true)
                        owned[#owned + 1] = {entity = child, icon = icon, lease = lease}
                        row[#row + 1] = {entity = child, file = file}
                        ComponentSetValue2(icon, "display_above_head", false)
                    end
                end
            end
            child_icons[entity] = row
        end
    end
end

-- Pure layout used by the renderer and regression tests. A player's upright
-- pose rotates the WHOLE row about the character, not each image in place.
function M.position(x, y, left, top, pose_angle, camera_angle, view_scale, cx, cy, width, height, gui_width, gui_height)
    local ox, oy = geometry.rotate(left, top, pose_angle)
    local dx, dy = geometry.world_to_screen(x + ox - cx, y + oy - cy, camera_angle, view_scale)
    return gui_width * (0.5 + dx / width), gui_height * (0.5 + dy / height), pose_angle - camera_angle
end

function M.update(player, camera_angle, view_scale, upright)
    M.restore()
    if not assets then return end
    gui = gui or GuiCreate()
    GuiStartFrame(gui)
    GuiOptionsAdd(gui, GUI_OPTION.NonInteractive)
    GuiOptionsAdd(gui, GUI_OPTION.NoPositionTween)
    GuiOptionsAdd(gui, GUI_OPTION.Layout_NoLayouting)
    GuiOptionsAdd(gui, GUI_OPTION.DrawNoHoverAnimation)
    GuiOptionsAdd(gui, GUI_OPTION.NoPixelSnapY)
    local gw, gh = GuiGetScreenDimensions(gui)
    local cx, cy = GameGetCameraPos()
    local _, _, width, height = GameGetCameraBounds()
    if width <= 0 or height <= 0 then return end
    local sx, sy = gw / (width * view_scale), gh / (height * view_scale)
    local widget = 0
    for _, entity in ipairs(entities) do
        if EntityGetIsAlive(entity) then
            local data = EntityGetFirstComponent(entity, "StatusEffectDataComponent")
            if data then
                local amounts = ComponentGetValue2(data, "stain_effects") or {}
                local smoothed = ComponentGetValue2(data, "mStainEffectsSmoothedForUI") or amounts
                local row = {}
                for index, status in ipairs(statuses) do
                    -- Lua arrays are one-based; native element 0 is NONE.
                    if (amounts[index + 1] or 0) >= 0.15 and
                        (status.id ~= "INVISIBILITY" or EntityHasTag(entity, "player_unit")) then
                        local asset = assets[status.file]
                        row[#row + 1] = {asset = asset, amount = ((smoothed[index + 1] or 0) - 0.15) / 0.85}
                    end
                end
                for _, icon in ipairs(child_icons[entity] or {}) do
                    if EntityGetIsAlive(icon.entity) then row[#row + 1] = icon end
                end
                if #row > 0 then
                    local x, y = EntityGetTransform(entity)
                    local hitbox = EntityGetFirstComponent(entity, "HitboxComponent")
                    local top = -14 + (hitbox and ComponentGetValue2(hitbox, "aabb_min_y") or 0)
                    local pose = entity == player and upright and camera_angle or 0
                    local left = -(#row - 1) * 3 - 6
                    for _, icon in ipairs(row) do
                        local file = icon.asset and icon.asset.sprite or icon.file
                        if file then
                            local gx, gy, rotation = M.position(x, y, left, top, pose, camera_angle, view_scale,
                                cx, cy, width, height, gw, gh)
                            if gx > -64 * sx and gx < gw + 64 * sx and gy > -64 * sy and gy < gh + 64 * sy then
                                widget = widget + 1
                                local animation = icon.asset and ("fill_" .. images.dark_rows(icon.amount, icon.asset.height)) or ""
                                GuiImage(gui, widget, gx, gy, file, 1, sx, sy, rotation, GUI_RECT_ANIMATION_PLAYBACK.Loop, animation)
                            end
                        end
                        left = left + 6
                    end
                end
            end
        end
    end
end

return M
