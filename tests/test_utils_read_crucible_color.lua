local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "tests/test_utils_read_crucible_color.lua"
local project_root = fs.combine(fs.getDir(running_program), "..")
_G.PRISMATIC_CONFIG = dofile(fs.combine(project_root, "config_transcendence.lua"))
local utils_path = fs.combine(project_root, "utils.lua")
local utils = dofile(utils_path)

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s (expected=%s, actual=%s)", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assert_truthy(value, message)
    if not value then
        error(message, 2)
    end
end

-- decode_chroma_sensor_signal: valid range
for signal = 1, 12 do
    local color, err = utils.decode_chroma_sensor_signal(signal)
    assert_truthy(color, "expected valid color for signal " .. signal .. ", err=" .. tostring(err))
end

-- decode_chroma_sensor_signal: invalid range
do
    local color0, err0 = utils.decode_chroma_sensor_signal(0)
    assert_eq(color0, nil, "signal 0 should be invalid")
    assert_truthy(err0, "signal 0 should return an error message")

    local color13, err13 = utils.decode_chroma_sensor_signal(13)
    assert_eq(color13, nil, "signal 13 should be invalid")
    assert_truthy(err13, "signal 13 should return an error message")
end

-- read_crucible_color with mocked redstone input
do
    local old_get_analog = redstone.getAnalogInput
    local old_get_analogue = redstone.getAnalogueInput

    redstone.getAnalogInput = function(side)
        local mock = {
            left = 1,    -- red
            right = 11,  -- magenta
            back = 0,    -- invalid
        }
        return mock[side] or 13
    end

    utils.DEFAULT_CHROMA_SENSOR_SIDE = "left"
    local color_left, signal_left, err_left = utils.read_crucible_color()
    assert_eq(color_left, "red", "left should decode to red")
    assert_eq(signal_left, 1, "left should return signal 1")
    assert_eq(err_left, nil, "left should have no error")

    utils.DEFAULT_CHROMA_SENSOR_SIDE = "right"
    local color_right, signal_right, err_right = utils.read_crucible_color()
    assert_eq(color_right, "magenta", "right should decode to magenta")
    assert_eq(signal_right, 11, "right should return signal 11")
    assert_eq(err_right, nil, "right should have no error")

    utils.DEFAULT_CHROMA_SENSOR_SIDE = "back"
    local color_back, signal_back, err_back = utils.read_crucible_color()
    assert_eq(color_back, nil, "back should be invalid")
    assert_eq(signal_back, 0, "back should return signal 0")
    assert_truthy(err_back, "back should provide an error")

    redstone.getAnalogInput = old_get_analog
    redstone.getAnalogueInput = old_get_analogue
end

print("test_utils_read_crucible_color.lua: PASS")
