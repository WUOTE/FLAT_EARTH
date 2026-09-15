-- Startup-only routing of known world sprites into the post-processed world.
-- No EntityGetInRadius loop, runtime sprite polling, or entity transforms.
local M = {}

local function attribute(tag, name)
    return tag:match('%s' .. name .. '%s*=%s*"([^"]*)"')
        or tag:match("%s" .. name .. "%s*=%s*'([^']*)'")
end
local function yes(value) return value == "1" or value == "true" end

function M.patch(source)
    if type(source) ~= "string" or source == "" then return source, 0 end
    local count = 0
    local function tags(text)
        for _, component in ipairs({"SpriteComponent", "SpriteParticleEmitterComponent"}) do
            text = text:gsub("<" .. component .. "%f[%s/>][^>]*>", function(tag)
                if not yes(attribute(tag, "emissive")) then return tag end
                if component == "SpriteComponent" then
                    if yes(attribute(tag, "ui_is_parent")) or yes(attribute(tag, "is_text_sprite"))
                        or (attribute(tag, "_tags") or ""):find("aiming_reticle", 1, true) then return tag end
                end
                local changed, n = tag:gsub("(%s+emissive%s*=%s*[\"'])[^\"']+([\"'])", function(before, after)
                    return before .. "0" .. after
                end)
                -- This overlay used to bypass world depth sorting. Its body
                -- inherits z=-1 from base_enemy_basic; default eye z=1 ends up
                -- behind that body once routed into the same world pass.
                if component == "SpriteComponent"
                    and attribute(tag, "image_file") == "data/enemies_gfx/zombie_emissive.xml"
                    and attribute(tag, "z_index") == nil then
                    changed = changed:gsub("(%s*/?>)$", ' z_index="-1.01"%1', 1)
                end
                count = count + n
                return changed
            end)
        end
        return text
    end
    -- Preserve comments byte-for-byte and never treat commented examples as data.
    local parts, offset = {}, 1
    while true do
        local first = source:find("<!--", offset, true)
        if not first then parts[#parts+1] = tags(source:sub(offset)); break end
        parts[#parts+1] = tags(source:sub(offset, first-1))
        local last = source:find("-->", first+4, true)
        if not last then parts[#parts+1] = source:sub(first); break end
        parts[#parts+1] = source:sub(first, last+2)
        offset = last+3
    end
    return table.concat(parts), count
end

function M.prepare(read, paths)
    local files, count, missing = {}, 0, 0
    for _, path in ipairs(paths) do
        assert(path:match("^data/entities/.*%.xml$"), "unexpected world-sprite definition path")
        local original = read(path)
        if type(original) ~= "string" or not original:match("%S") then
            missing = missing + 1
        else
            local modified, changes = M.patch(original)
            if changes > 0 then files[path], count = modified, count + changes end
        end
    end
    return files, count, missing
end

return M
