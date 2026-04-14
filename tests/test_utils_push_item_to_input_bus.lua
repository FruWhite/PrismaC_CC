local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "tests/test_utils_push_item_to_input_bus.lua"
local project_root = fs.combine(fs.getDir(running_program), "..")
_G.PRISMATIC_CONFIG = dofile(fs.combine(project_root, "config.lua"))
local utils = dofile(fs.combine(project_root, "utils.lua"))

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

local old_peripheral = peripheral
local old_redstone = redstone
local old_sleep = sleep

local stage = 1
local sleep_calls = 0
local pushed_items = 0
local last_push_target = nil
local last_push_name = nil

local storage_slots = {
    [3] = { name = "kubejs:red_prismatic_core", count = 1 },
}

local function input_bus_list()
    if stage == 3 then
        return { [1] = { name = "minecraft:stone", count = 1 } }
    end
    return {}
end

local mock_peripherals = {}
mock_peripherals[utils.INTERNAL_STORAGE_CONTAINER] = {
    list = function()
        return storage_slots
    end,
    pushItems = function(target, slot, limit)
        local stack = storage_slots[slot]
        if not stack or stack.count <= 0 or limit < 1 then
            return 0
        end
        storage_slots[slot].count = storage_slots[slot].count - 1
        if storage_slots[slot].count == 0 then
            storage_slots[slot] = nil
        end
        pushed_items = pushed_items + 1
        last_push_target = target
        last_push_name = stack.name
        return 1
    end,
}
mock_peripherals[utils.CRUCIBLE_INPUT_BUS] = {
    list = input_bus_list,
}

_G.peripheral = {
    wrap = function(name)
        return mock_peripherals[name]
    end,
}

_G.redstone = {
    getAnalogInput = function(side)
        if side == utils.CRUCIBLE_WORKING_SIGNAL_SIDE then
            if stage == 1 then
                return 1
            end
            return 0
        end
        if side == utils.DEFAULT_CHROMA_SENSOR_SIDE then
            if stage <= 2 then
                return 2 -- orange
            end
            return 1 -- red
        end
        return 0
    end,
}

_G.sleep = function(seconds)
    sleep_calls = sleep_calls + 1
    assert_eq(seconds, utils.BUS_CHECK_INTERVAL_SECONDS, "sleep interval should come from config constant")
    stage = stage + 1
end

-- is_crucible_working
assert_truthy(utils.is_crucible_working(), "crucible should be working at stage 1")
stage = 2
assert_eq(utils.is_crucible_working(), false, "crucible should not be working at stage 2")

-- is_crucible_input_bus_empty
stage = 3
assert_eq(utils.is_crucible_input_bus_empty(), false, "input bus should not be empty at stage 3")
stage = 4
assert_truthy(utils.is_crucible_input_bus_empty(), "input bus should be empty at stage 4")

-- push_item_to_input_bus should wait until all 3 conditions are met then push 1 item.
stage = 1
sleep_calls = 0
local ok, err = utils.push_item_to_input_bus("kubejs:red_prismatic_core", "red")
assert_truthy(ok, "push_item_to_input_bus should succeed, err=" .. tostring(err))
assert_eq(err, nil, "push_item_to_input_bus should not return error on success")
assert_eq(sleep_calls, 3, "push_item_to_input_bus should wait through 3 unsatisfied stages")
assert_eq(pushed_items, 1, "exactly one item should be pushed")
assert_eq(last_push_target, utils.CRUCIBLE_INPUT_BUS, "item should be pushed into crucible input bus")
assert_eq(last_push_name, "kubejs:red_prismatic_core", "pushed item should match requested name")

-- missing item should return nil + error
local ok2, err2 = utils.push_item_to_input_bus("kubejs:not_present", "red")
assert_eq(ok2, nil, "missing item should fail")
assert_truthy(err2, "missing item should return an error message")

_G.peripheral = old_peripheral
_G.redstone = old_redstone
_G.sleep = old_sleep

print("test_utils_push_item_to_input_bus.lua: PASS")
