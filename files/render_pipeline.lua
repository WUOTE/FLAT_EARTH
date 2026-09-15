-- All source-resolution-dependent shader changes are prepared together, before
-- committing any of them or enabling the expanded world bounds.
local rotation = dofile_once("mods/FLAT_EARTH/files/shader_patch.lua")
local M = {}

local function substitute(source, pattern, replacement, label)
    if type(source) ~= "string" or not source:match("%S") then
        return nil, "empty " .. label
    end
    local count
    source, count = source:gsub(pattern, function()
        return replacement
    end)
    if count ~= 1 then
        return nil, "missing/ambiguous " .. label
    end
    return source
end

function M.prepare(read, view_scale, world_scale)
    local fragment_path = "data/shaders/post_final.frag"
    local fragment, err = rotation.build(read(fragment_path), view_scale, world_scale)
    if not fragment then
        return nil, err
    end
    local files = {
        [fragment_path] = fragment
    }
    if world_scale == 1 then
        return files
    end

    -- These stock offsets position the textures in WORLD units. Leaving the
    -- 55/90 offsets unscaled moves the cave's fog over the mountain after zoom.
    local vertex_path = "data/shaders/post_final.vert"
    local vertex = read(vertex_path)
    vertex, err = substitute(vertex, "const%s+float%s+SKY_Y_OFFSET%s*=%s*55%.0%s*;",
        string.format("const float SKY_Y_OFFSET = %.12f;", 55 * world_scale), "skylight origin")
    if not vertex then
        return nil, err
    end
    vertex, err = substitute(vertex, "float%s+FOG_Y_OFFSET%s*=%s*90%.0%s*%*%s*camera_inv_zoom_ratio%s*;",
        string.format("float FOG_Y_OFFSET = %.12f * camera_inv_zoom_ratio;", 90 * world_scale), "fog origin")
    if not vertex then
        return nil, err
    end
    files[vertex_path] = vertex

    -- Keep the native glow blur/decay passes: they already use the actual
    -- texture size. A coordinate-origin error is not a brightness/blur issue.
    return files
end

return M
