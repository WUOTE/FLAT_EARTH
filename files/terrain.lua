local geometry = dofile_once("mods/FLAT_EARTH/files/camera_math.lua")
local M = {}
local offsets = {-12, -8, -4, 4, 8, 12}
local cache
function M.reset()
    cache = nil
end

function M.measure(player, frame)
    frame = frame or GameGetFrameNum()
    local character = EntityGetFirstComponent(player, "CharacterDataComponent")
    if not character then
        cache = nil;
        return false, nil
    end
    local grounded = ComponentGetValue2(character, "is_on_ground") == true
    if not grounded then
        cache = nil;
        return false, nil
    end
    local x, y = EntityGetTransform(player)
    local bottom = ComponentGetValue2(character, "collision_aabb_max_y") or 2
    if cache and cache.player == player and cache.character == character and cache.x == x and cache.y == y and
        cache.bottom == bottom and frame >= cache.frame and frame - cache.frame < 6 then
        return true, cache.angle
    end
    local function remember(angle)
        cache = {
            player = player,
            character = character,
            x = x,
            y = y,
            bottom = bottom,
            frame = frame,
            angle = angle
        }
        return true, angle
    end
    local feet = y + bottom
    local hit, _, floor_y = RaytracePlatforms(x, feet - 6, x, feet + 12)
    if not hit or floor_y == nil then
        return remember(nil)
    end

    local points = {{
        x = 0,
        y = 0
    }}
    -- RaytracePlatforms ignores gas/liquids and tests terrain a character can
    -- stand on. A 24-pixel neighbourhood averages over individual pixel steps.
    for _, offset in ipairs(offsets) do
        local found, _, hit_y = RaytracePlatforms(x + offset, floor_y - 24, x + offset, floor_y + 24)
        if found and hit_y ~= nil then
            points[#points + 1] = {
                x = offset,
                y = hit_y - floor_y
            }
        end
    end
    return remember(geometry.fit_ground(points, 12, 2.5))
end

return M
