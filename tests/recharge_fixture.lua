-- Small, read-only ECS/GUI fixture. Any gameplay-component mutation is a failure.
fake = {
    frame = 100, player = 1, alive = true, inventory_open = false,
    px = 100, py = 200, cx = 100, cy = 194,
    world_w = 960, world_h = 542, gui_w = 427, gui_h = 242,
    effect = 0, tags = {player_unit = true}, draws = {}, writes = {}, globals = {},
    fields = {
        [11] = {enabled = true, mButtonDownFire = true},
        [12] = {mActiveItem = 2, mActualActiveItem = 2},
        [13] = {},
        [21] = {use_gun_script = true, never_reload = false, mReloadNextFrameUsable = 120},
        [31] = {use_gun_script = true, mReloadNextFrameUsable = 120}
    }
}
function EntityGetIsAlive(id) return id ~= 0 and fake.alive end
function EntityHasTag(id, tag) return id == 1 and fake.tags[tag] == true end
function EntityGetWithTag(tag) return fake.tags[tag] and {1} or {} end
function EntityGetFirstComponent(id, kind)
    if id == 1 then
        return ({ControlsComponent = 11, Inventory2Component = 12, PlatformShooterPlayerComponent = 13})[kind]
    elseif kind == "AbilityComponent" then return id == 2 and 21 or 31 end
end
EntityGetFirstComponentIncludingDisabled = EntityGetFirstComponent
function ComponentGetValue2(id, key) return fake.fields[id][key] end
function ComponentSetValue2() error("notice must not mutate gameplay components") end
function EntityGetComponent() return {} end
function EntityGetAllChildren() return {} end
function EntityGetTransform() return fake.px, fake.py end
function EntityGetFirstHitboxCenter() return fake.px, fake.py - 6 end
function GameGetCameraPos() return fake.cx, fake.cy end
function GameGetCameraBounds() return 0, 0, fake.world_w, fake.world_h end
function GameGetFrameNum() return fake.frame end
function GameIsInventoryOpen() return fake.inventory_open end
function GameGetGameEffectCount() return fake.effect end
function GameTextGetTranslatedOrNot(key)
    assert(key == "$flat_earth_log_recharging")
    return "RECHARGING.."
end
function GuiCreate() return 99 end
function GuiDestroy() fake.draws = {} end
function GuiStartFrame() fake.draws = {} end
function GuiGetScreenDimensions() return fake.gui_w, fake.gui_h end
function GuiGetTextDimensions(_, text) return #text * 5, 7 end
function GuiColorSetForNextWidget(_, r, g, b, a) fake.alpha = a end
function GuiText(_, x, y, text, scale)
    fake.draws[#fake.draws + 1] = {x = x, y = y, text = text, scale = scale or 1}
end
function GlobalsGetValue(key, default) return fake.globals[key] or default end
function GlobalsSetValue(key, value) fake.globals[key] = value end
function GameSetCameraFree() end
function GameSetCameraPos(x, y) fake.cx, fake.cy = x, y end
function GameSetPostFxParameter() end
function ModSettingGet(key)
    if key == "FLAT_EARTH.route_world_sprites" then return false end
    if key == "FLAT_EARTH.extra_coverage" then return fake.extra_coverage ~= false end
end
function ModSettingRemove() end
function ModMagicNumbersFileAdd(path) fake.bounds = path end
function ModTextFileSetContent(path, content) fake.writes[path] = content end
function GamePrint() end
