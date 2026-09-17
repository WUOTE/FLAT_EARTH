local original_dofile = dofile
local compile = loadstring or load
local files, bitmaps, calls, components, entities = {}, {}, {}, {}, {}
local next_component, next_image, scans, frame = 10, 10, 0, 0
local camera_x, camera_y, world_width, world_height = 100, 200, 960, 542
local gui_width, gui_height = 640, 360
local definition_source = {
    {id = "WET", ui_icon = "data/wet.png", effect_entity = "wet.xml"},
    {id = "OILED", ui_icon = "data/oiled.png", effect_entity = "oil.xml"},
    {id = "OILED", ui_icon = "data/oiled.png", min_threshold_normalized = 2},
    {id = "INVISIBILITY", ui_icon = "data/invisible.png"},
    {id = "MODDED", ui_icon = "mods/other/missing.png"},
}
local function copy(source)
    local result = {}
    for k, v in pairs(source) do result[k] = type(v) == "table" and copy(v) or v end
    return result
end
local function close(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
local function component(entity, kind, values)
    next_component = next_component + 1
    components[next_component] = {entity = entity, kind = kind, values = values, enabled = true}
    return next_component
end
function EntityGetIsAlive(id) return entities[id] and entities[id].alive ~= false end
function EntityGetFirstComponentIncludingDisabled(id, kind, tag)
    for key = 11, next_component do
        local c = components[key]
        if c and c.entity == id and c.kind == kind and (not tag or c.values._tags == tag) then return key end
    end
end
function EntityGetComponentIncludingDisabled(id, kind)
    local result = {}
    for key = 11, next_component do
        local c = components[key]
        if c and c.entity == id and c.kind == kind then result[#result + 1] = key end
    end
    return result
end
function EntityGetFirstComponent(id, kind)
    local c = EntityGetFirstComponentIncludingDisabled(id, kind)
    return c and components[c].enabled and c or nil
end
function EntityAddComponent2(id, kind, values) return component(id, kind, values) end
function ComponentGetEntity(id) return components[id] and components[id].entity or 0 end
function ComponentGetValue2(id, name) return components[id].values[name] end
function ComponentSetValue2(id, name, value)
    assert(components[id].kind ~= "StatusEffectDataComponent", "must never mutate stain data")
    assert(components[id].kind ~= "GameEffectComponent", "must never mutate effects")
    assert(name ~= "display_in_hud", "must never toggle the native HUD")
    components[id].values[name] = value
end
function EntityGetAllChildren(id) return entities[id].children or {} end
function EntityGetTransform(id) return entities[id].x, entities[id].y end
function EntityHasTag(id, tag) return tag == "player_unit" and id == 1 end
function EntityGetInRadius()
    scans = scans + 1
    return {1, 2, 3, 4}
end
function GameGetFrameNum() return frame end
function GameGetCameraPos() return camera_x, camera_y end
function GameGetCameraBounds() return 0, 0, world_width, world_height end
function GuiCreate() return 7 end
function GuiDestroy() calls = {} end
function GuiStartFrame() calls = {} end
function GuiGetScreenDimensions() return gui_width, gui_height end
function GuiOptionsAdd(_, option) assert(type(option) == "number") end
function GuiImage(...) calls[#calls + 1] = {...} end
function ModImageDoesExist(file) return bitmaps[file] ~= nil end
function ModImageMakeEditable(file, w, h)
    if not bitmaps[file] then
        next_image = next_image + 1
        local image = {id = next_image, w = w, h = h, pixels = {}}
        bitmaps[file], bitmaps[next_image] = image, image
    end
    local image = bitmaps[file]
    return image.id, image.w, image.h
end
function ModImageGetPixel(id, x, y) return bitmaps[id].pixels[y * bitmaps[id].w + x] or 0 end
function ModImageSetPixel(id, x, y, color) bitmaps[id].pixels[y * bitmaps[id].w + x] = color end
function ModTextFileSetContent(file, source) files[file] = source end
function ModLuaFileAppend(to, from) assert(to == "data/scripts/status_effects/status_list.lua"); files.append = from end
function dofile(path)
    if files[path] then return assert(compile(files[path]))() end
    return original_dofile((path:gsub("^mods/FLAT_EARTH/", "")))
end
function dofile_once(path)
    if path == "data/scripts/lib/utilities.lua" then
        GUI_OPTION = {NonInteractive = 2, NoPositionTween = 6, Layout_NoLayouting = 15,
            NoPixelSnapY = 19, DrawNoHoverAnimation = 21}
        GUI_RECT_ANIMATION_PLAYBACK = {Loop = 2}
        return
    end
    if path == "data/scripts/status_effects/status_list.lua" then status_effects = copy(definition_source); return end
    return dofile(path)
end
for _, file in ipairs({"data/wet.png", "data/oiled.png", "data/invisible.png"}) do
    local id = ModImageMakeEditable(file, 12, 12)
    for y = 0, 11 do for x = 0, 11 do ModImageSetPixel(id, x, y, 0xffa08060) end end
end
entities[1] = {x = camera_x, y = camera_y, children = {3, 4}}
entities[2] = {x = camera_x + 30, y = camera_y, children = {}}
entities[3] = {x = 0, y = 0}
entities[4] = {x = 0, y = 0}
local player_data = component(1, "StatusEffectDataComponent", {
    stain_effects = {0, 0.6, 0.8, 0.9, 0}, mStainEffectsSmoothedForUI = {0, 0.5, 0.7, 0.9, 0}
})
component(1, "HitboxComponent", {aabb_min_y = -10})
component(2, "StatusEffectDataComponent", {stain_effects = {0, 0.5, 0, 0.9, 0}})
local head_icon = component(3, "UIIconComponent", {
    icon_sprite_file = "data/curse.png", display_above_head = true, display_in_hud = true
})
local hud_only = component(4, "UIIconComponent", {
    icon_sprite_file = "data/perk.png", display_above_head = false, display_in_hud = true
})
local images = dofile("files/overhead_icon_assets.lua")
local head = dofile("files/overhead_icons.lua")
head.install()
assert(files.append == "mods/FLAT_EARTH/files/overhead_status_list.lua")
assert(#status_effects == #definition_source)
for i, status in ipairs(status_effects) do
    for key, value in pairs(definition_source[i]) do
        if key ~= "ui_icon" then assert(status[key] == value) end
    end
end
assert(status_effects[2].ui_icon == status_effects[3].ui_icon, "tiers share an icon, not extra status indices")
assert(status_effects[5].ui_icon == definition_source[5].ui_icon, "missing asset must remain native")
local wrapper = files[status_effects[1].ui_icon]
assert(wrapper:find('filename="data/wet.png"', 1, true))
assert(wrapper:find('scale_x="0" scale_y="0"', 1, true))
assert(not files["data/wet.png"], "original icon not replaced")
local manifest = dofile("mods/FLAT_EARTH/files/generated_status_icons/wrappers.lua")
assert(manifest["data/wet.png"] == status_effects[1].ui_icon)
-- Pixel shading retains alpha and reproduces native 0.55 RGB multiplication.
local sheet = bitmaps["mods/FLAT_EARTH/files/generated_status_icons/1.png"]
assert(ModImageGetPixel(sheet.id, 0, 0) == 0xffa08060)
assert(ModImageGetPixel(sheet.id, 0, 12) == 0xff584635)
for n = 0, 100 do
    local amount = n / 100
    local dark = 0
    for y = 0, 11 do if (y + 0.5) / 12 < 0.8 - 0.6 * math.max(0.1, amount) then dark = dark + 1 end end
    assert(images.dark_rows(amount, 12) == dark)
end
-- Safe lifecycle: only above-head flag leased during native simulation.
head.prepare(1)
assert(ComponentGetValue2(head_icon, "display_above_head") == false)
assert(ComponentGetValue2(head_icon, "display_in_hud") == true)
assert(ComponentGetValue2(hud_only, "display_above_head") == false)
head.update(1, math.pi / 4, 427 / 960, true)
assert(ComponentGetValue2(head_icon, "display_above_head") == true)
assert(#calls == 5, "three player stains + custom status + one NPC stain; no invisible NPC indicator")
for i = 1, 4 do close(calls[i][9], 0) end
close(calls[5][9], -math.pi / 4)
assert(calls[4][5] == "data/curse.png")
assert(calls[1][11]:match("^fill_%d+$"))
assert(ComponentGetValue2(player_data, "stain_effects")[2] == 0.6)
local first_scan = scans
frame = 1; head.prepare(1); head.restore()
assert(scans == first_scan, "no per-frame world scan")
frame = 10; head.prepare(1); head.restore()
assert(scans == first_scan + 1)
-- Restart/polymorph recovery: serialized marker, no reliance on component IDs.
head.prepare(1)
local resumed = dofile("files/overhead_icons.lua")
resumed.install()
resumed.prepare(1)
resumed.restore()
assert(ComponentGetValue2(head_icon, "display_above_head") == true)
-- Recovery also works when serialization disabled the leased component, and
-- even when the replacement setting is off (no assets installed).
head.prepare(1)
components[head_icon].enabled = false
local disabled = dofile("files/overhead_icons.lua")
disabled.prepare(1)
assert(ComponentGetValue2(head_icon, "display_above_head") == true)
components[head_icon].enabled = true
-- A replaced icon must not have an old lease restored onto it.
head.prepare(1)
components[head_icon].values.icon_sprite_file = "replacement.png"
head.restore()
assert(ComponentGetValue2(head_icon, "display_above_head") == false)
components[head_icon].values.icon_sprite_file = "data/curse.png"
components[head_icon].values.display_above_head = true
-- Clear/release does not leave a hidden icon or a stale custom overlay.
head.prepare(1); head.clear()
assert(ComponentGetValue2(head_icon, "display_above_head") == true)
assert(#calls == 0)
-- Layout: +/-90 degrees, zero tilt, upright on/off, both coverage modes.
for _, angle in ipairs({-math.pi / 2, -0.4, 0, 0.4, math.pi / 2}) do
    for _, coverage in ipairs({1, 427 / 960}) do
        local x, y, rotation = head.position(100, 200, -6, -24, angle, angle, coverage,
            100, 200, 960, 542, 640, 360)
        close(x, 320 - 6 * 640 / (960 * coverage))
        close(y, 180 - 24 * 360 / (542 * coverage))
        close(rotation, 0)
        x, y, rotation = head.position(100, 200, -6, -24, 0, angle, coverage,
            100, 200, 960, 542, 640, 360)
        close(rotation, -angle)
        local dx, dy = (x / 640 - 0.5) * 960 * coverage, (y / 360 - 0.5) * 542 * coverage
        close(dx * math.cos(angle) - dy * math.sin(angle), -6)
        close(dx * math.sin(angle) + dy * math.cos(angle), -24)
    end
end
print("Overhead icon tests passed: assets, fill, layout, HUD isolation, NPCs, leases and scan cadence")
