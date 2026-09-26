-- The native $log_recharging world message has a hard-coded size of 2.
-- REPORT_DAMAGE_SCALE does not affect it, so the coverage crop magnifies it.
-- Replace only this notice with a normally sized GUI label. Keep native wand
-- state, cooldowns, localization, other world messages and HUD fonts untouched.
local geometry = dofile_once("mods/FLAT_EARTH/files/camera_math.lua")
local guard = dofile_once("mods/FLAT_EARTH/files/input_guard.lua")
local M = {}
local key = "flat_earth_log_recharging"
local gui, owner, active_wand, last_attempt
local active = false

function M.prepare(read, scale)
    if scale == 1 then
        return {}
    end
    local path = "data/translations/common.csv"
    local source = read(path)
    if type(source) ~= "string" or source == "" then
        return nil, "recharge notice translations unavailable"
    end
    if source:find("\n" .. key .. ",", 1, true) then
        return {[path] = source}
    end
    local count
    source, count = source:gsub("(\r?\n)log_recharging,([^\r\n]*)", function(newline, translations)
        -- Retain the complete localized row under our own key. An empty native
        -- row suppresses only this world notice, not any other wand feedback.
        local _, columns = translations:gsub(",", "")
        return newline .. key .. "," .. translations .. newline .. "log_recharging," .. string.rep(",", columns)
    end)
    if count ~= 1 then
        return nil, "missing/ambiguous recharge notice translation"
    end
    return {[path] = source}
end

function M.configure(enabled)
    active = enabled
    M.clear()
end

function M.clear()
    owner, active_wand, last_attempt = nil, nil, nil
    if gui then
        GuiDestroy(gui)
        gui = nil
    end
end

function M.update(player, angle, scale)
    if not active then
        return
    end
    if not player or not EntityGetIsAlive(player) or GameIsInventoryOpen() or
        not EntityHasTag(player, "player_unit") or EntityHasTag(player, "polymorphed_player") then
        M.clear()
        return
    end
    if owner ~= player then
        M.clear()
        owner = player
    end
    local frame = GameGetFrameNum()
    local controls = EntityGetFirstComponent(player, "ControlsComponent")
    local inventory = EntityGetFirstComponent(player, "Inventory2Component")
    local wand = inventory and ComponentGetValue2(inventory, "mActiveItem")
    local ability = wand and wand ~= 0 and EntityGetIsAlive(wand) and
        EntityGetFirstComponentIncludingDisabled(wand, "AbilityComponent")
    if not ability or ComponentGetValue2(ability, "use_gun_script") ~= true or guard.reason(player, controls) then
        M.clear()
        return
    end
    if active_wand ~= wand then
        last_attempt = nil
        active_wand = wand
    end
    -- Do not carry a notice over an item switch/throw before the inventory has
    -- finished equipping the new wand.
    local actual_item = ComponentGetValue2(inventory, "mActualActiveItem")
    if (actual_item ~= nil and actual_item ~= wand) or
        (ComponentGetValue2(inventory, "mThrowItem") or 0) ~= 0 then
        M.clear()
        return
    end
    -- Read-only: match an attempted use while native reload is still pending.
    -- In particular, reloading by itself must not show a notice while idle.
    if ComponentGetValue2(controls, "mButtonDownFire") == true and
        ComponentGetValue2(ability, "never_reload") ~= true and
        (ComponentGetValue2(ability, "mReloadNextFrameUsable") or 0) > frame then
        last_attempt = frame
    end
    if not last_attempt or frame < last_attempt or frame - last_attempt >= 20 then
        M.clear()
        return
    end
    gui = gui or GuiCreate()
    GuiStartFrame(gui)
    local width, height = GuiGetScreenDimensions(gui)
    local _, _, world_width, world_height = GameGetCameraBounds()
    if not world_width or world_width <= 0 or not world_height or world_height <= 0 then
        M.clear()
        return
    end
    local px, py = EntityGetTransform(player)
    local cx, cy = GameGetCameraPos()
    local dx, dy = geometry.world_to_screen(px - cx, py - cy, angle, scale)
    local text = GameTextGetTranslatedOrNot("$" .. key)
    local text_width = GuiGetTextDimensions(gui, text)
    local age = frame - last_attempt
    GuiColorSetForNextWidget(gui, 1, 0.8, 0, math.min(1, (20 - age) / 8))
    GuiText(gui, width * (0.5 + dx / world_width) - text_width * 0.5,
        height * (0.5 + dy / world_height) - 23 - age * 0.15, text)
end

return M
