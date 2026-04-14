local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "tests/test_active_core_cycle.lua"
local project_root = fs.combine(fs.getDir(running_program), "..")

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

local function clone_counts(tbl)
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = v
    end
    return out
end

local function sorted_keys(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

local function list_from_counts(counts)
    local out = {}
    local keys = sorted_keys(counts)
    local slot = 1
    for _, name in ipairs(keys) do
        local count = counts[name]
        if count and count > 0 then
            out[slot] = { name = name, count = count }
            slot = slot + 1
        end
    end
    return out
end

local old_peripheral = peripheral
local old_redstone = redstone
local old_sleep = sleep
local old_config = rawget(_G, "PRISMATIC_CONFIG")
local old_utils = rawget(_G, "PRISMATIC_UTILS")

local config = dofile(fs.combine(project_root, "config.lua"))
_G.PRISMATIC_CONFIG = config
local utils = dofile(fs.combine(project_root, "utils.lua"))
_G.PRISMATIC_UTILS = utils
local active_core = dofile(fs.combine(project_root, "active_core.lua"))

local color_to_signal = {}
for signal, color in pairs(config.PRISMATIC_COLOR_BY_SIGNAL) do
    color_to_signal[color] = signal
end

local state = {
    color = "red",
    working = false,
    pending = nil,
}

local internal_counts = clone_counts(config.ACTIVE_CORE_STORAGE_REQUIREMENTS)
local output_counts = {}

local function add_item(counts, item, amount)
    counts[item] = (counts[item] or 0) + amount
end

local function remove_item(counts, item, amount)
    local cur = counts[item] or 0
    if cur < amount then
        return false
    end
    counts[item] = cur - amount
    if counts[item] == 0 then
        counts[item] = nil
    end
    return true
end

local function transition_for(item_name, current_color)
    local rules = {
        ["kubejs:inert_prismatic_core|red"] = { next_color = "green", output_item = "kubejs:red_prismatic_core" },
        ["kubejs:yellow_prismatic_core|green"] = { next_color = "blue", output_item = "kubejs:green_prismatic_core" },
        ["kubejs:cyan_prismatic_core|blue"] = { next_color = "red", output_item = "kubejs:blue_prismatic_core" },
        ["kubejs:chromatic_stabilizer|red"] = { next_color = "magenta" },
        ["kubejs:blue_prismatic_core|magenta"] = { next_color = "blue", output_item = "kubejs:active_prismatic_core" },
        ["kubejs:chromatic_stabilizer|blue"] = { next_color = "cyan" },
        ["kubejs:green_prismatic_core|cyan"] = { next_color = "green", output_item = "kubejs:cyan_prismatic_core" },
        ["kubejs:chromatic_stabilizer|green"] = { next_color = "yellow" },
        ["kubejs:red_prismatic_core|yellow"] = { next_color = "red", output_item = "kubejs:yellow_prismatic_core" },
    }
    return rules[item_name .. "|" .. current_color]
end

local peripherals = {}

peripherals[config.INTERNAL_STORAGE_CONTAINER] = {
    list = function()
        return list_from_counts(internal_counts)
    end,
    pushItems = function(target_name, slot, limit)
        local snapshot = list_from_counts(internal_counts)
        local stack = snapshot[slot]
        if not stack or not limit or limit < 1 then
            return 0
        end

        local item_name = stack.name
        if target_name == config.CRUCIBLE_INPUT_BUS then
            local transition = transition_for(item_name, state.color)
            if not transition then
                error(("unexpected process transition for %s at color %s"):format(item_name, state.color), 2)
            end

            if not remove_item(internal_counts, item_name, 1) then
                return 0
            end

            state.working = true
            state.pending = transition
            return 1
        end

        if target_name == config.OUTPUT_CONTAINER then
            if not remove_item(internal_counts, item_name, 1) then
                return 0
            end
            add_item(output_counts, item_name, 1)
            return 1
        end

        return 0
    end,
}

peripherals[config.CRUCIBLE_INPUT_BUS] = {
    list = function()
        return {}
    end,
}

peripherals[config.OUTPUT_CONTAINER] = {
    list = function()
        return list_from_counts(output_counts)
    end,
}

_G.peripheral = {
    wrap = function(name)
        return peripherals[name]
    end,
}

_G.redstone = {
    getAnalogInput = function(side)
        if side == config.CRUCIBLE_WORKING_SIGNAL_SIDE then
            return state.working and 1 or 0
        end
        if side == config.DEFAULT_CHROMA_SENSOR_SIDE then
            return color_to_signal[state.color] or 0
        end
        return 0
    end,
}

_G.sleep = function(seconds)
    assert_eq(seconds, config.BUS_CHECK_INTERVAL_SECONDS, "sleep interval should use config.BUS_CHECK_INTERVAL_SECONDS")
    if state.working and state.pending then
        state.working = false
        state.color = state.pending.next_color
        if state.pending.output_item then
            add_item(internal_counts, state.pending.output_item, 1)
        end
        state.pending = nil
    end
end

local ok, err = active_core.run_active_core_cycle()
assert_truthy(ok, "active core cycle should succeed, err=" .. tostring(err))
assert_eq(err, nil, "success path should not return error")
assert_eq(state.color, "red", "cycle should end on red")
assert_eq(state.working, false, "cycle should end not working")
assert_eq(output_counts["kubejs:active_prismatic_core"], 1, "output container should receive one active core")
assert_eq(internal_counts["kubejs:active_prismatic_core"], nil, "active core should be moved out from internal storage")

_G.peripheral = old_peripheral
_G.redstone = old_redstone
_G.sleep = old_sleep
_G.PRISMATIC_CONFIG = old_config
_G.PRISMATIC_UTILS = old_utils

print("test_active_core_cycle.lua: PASS")
