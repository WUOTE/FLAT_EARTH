-- Run the real settings.lua and vanilla mod-settings library. Only engine API
-- calls are mocked; the loader in Python rejects every mod-local dependency.
settings_test = {current={}, next={}, labels={}, edits=0}
function ModSettingGet(key) return settings_test.current[key] end
function ModSettingGetNextValue(key) return settings_test.next[key] end
function ModSettingSet(key, value) settings_test.current[key] = value end
function ModSettingSetNextValue(key, value, is_default)
    if is_default and settings_test.next[key] ~= nil then return end
    settings_test.next[key] = value
    if not is_default then settings_test.edits = settings_test.edits + 1 end
end
function ModSettingRemove(key)
    settings_test.current[key], settings_test.next[key] = nil, nil
end
function GameTextGet(key) return key end
function GuiText(_, _, _, label)
    settings_test.labels[#settings_test.labels+1] = label
end
function GuiButton(_, _, _, _, label)
    if label ~= '-10 ms' and label ~= '+10 ms' then
        settings_test.labels[#settings_test.labels+1] = label
    end
    return settings_test.click == label, false
end
function GuiSlider(_, _, _, _, label, value, _, _, default)
    if label ~= '' then
        settings_test.labels[#settings_test.labels+1] = label
        return value
    end
    if settings_test.reset_slider then return default end
    if settings_test.slider ~= nil then return settings_test.slider end
    -- Model float32 rounding in Noita's slider return value.
    return math.floor(value * 2048 + .5) / 2048
end
function GuiIdPushString() end
function GuiIdPop() end
function GuiTooltip() end
function GuiLayoutBeginHorizontal() end
function GuiLayoutEnd() end
