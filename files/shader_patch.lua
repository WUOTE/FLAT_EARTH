-- Fragment-only rotation. Keep Noita's vertex shader, samplers, lighting
-- equations and texture filters unchanged. Optional extra SOURCE coverage
-- is cropped at a fixed scale, so camera tilt never changes visible zoom.
-- Embedded in Lua: no unsupported .glsl asset for Noita's VFS to silently omit.
local M = {}
local marker = "// FLAT_EARTH_FRAGMENT_V5"

local declarations = [[
// FLAT_EARTH_FRAGMENT_V5
uniform vec4 FLAT_EARTH_rotation;

// Each source varying can use a DIFFERENT texture rectangle/scale. Its screen
// derivatives give the correct affine mapping; adding one UV offset to all
// textures is not safe (in particular for glow, skylight and fog).
vec2 sc_remap(vec2 value, vec2 pixel_offset) {
    return value + dFdx(value) * pixel_offset.x + dFdy(value) * pixel_offset.y;
}
]]

local transform = [[
    vec2 sc_screen_uv = tex_coord_;
    vec2 sc_uv_per_pixel = vec2(dFdx(tex_coord_.x), dFdy(tex_coord_.y));
    vec2 sc_pixel = (tex_coord_ - vec2(0.5)) / sc_uv_per_pixel;
    float sc_c = 1.0;
    float sc_s = 0.0;
    if (FLAT_EARTH_rotation.w > 0.5) {
        sc_c = FLAT_EARTH_rotation.x;
        sc_s = FLAT_EARTH_rotation.y;
    }
    // GLSL screen Y points UP; the Noita slope angle uses Y DOWN.
    // Inverse map the displayed pixel to the original, unrotated image.
    vec2 sc_rotated_pixel = vec2(sc_c * sc_pixel.x + sc_s * sc_pixel.y,
                                -sc_s * sc_pixel.x + sc_c * sc_pixel.y) * SC_RENDER_SCALE;
    vec2 sc_pixel_offset = sc_rotated_pixel - sc_pixel;
    vec2 sc_tex_coord = sc_remap(tex_coord_, sc_pixel_offset);
    vec2 sc_tex_coord_y_inverted = sc_remap(tex_coord_y_inverted_, sc_pixel_offset);
    vec2 sc_tex_coord_glow = sc_remap(tex_coord_glow_, sc_pixel_offset);
    // The glow render's pixel-border origin changes with the world footprint.
    // Correct its source-space origin before the stock glow/refraction reads.
    sc_tex_coord_glow -= vec2(SC_WORLD_SCALE - 1.0) / world_viewport_size;
    vec2 sc_world_pos = sc_remap(world_pos, sc_pixel_offset);
    vec2 sc_tex_coord_skylight = sc_remap(tex_coord_skylight, sc_pixel_offset);
    vec2 sc_tex_coord_fogofwar = sc_remap(tex_coord_fogofwar, sc_pixel_offset);
    vec2 sc_uv_shift = sc_tex_coord - sc_screen_uv;
]]

local function replace_once(source, needle, replacement)
    local first, last = source:find(needle, 1, true)
    if not first then
        return nil, "missing shader anchor: " .. needle
    end
    if source:find(needle, last + 1, true) then
        return nil, "ambiguous shader anchor: " .. needle
    end
    return source:sub(1, first - 1) .. replacement .. source:sub(last + 1)
end

local function replace_pattern(source, pattern, replacement, label)
    local count
    source, count = source:gsub(pattern, function()
        return replacement
    end)
    if count ~= 1 then
        return nil, "missing/ambiguous shader constant: " .. label
    end
    return source
end

function M.build(fragment, render_scale, world_scale)
    render_scale = tonumber(render_scale or 1)
    if not render_scale or not (render_scale > 0 and render_scale <= 1) then
        return nil, "invalid source-coverage scale"
    end
    world_scale = tonumber(world_scale or (render_scale == 1 and 1 or 1 / render_scale))
    if not world_scale or not (world_scale >= 1) then
        return nil, "invalid world-coverage scale"
    end
    local scale_declaration = string.format(
        "const float SC_RENDER_SCALE = %.12f;\nconst float SC_WORLD_SCALE = %.12f;\n", render_scale, world_scale)
    if type(fragment) ~= "string" or not fragment:match("%S") then
        return nil, "the game returned an empty or unreadable final fragment shader"
    end
    if fragment:find(marker, 1, true) then
        if fragment:find(scale_declaration, 1, true) then
            return fragment
        end
        return nil, "coverage changed while shader was loaded; fully restart Noita"
    end
    if fragment:find("// FLAT_EARTH_BEGIN", 1, true) or fragment:find("// FLAT_EARTH_FRAGMENT_V2", 1, true) or
        fragment:find("// FLAT_EARTH_FRAGMENT_V3", 1, true) or fragment:find("// FLAT_EARTH_FRAGMENT_V4", 1, true) then
        return nil, "old shader still loaded; fully restart Noita after updating the mod"
    end
    local first, last = fragment:find("void%s+main%s*%(%s*%)%s*{")
    if not first then
        return nil, "missing final shader main()"
    end
    if fragment:find("void%s+main%s*%(", last + 1) then
        return nil, "multiple shader main() functions"
    end
    local prefix, body = fragment:sub(1, first - 1), fragment:sub(last + 1)
    local err
    -- Liquid refraction is defined in texture UV units. On the larger source
    -- buffer that wobble becomes SC_WORLD_SCALE times bigger on screen and the
    -- wave that much longer, pulling samples across the liquid edge into the
    -- surrounding terrain. Keep the vanilla amplitude/wavelength in pixels.
    body, err = replace_pattern(body, "DISTORTION_SCALE_MULT%s*=%s*50%.0%s*;",
        "DISTORTION_SCALE_MULT = 50.0 * SC_WORLD_SCALE;", "DISTORTION_SCALE_MULT")
    if not body then
        return nil, err
    end
    body, err = replace_pattern(body, "DISTORTION_SCALE_MULT2%s*=%s*0%.002%s*;",
        "DISTORTION_SCALE_MULT2 = 0.002 * SC_RENDER_SCALE;", "DISTORTION_SCALE_MULT2")
    if not body then
        return nil, err
    end
    local replacements = { -- Dithering and damage/health vignettes stay in screen space. At zero
    -- rotation and native coverage sc_uv_shift is zero (stock image).
    {"tex_coord * noise_scale + noise_time", "sc_screen_uv * noise_scale + noise_time"},
    {"length(tex_coord - vec2(0.5))", "length((tex_coord - sc_uv_shift) - vec2(0.5))"},
    {"float a = length(tex_coord - vec2(0.5,0.5));", "float a = length((tex_coord - sc_uv_shift) - vec2(0.5,0.5));"},
    {"vec2( gl_TexCoord[0].x, - gl_TexCoord[0].y )", "vec2(sc_tex_coord.x, -sc_tex_coord.y)"},
    {"vec2 tex_coord_debug = gl_TexCoord[0].xy;", "vec2 tex_coord_debug = sc_tex_coord;"}}
    for _, replacement in ipairs(replacements) do
        body, err = replace_once(body, replacement[1], replacement[2])
        if not body then
            return nil, err
        end
    end
    for from, to in pairs({
        tex_coord_ = "sc_tex_coord",
        tex_coord_y_inverted_ = "sc_tex_coord_y_inverted",
        tex_coord_glow_ = "sc_tex_coord_glow",
        world_pos = "sc_world_pos",
        tex_coord_skylight = "sc_tex_coord_skylight",
        tex_coord_fogofwar = "sc_tex_coord_fogofwar"
    }) do
        if not prefix:find("varying%s+vec2%s+" .. from .. "%s*;") then
            return nil, "missing stock varying: " .. from
        end
        body = body:gsub("%f[%w_]" .. from .. "%f[^%w_]", to)
    end
    local output = "gl_FragColor.rgb  = color;"
    body, err = replace_once(body, output, [[
    // Native-sized buffers have no picture outside their rectangle. Leave
    // those corners black rather than zooming, stretching or smearing edges.
    if ((abs(sc_s) > 0.000001 || abs(sc_c - 1.0) > 0.000001)
        && (sc_tex_coord.x < 0.0 || sc_tex_coord.x > 1.0
            || sc_tex_coord.y < 0.0 || sc_tex_coord.y > 1.0)) {
        color = vec3(0.0);
    }
    ]] .. output)
    if not body then
        return nil, err
    end
    return prefix .. scale_declaration .. declarations .. "\nvoid main() {\n" .. transform .. body
end

return M
