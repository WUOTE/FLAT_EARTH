-- Real late_aim.lua + aim.lua + input_guard.lua run against this ECS fixture.
-- Every component write is recorded; assertions can distinguish camera output
-- from relayed buttons, enabled changes and forced native casts.
relay = {
    frame = 100, next_id = 100, writes = {}, globals = {},
    effects = {}, component_disabled = false, dead = false, children = {},
    camera_releases = 0, camera_free = false, cx = 100, cy = 194,
    components = {
        [11] = {entity=1, kind='ControlsComponent', fields={enabled=true,
            mAimingVector={10,0}, mAimingVectorNormalized={1,0}, mAimingVectorNonZeroLatest={10,0},
            mMousePosition={110,200}, mMousePositionRaw={10,20}, mMousePositionRawPrev={9,20},
            mMouseDelta={1,0}, mButtonDownFire=false, mButtonDownRight=false, input_latency_frames=0}},
        [12] = {entity=1, kind='Inventory2Component', fields={mActiveItem=2, mActualActiveItem=2, mThrowItem=0}},
        [13] = {entity=1, kind='PlatformShooterPlayerComponent', fields={mForceFireOnNextUpdate=false,
            mSmoothedAimingVector={10,0}, mRequireTriggerPull=false, mItemTemporarilyHidden=0, mCessationDo=false}},
        [21] = {entity=2, kind='AbilityComponent', fields={use_gun_script=true, throw_as_item=false}},
        [31] = {entity=3, kind='ControlsComponent', fields={enabled=true,
            mButtonDownFire=true, mButtonFrameFire=100, mButtonDownRight=true,
            mButtonDownFly=true, mButtonFrameRight=100, mFlyingTargetY=190,
            mMousePositionRaw={10,20}, mMousePositionRawPrev={9,20}, mMouseDelta={1,0}}}
    }
}
function EntityGetIsAlive(id) return id ~= nil and id ~= 0 and not (id == 1 and relay.dead) end
function EntityHasTag(id, tag) return id == 1 and tag == 'player_unit' end
function EntityGetWithTag(tag) return tag == 'player_unit' and {1} or {} end
function EntityGetFirstComponentIncludingDisabled(entity, kind, tag)
    for id,c in pairs(relay.components) do
        if c.entity == entity and c.kind == kind and (not tag or c.fields._tags == tag) then return id end
    end
end
function EntityGetFirstComponent(entity, kind, tag)
    if entity == 1 and kind == 'ControlsComponent' and relay.component_disabled then return nil end
    return EntityGetFirstComponentIncludingDisabled(entity, kind, tag)
end
function EntityGetComponent(entity, kind)
    local result = {}
    for id,c in pairs(relay.components) do
        if c.entity == entity and c.kind == kind then result[#result+1] = id end
    end
    return result
end
EntityGetComponentIncludingDisabled = EntityGetComponent
function EntityGetAllChildren(entity) return entity == 1 and relay.children or {} end
function EntityAddComponent2(entity, kind, fields)
    relay.next_id = relay.next_id + 1
    relay.components[relay.next_id] = {entity=entity, kind=kind, fields=fields}
    return relay.next_id
end
function EntityRemoveComponent(_, id) relay.components[id] = nil end
function ComponentGetValue2(id, field)
    local value = relay.components[id].fields[field]
    if type(value) == 'table' then return unpack(value) end
    return value
end
function ComponentSetValue2(id, field, ...)
    local values = {...}
    relay.writes[#relay.writes+1] = {id=id, field=field, value=values[1]}
    relay.components[id].fields[field] = #values > 1 and values or values[1]
end
function ComponentGetEntity(id) return relay.components[id].entity end
function ComponentGetIsEnabled(id) return not (id == 11 and relay.component_disabled) end
function EntityLoad(path)
    assert(path == 'mods/FLAT_EARTH/files/input_receiver.xml')
    return 3
end
function EntityKill() end
function EntityGetTransform() return 100,200,0,1,1 end
function EntitySetTransform() end
function EntityGetFirstHitboxCenter() return 100,194 end
function GameGetGameEffectCount(_, effect) return relay.effects[effect] or 0 end
function GameGetFrameNum() return relay.frame end
function GameGetCameraPos() return relay.cx, relay.cy end
function GameSetCameraPos(x,y) relay.cx,relay.cy=x,y end
function GameSetCameraFree(free)
    relay.camera_free = free
    if not free then relay.camera_releases = relay.camera_releases+1 end
end
function GameSetPostFxParameter(name,x,y,z,w) relay.rotation = {x,y,z,w} end
function GameIsInventoryOpen() return false end
function DEBUG_GetMouseWorld() return 110,200 end
function GlobalsGetValue(name, default) return relay.globals[name] or default end
function GlobalsSetValue(name,value) relay.globals[name]=value end
function ModSettingGet(name)
    if name == 'FLAT_EARTH.route_world_sprites' then return false end
    return nil
end
function ModSettingRemove() end
function ModMagicNumbersFileAdd() end
function ModTextFileSetContent() end
function GamePrint() end
function relay_reset_writes() relay.writes = {} end
function relay_gameplay_writes()
    local result={}
    for _,write in ipairs(relay.writes) do
        if write.id == 11 or write.id == 12 or write.id == 13 then result[#result+1]=write end
    end
    return result
end
