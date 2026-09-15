-- Pure geometry: world coordinates have +Y pointing down.
local M = {}
local pi = math.pi

function M.clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function M.atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and pi or -pi) end
    if y > 0 then return pi / 2 end
    if y < 0 then return -pi / 2 end
    return 0
end

function M.rotate(x, y, angle)
    local c, s = math.cos(angle), math.sin(angle)
    return c * x - s * y, s * x + c * y
end

-- A tangent is an unoriented line: walking LEFT on a slope must not flip
-- the entire view through 180 degrees. A vertical path uses the last facing.
function M.tangent_angle(dx, dy, facing)
    if dx * dx + dy * dy < 0.000001 then return nil end
    local direction = dx < -0.001 and -1 or (dx > 0.001 and 1 or (facing or 1))
    return M.atan2(dy * direction, math.abs(dx))
end

function M.screen_to_world(dx, dy, angle, scale)
    return M.rotate(dx * scale, dy * scale, angle)
end

function M.world_to_screen(dx, dy, angle, scale)
    local x, y = M.rotate(dx, dy, -angle)
    return x / scale, y / scale
end

-- Least-squares ground tangent, rejecting gaps, ledges and very uneven
-- groups of hits rather than interpreting them as a smooth walkable slope.
function M.fit_ground(points, min_span, max_residual)
    if #points < 4 then return nil end
    local sx, sy, min_x, max_x = 0, 0, math.huge, -math.huge
    for _, point in ipairs(points) do
        sx, sy = sx + point.x, sy + point.y
        min_x, max_x = math.min(min_x, point.x), math.max(max_x, point.x)
    end
    if max_x - min_x < (min_span or 12) then return nil end
    local mean_x, mean_y = sx / #points, sy / #points
    local xx, xy = 0, 0
    for _, point in ipairs(points) do
        local x = point.x - mean_x
        xx, xy = xx + x * x, xy + x * (point.y - mean_y)
    end
    if xx < 0.001 then return nil end
    local slope = xy / xx
    local error_sum = 0
    for _, point in ipairs(points) do
        local error = point.y - (mean_y + slope * (point.x - mean_x))
        error_sum = error_sum + error * error
    end
    if math.sqrt(error_sum / #points) > (max_residual or 2.5) then return nil end
    return math.atan(slope)
end

function M.smooth_angle(current, target, seconds, dt)
    if seconds <= 0 then return target end
    local change = (target - current) * (1 - math.exp(-dt / seconds))
    -- Also bound the angular speed after a sudden terrain change.
    change = M.clamp(change, -math.pi * dt, math.pi * dt)
    local result = current + change
    if math.abs(target - result) < 0.00001 then return target end
    return result
end

function M.new_tracker()
    return { angle = 0, target = 0, history = {}, facing = 1 }
end

function M.reset_tracker(state, x, y, frame)
    state.angle, state.target = 0, 0
    state.history = { { x = x, y = y, frame = frame } }
    state.x, state.y, state.frame = x, y, frame
    state.grounded = false
end

function M.update_tracker(state, x, y, frame, grounded, ground_angle, options)
    if not state.frame then M.reset_tracker(state, x, y, frame) end
    local frame_delta = math.max(1, frame - state.frame)
    local dx, dy = x - state.x, y - state.y
    -- Teleports, new runs and long gaps must not be treated as travel slopes.
    if dx * dx + dy * dy > 64 * 64 or frame < state.frame or frame_delta > 30 then
        M.reset_tracker(state, x, y, frame)
        state.grounded = grounded
        return state.angle
    end
    if math.abs(dx) > 0.05 then state.facing = dx > 0 and 1 or -1 end
    if grounded ~= state.grounded then state.history = {} end
    local history = state.history
    history[#history + 1] = { x = x, y = y, frame = frame }
    while #history > 1 and frame - history[1].frame > 10 do table.remove(history, 1) end

    if not options.enabled then
        state.target = 0
    elseif not options.locked then
        local candidate = grounded and ground_angle or nil
        if candidate == nil and (grounded or options.follow_airborne) and #history > 1 then
            local first = history[1]
            local mx, my = x - first.x, y - first.y
            -- Do not turn tiny pixel jitters or standing on a lift into a slope.
            if mx * mx + my * my >= 1 and (options.follow_airborne or math.abs(mx) >= 1) then
                candidate = M.tangent_angle(mx, my, state.facing)
            end
        end
        if candidate ~= nil then
            state.target = M.clamp(candidate, -options.max_angle, options.max_angle)
        end
    else
        state.target = state.angle
    end
    state.angle = M.smooth_angle(state.angle, state.target, options.smoothing, frame_delta / 60)
    state.x, state.y, state.frame, state.grounded = x, y, frame, grounded
    return state.angle
end

return M
