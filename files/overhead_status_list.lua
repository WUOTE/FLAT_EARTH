-- Appended after the status definitions, before native status registration.
-- Change ONLY the icon resource: effect IDs, order, thresholds, names, timers
-- and effect entities remain the game's (and other mods') definitions.
local wrappers = dofile("mods/FLAT_EARTH/files/generated_status_icons/wrappers.lua")
for _, effect in ipairs(status_effects or {}) do
    effect.ui_icon = wrappers[effect.ui_icon] or effect.ui_icon
end
