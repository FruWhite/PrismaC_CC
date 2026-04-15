local M = {}
local base_dir = rawget(_G, "PRISMATIC_BASE_DIR")
if not base_dir then
    local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "utils.lua"
    base_dir = fs.getDir(running_program)
end

local function load_local(name)
    if base_dir and base_dir ~= "" then
        return dofile(fs.combine(base_dir, name))
    end
    return dofile(name)
end

local config = rawget(_G, "PRISMATIC_CONFIG")
if not config then
    config = load_local("config_transcendence.lua")
end

M.DEFAULT_CHROMA_SENSOR_SIDE = config.DEFAULT_CHROMA_SENSOR_SIDE
M.CRUCIBLE_WORKING_SIGNAL_SIDE = config.CRUCIBLE_WORKING_SIGNAL_SIDE
M.BUS_CHECK_INTERVAL_SECONDS = config.BUS_CHECK_INTERVAL_SECONDS or 0.1
M.ACTIVE_CORE_INPUT_CONTAINER = config.ACTIVE_CORE_INPUT_CONTAINER
M.SUPERCRITICAL_CORE_INPUT_CONTAINER = config.SUPERCRITICAL_CORE_INPUT_CONTAINER
M.INTERNAL_STORAGE_CONTAINER = config.INTERNAL_STORAGE_CONTAINER
M.CRUCIBLE_INPUT_BUS = config.CRUCIBLE_INPUT_BUS
M.PRISMATIC_COLOR_BY_SIGNAL = config.PRISMATIC_COLOR_BY_SIGNAL

local function read_analog_input(side)
    if redstone.getAnalogInput then
        return redstone.getAnalogInput(side)
    end
    return redstone.getAnalogueInput(side)
end

local function get_inventory(name)
    if type(name) ~= "string" or name == "" then
        error("inventory peripheral name must be a non-empty string", 2)
    end

    local inv = peripheral.wrap(name)
    if not inv then
        error(("peripheral '%s' not found"):format(name), 2)
    end
    if type(inv.list) ~= "function" then
        error(("peripheral '%s' is not an inventory (missing list method)"):format(name), 2)
    end
    return inv
end

function M.decode_chroma_sensor_signal(signal)
    if type(signal) ~= "number" then
        error("signal must be a number", 2)
    end

    signal = math.floor(signal)
    local color = M.PRISMATIC_COLOR_BY_SIGNAL[signal]
    if not color then
        return nil, ("invalid chroma sensor signal %d (expected 1..12)"):format(signal)
    end

    return color
end

function M.is_crucible_working()
    local side = M.CRUCIBLE_WORKING_SIGNAL_SIDE
    if type(side) ~= "string" or side == "" then
        error("CRUCIBLE_WORKING_SIGNAL_SIDE must be a non-empty string", 2)
    end
    return read_analog_input(side) > 0
end

function M.read_crucible_color()
    local side = M.DEFAULT_CHROMA_SENSOR_SIDE
    if type(side) ~= "string" or side == "" then
        error("DEFAULT_CHROMA_SENSOR_SIDE must be a non-empty string", 2)
    end

    local signal = read_analog_input(side)
    local color, err = M.decode_chroma_sensor_signal(signal)
    if not color then
        return nil, signal, err
    end

    return color, signal
end

function M.is_crucible_input_bus_empty()
    local input_bus = get_inventory(M.CRUCIBLE_INPUT_BUS)
    return next(input_bus.list()) == nil
end

function M.get_input_push_readiness(required_color)
    if type(required_color) ~= "string" or required_color == "" then
        error("required_color must be a non-empty string", 2)
    end

    local normalized = string.lower(required_color)
    local working = M.is_crucible_working()
    local current_color, signal, color_err = M.read_crucible_color()
    local input_bus_empty = M.is_crucible_input_bus_empty()

    local waiting_for = {}
    if working then
        waiting_for[#waiting_for + 1] = "crucible not working"
    end
    if not current_color then
        waiting_for[#waiting_for + 1] = "valid crucible color signal"
    elseif current_color ~= normalized then
        waiting_for[#waiting_for + 1] = ("crucible color '%s' == '%s'"):format(current_color, normalized)
    end
    if not input_bus_empty then
        waiting_for[#waiting_for + 1] = "input bus empty"
    end

    return {
        required_color = normalized,
        crucible_working = working,
        current_color = current_color,
        current_signal = signal,
        color_error = color_err,
        input_bus_empty = input_bus_empty,
        waiting_for = waiting_for,
        all_met = #waiting_for == 0,
    }
end

function M.has_required_items_in_internal_storage(requirements)
    if type(requirements) ~= "table" then
        error("requirements must be a table", 2)
    end

    local required_by_name = {}

    -- Supports:
    -- 1) array style: { {"mod:item_a", 4}, {"mod:item_b", 2} }
    -- 2) map style:   { ["mod:item_a"] = 4, ["mod:item_b"] = 2 }
    for key, value in pairs(requirements) do
        local item_name, amount

        if type(key) == "number" then
            if type(value) ~= "table" then
                error("array-style requirement must be {item_name, amount}", 2)
            end
            item_name = value[1]
            amount = value[2]
        else
            item_name = key
            amount = value
        end

        if type(item_name) ~= "string" or item_name == "" then
            error("item_name in requirements must be a non-empty string", 2)
        end
        if type(amount) ~= "number" or amount < 1 then
            error(("amount for '%s' must be a number >= 1"):format(item_name), 2)
        end

        amount = math.floor(amount)
        required_by_name[item_name] = (required_by_name[item_name] or 0) + amount
    end

    local storage = get_inventory(M.INTERNAL_STORAGE_CONTAINER)
    local available_by_name = {}

    for _, stack in pairs(storage.list()) do
        available_by_name[stack.name] = (available_by_name[stack.name] or 0) + stack.count
    end

    local missing = {}
    for item_name, needed in pairs(required_by_name) do
        local available = available_by_name[item_name] or 0
        if available < needed then
            missing[#missing + 1] = {
                item = item_name,
                needed = needed,
                available = available,
            }
        end
    end

    if #missing > 0 then
        return false, missing
    end

    return true
end

local function push_one_item_by_name(source_name, target_name, item_name)
    local source = get_inventory(source_name)
    local source_items = source.list()
    local source_slot = nil

    for slot, stack in pairs(source_items) do
        if stack.name == item_name and stack.count > 0 then
            source_slot = slot
            break
        end
    end

    if not source_slot then
        return nil, ("item '%s' not found in '%s'"):format(item_name, source_name)
    end

    if type(source.pushItems) ~= "function" then
        error(("peripheral '%s' cannot push items (missing pushItems method)"):format(source_name), 2)
    end

    local moved = source.pushItems(target_name, source_slot, 1)
    if moved ~= 1 then
        return nil, ("failed to push '%s' to '%s' (moved=%d)"):format(item_name, target_name, moved or 0)
    end

    return true
end

function M.push_item_to_input_bus(item_name, required_color, on_wait_update)
    if type(item_name) ~= "string" or item_name == "" then
        error("item_name must be a non-empty string", 2)
    end
    if type(required_color) ~= "string" or required_color == "" then
        error("required_color must be a non-empty string", 2)
    end
    if on_wait_update ~= nil and type(on_wait_update) ~= "function" then
        error("on_wait_update must be a function or nil", 2)
    end

    required_color = string.lower(required_color)
    if type(M.BUS_CHECK_INTERVAL_SECONDS) ~= "number" or M.BUS_CHECK_INTERVAL_SECONDS < 0 then
        error("BUS_CHECK_INTERVAL_SECONDS must be a number >= 0", 2)
    end

    while true do
        local readiness = M.get_input_push_readiness(required_color)
        if on_wait_update then
            on_wait_update(readiness)
        end
        if readiness.all_met then
            break
        end

        sleep(M.BUS_CHECK_INTERVAL_SECONDS)
    end

    return push_one_item_by_name(M.INTERNAL_STORAGE_CONTAINER, M.CRUCIBLE_INPUT_BUS, item_name)
end

return M
