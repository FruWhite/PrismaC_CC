local config = dofile("config.lua")
_G.PRISMATIC_CONFIG = config

local utils = dofile("utils.lua")
_G.PRISMATIC_UTILS = utils

local active_core = dofile("active_core.lua")

local REQUIRED_EXTERNAL_INPUT = {
    ["kubejs:inert_prismatic_core"] = 1,
    ["kubejs:chromatic_stabilizer"] = 3,
}

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

local function count_item_in_inventory(inv, item_name)
    local total = 0
    for _, stack in pairs(inv.list()) do
        if stack.name == item_name then
            total = total + stack.count
        end
    end
    return total
end

local function external_has_required_batch(external_input)
    for item_name, needed in pairs(REQUIRED_EXTERNAL_INPUT) do
        if count_item_in_inventory(external_input, item_name) < needed then
            return false
        end
    end
    return true
end

local function move_item_amount_by_name(source_inv, target_name, item_name, amount)
    local remaining = amount
    local snapshot = source_inv.list()

    for slot, stack in pairs(snapshot) do
        if remaining <= 0 then
            break
        end
        if stack.name == item_name and stack.count > 0 then
            local moved = source_inv.pushItems(target_name, slot, remaining)
            remaining = remaining - (moved or 0)
        end
    end

    if remaining > 0 then
        return nil, ("failed moving %s x%d (missing %d)"):format(item_name, amount, remaining)
    end
    return true
end

local function import_external_batch_to_internal(external_input)
    for item_name, needed in pairs(REQUIRED_EXTERNAL_INPUT) do
        local ok, err = move_item_amount_by_name(
            external_input,
            config.INTERNAL_STORAGE_CONTAINER,
            item_name,
            needed
        )
        if not ok then
            return nil, err
        end
    end
    return true
end

local function run_once_if_ready(external_input)
    local has_any_input = next(external_input.list()) ~= nil
    if not has_any_input then
        return
    end

    if not external_has_required_batch(external_input) then
        return
    end

    local moved, move_err = import_external_batch_to_internal(external_input)
    if not moved then
        print("Import failed: " .. tostring(move_err))
        return
    end

    local ok, cycle_err = active_core.run_active_core_cycle()
    if not ok then
        print("Active core cycle failed: " .. tostring(cycle_err))
        return
    end

    print("Active core cycle complete.")
end

local function read_analog_input(side)
    if redstone.getAnalogInput then
        return redstone.getAnalogInput(side)
    end
    return redstone.getAnalogueInput(side)
end

local function is_trigger_on()
    local side = config.AE2_CRAFT_TRIGGER_SIDE
    if type(side) ~= "string" or side == "" then
        error("AE2_CRAFT_TRIGGER_SIDE must be a non-empty string", 2)
    end
    return read_analog_input(side) > 0
end

local function main()
    local external_input = get_inventory(config.EXTERNAL_INPUT_CONTAINER)
    if type(external_input.pushItems) ~= "function" then
        error(("peripheral '%s' cannot push items (missing pushItems method)"):format(config.EXTERNAL_INPUT_CONTAINER), 2)
    end

    print("PrismaticCrucible trigger loop started.")

    local was_on = is_trigger_on()
    if was_on then
        run_once_if_ready(external_input)
    end

    while true do
        local event = { os.pullEvent() }
        if event[1] == "redstone" then
            local is_on = is_trigger_on()
            if is_on and not was_on then
                run_once_if_ready(external_input)
            end
            was_on = is_on
        end
    end
end

main()
