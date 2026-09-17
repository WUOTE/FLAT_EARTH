-- Safe-mod assets only. Native overhead ShadedSprites honor XML scale_x/y;
-- ImGui measures the unscaled bitmap and supplies its own scale when drawing.
-- A zero-scale wrapper suppresses the overhead copy, NOT its native HUD entry.
local M = {}
local directory = "mods/FLAT_EARTH/files/generated_status_icons/"

local function xml(value)
    return (value:gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function M.wrapper(file)
    return '<Sprite filename="' .. xml(file) .. '" scale_x="0" scale_y="0" />'
end

function M.dark_rows(amount, height)
    -- Stock imgui_status_icon.frag, evaluated at texel centers. Its top/bottom
    -- margins are 0.2/0.8 and the unfilled portion is multiplied by 0.55.
    amount = math.max(0.1, math.min(1, amount))
    return math.max(0, math.min(height, math.ceil(height * (0.8 - 0.6 * amount) - 0.5)))
end

local function dim(color)
    local r = color % 256
    local g = math.floor(color / 256) % 256
    local b = math.floor(color / 65536) % 256
    local a = math.floor(color / 16777216) % 256
    return math.floor(r * 0.55 + 0.5) + math.floor(g * 0.55 + 0.5) * 256 +
        math.floor(b * 0.55 + 0.5) * 65536 + a * 16777216
end

function M.install(definitions)
    local assets, statuses, seen = {}, {}, {}
    for _, definition in ipairs(definitions) do
        -- The native status vector starts with NONE (index 0). Repeated IDs
        -- are ingestion tiers, not additional stain-vector indices.
        if not seen[definition.id] then
            seen[definition.id] = true
            statuses[#statuses + 1] = {id = definition.id, file = definition.ui_icon}
        end
        local file = definition.ui_icon
        -- Unknown/non-bitmap assets stay native. Never suppress an icon for
        -- which we could not build a replacement.
        if type(file) == "string" and file:match("%.png$") and not assets[file] and ModImageDoesExist(file) then
            local source, width, height = ModImageMakeEditable(file, 0, 0)
            if source and source ~= 0 and width > 0 and height > 0 and width <= 64 and height <= 64 then
                -- Each distinct file needs a distinct name, including ingestion
                -- tiers of the same status with different images.
                local serial = 1
                for _ in pairs(assets) do serial = serial + 1 end
                local stem = directory .. tostring(serial)
                local sheet = stem .. ".png"
                local image = ModImageMakeEditable(sheet, width, height * (height + 1))
                if image and image ~= 0 then
                    local animations = {'<Sprite filename="' .. sheet .. '" default_animation="fill_0">'}
                    for rows = 0, height do
                        for y = 0, height - 1 do
                            for x = 0, width - 1 do
                                local color = ModImageGetPixel(source, x, y)
                                ModImageSetPixel(image, x, rows * height + y, y < rows and dim(color) or color)
                            end
                        end
                        animations[#animations + 1] = string.format(
                            '<RectAnimation name="fill_%d" pos_x="0" pos_y="%d" frame_count="1" frame_width="%d" frame_height="%d" frames_per_row="1" frame_wait="1" loop="1" />',
                            rows, rows * height, width, height)
                    end
                    animations[#animations + 1] = '</Sprite>'
                    local wrapper, sprite = stem .. "_native.xml", stem .. "_fill.xml"
                    ModTextFileSetContent(wrapper, M.wrapper(file))
                    ModTextFileSetContent(sprite, table.concat(animations, "\n"))
                    assets[file] = {wrapper = wrapper, sprite = sprite, height = height}
                end
            end
        end
    end
    local manifest = {"return {"}
    for file, asset in pairs(assets) do
        manifest[#manifest + 1] = string.format("[%q] = %q,", file, asset.wrapper)
    end
    manifest[#manifest + 1] = "}"
    ModTextFileSetContent(directory .. "wrappers.lua", table.concat(manifest, "\n"))
    return assets, statuses
end

return M
