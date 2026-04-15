local base_dir = rawget(_G, "PRISMATIC_BASE_DIR")
if not base_dir then
    local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "active_core.lua"
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

local utils = rawget(_G, "PRISMATIC_UTILS")
if not utils then
    utils = load_local("utils.lua")
end

local M = {}
local FINAL_COLOR_SETTLE_SECONDS = 2.0

local ACTIVE_CORE_SEQUENCE = {
    { item = "kubejs:blue_prismatic_core", color = "magenta" },
    { item = "kubejs:chromatic_stabilizer", color = "blue" },
    { item = "kubejs:green_prismatic_core", color = "cyan" },
    { item = "kubejs:chromatic_stabilizer", color = "green" },
    { item = "kubejs:red_prismatic_core", color = "yellow" },
    { item = "kubejs:inert_prismatic_core", color = "red" },
    { item = "kubejs:yellow_prismatic_core", color = "green" },
    { item = "kubejs:cyan_prismatic_core", color = "blue" },
    { item = "kubejs:chromatic_stabilizer", color = "red" },
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

local function emit_status(cb, payload)
    if cb then
        cb(payload)
    end
end

local function format_step(step)
    return ("%s @ %s"):format(step.item, step.color)
end

function M.run_active_core_cycle(on_status)
    local last_step = nil
    emit_status(on_status, {
        phase = "precheck",
        message = "Checking active core ingredient availability",
    })

    local ready, missing = utils.has_required_items_in_internal_storage(config.ACTIVE_CORE_STORAGE_REQUIREMENTS)
    emit_status(on_status, {
        phase = "precheck",
        ingredients_ready = ready,
        missing = missing,
        message = ready and "Ingredients ready" or "Ingredients missing",
    })
    if not ready then
        return nil, missing
    end

    for index, step in ipairs(ACTIVE_CORE_SEQUENCE) do
        local step_label = format_step(step)
        emit_status(on_status, {
            phase = "step_wait",
            step_index = index,
            current_step = step_label,
            last_step = last_step,
            waiting_for = {},
            message = "Waiting for input conditions",
        })

        local ok, err = utils.push_item_to_input_bus(step.item, step.color, function(readiness)
            emit_status(on_status, {
                phase = "step_wait",
                step_index = index,
                current_step = step_label,
                last_step = last_step,
                waiting_for = readiness.waiting_for,
                current_color = readiness.current_color,
                crucible_working = readiness.crucible_working,
                input_bus_empty = readiness.input_bus_empty,
                message = readiness.all_met and "Input conditions met" or "Waiting for input conditions",
            })
        end)
        if not ok then
            return nil, err
        end
        emit_status(on_status, {
            phase = "step_submitted",
            step_index = index,
            current_step = step_label,
            last_step = last_step,
            message = "Input pushed to crucible",
        })

        -- Ensure the previous input step is fully finished before next input.
        while utils.is_crucible_working() do
            emit_status(on_status, {
                phase = "step_processing",
                step_index = index,
                current_step = step_label,
                last_step = last_step,
                waiting_for = { "crucible not working" },
                message = "Waiting for crucible to finish step",
            })
            sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
        end
        last_step = step_label
        emit_status(on_status, {
            phase = "step_done",
            step_index = index,
            current_step = nil,
            last_step = last_step,
            message = "Step finished",
        })
    end

    while utils.is_crucible_working() do
        emit_status(on_status, {
            phase = "final_wait",
            current_step = nil,
            last_step = last_step,
            waiting_for = { "crucible not working" },
            message = "Waiting for crucible idle state",
        })
        sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
    end

    local final_color = nil
    local final_err = nil
    local settle_deadline = os.clock() + FINAL_COLOR_SETTLE_SECONDS
    while true do
        final_color, _, final_err = utils.read_crucible_color()
        if final_color == "magenta" then
            break
        end
        if os.clock() >= settle_deadline then
            if final_color then
                return nil, ("cycle finished on '%s' instead of 'magenta'"):format(final_color)
            end
            return nil, final_err
        end

        emit_status(on_status, {
            phase = "final_color_settle",
            current_step = nil,
            last_step = last_step,
            waiting_for = { "crucible final color magenta" },
            current_color = final_color,
            message = "Waiting for final color settle",
        })
        sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
    end

    emit_status(on_status, {
        phase = "output_move",
        current_step = nil,
        last_step = last_step,
        message = "Moving active core to output container",
    })

    local moved, move_err = push_one_item_by_name(
        config.INTERNAL_STORAGE_CONTAINER,
        config.OUTPUT_CONTAINER,
        "kubejs:active_prismatic_core"
    )
    if not moved then
        return nil, move_err
    end

    emit_status(on_status, {
        phase = "done",
        current_step = nil,
        last_step = last_step,
        ingredients_ready = true,
        message = "Active core cycle complete",
    })

    return true
end

return M
