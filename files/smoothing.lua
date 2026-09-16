-- Stored values remain seconds; the UI defaults to 200 ms and steps by 10 ms.
local M = {default = 0.2, min = 0, max = 2, step = 0.01, slider_max = 10000}
local curve = 0.02
local span = math.log(1 + M.max / curve)
function M.clamp(seconds)
    return math.max(M.min, math.min(M.max, tonumber(seconds) or M.default))
end
function M.to_slider(seconds)
    return math.log(1 + M.clamp(seconds) / curve) / span * M.slider_max
end
function M.from_slider(position)
    local seconds = curve * (math.exp(math.max(0, math.min(M.slider_max, position)) / M.slider_max * span) - 1)
    return M.clamp(math.floor(seconds / M.step + 0.5) * M.step)
end
function M.adjust(seconds, steps)
    return M.clamp(math.floor(M.clamp(seconds) / M.step + steps + 0.5) * M.step)
end
return M
