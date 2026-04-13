local config = rawget(_G, "PRISMATIC_CONFIG")
if not config then
    config = dofile("config.lua")
end

local utils = rawget(_G, "PRISMATIC_UTILS")
if not utils then
    utils = dofile("utils.lua")
end

local M = {}

local ACTIVE_CORE_SEQUENCE = {
    { item = "kubejs:inert_prismatic_core", color = "red" },
    { item = "kubejs:yellow_prismatic_core", color = "green" },
    { item = "kubejs:cyan_prismatic_core", color = "blue" },
    { item = "kubejs:chromatic_stabilizer", color = "red" },
    { item = "kubejs:blue_prismatic_core", color = "magenta" },
    { item = "kubejs:chromatic_stabilizer", color = "blue" },
    { item = "kubejs:green_prismatic_core", color = "cyan" },
    { item = "kubejs:chromatic_stabilizer", color = "green" },
    { item = "kubejs:red_prismatic_core", color = "yellow" },
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

local function push_one_item_by_name(source_name, target_name, item_name)
    local source = get_inventory(source_name)
    local source_slot = nil

    for slot, stack in pairs(source.list()) do
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

function M.run_active_core_cycle()
    local ready, missing = utils.has_required_items_in_internal_storage(config.ACTIVE_CORE_STORAGE_REQUIREMENTS)
    if not ready then
        return nil, missing
    end

    for _, step in ipairs(ACTIVE_CORE_SEQUENCE) do
        local ok, err = utils.push_item_to_input_bus(step.item, step.color)
        if not ok then
            return nil, err
        end
        -- Ensure the previous input step is fully finished before next input.
        while utils.is_crucible_working() do
            sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
        end
    end

    while utils.is_crucible_working() do
        sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
    end

    local color, _, color_err = utils.read_crucible_color()
    if not color then
        return nil, color_err
    end
    if color ~= "red" then
        return nil, ("cycle finished on '%s' instead of 'red'"):format(color)
    end

    local moved, move_err = push_one_item_by_name(
        config.INTERNAL_STORAGE_CONTAINER,
        config.OUTPUT_CONTAINER,
        "kubejs:active_prismatic_core"
    )
    if not moved then
        return nil, move_err
    end

    return true
end

return M
