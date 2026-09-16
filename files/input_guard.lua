-- The receiver has no status effects. Its buttons are NOT proof that the real
-- player may act. During native restrictions, do not relay or force anything:
-- vanilla must process stun, delayed input, trigger locks and hidden items.
local M = {}
local native_effects = {"FROZEN", "ELECTROCUTION", "CONFUSION"}

function M.reason(player, controls)
    if not controls or ComponentGetValue2(controls, "enabled") == false then
        return "controls disabled"
    end
    if (ComponentGetValue2(controls, "input_latency_frames") or 0) > 0 then
        return "native input latency"
    end
    for _, effect in ipairs(native_effects) do
        if GameGetGameEffectCount(player, effect) > 0 then
            return "native effect: " .. effect
        end
    end
    -- Covers custom immobilizing effects as well as vanilla freeze/electricity.
    -- Only inspect the player and attached effects, never an area of the world.
    local function immobilized(entity)
        for _, effect in ipairs(EntityGetComponent(entity, "GameEffectComponent") or {}) do
            if ComponentGetValue2(effect, "disable_movement") == true and
                ComponentGetValue2(effect, "frames") ~= 0 then
                return true
            end
        end
        return false
    end
    if immobilized(player) then
        return "movement disabled by effect"
    end
    for _, child in ipairs(EntityGetAllChildren(player) or {}) do
        if immobilized(child) then
            return "movement disabled by effect"
        end
    end
    local platform = EntityGetFirstComponent(player, "PlatformShooterPlayerComponent")
    if not platform then
        return "no native player controls"
    end
    if ComponentGetValue2(platform, "mRequireTriggerPull") == true or
        (ComponentGetValue2(platform, "mItemTemporarilyHidden") or 0) > 0 or
        ComponentGetValue2(platform, "mCessationDo") == true then
        return "native action lock"
    end
    return nil
end

return M
