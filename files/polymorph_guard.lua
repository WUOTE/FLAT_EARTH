-- Functional, event-only lifecycle guard. No per-frame script or debug input.
function polymorphing_to(...)
    local player = GetUpdatedEntityID()
    local input = dofile_once("mods/FLAT_EARTH/files/late_aim.lua")
    input.before_polymorph(player)
end
