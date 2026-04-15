local base_dir = rawget(_G, "PRISMATIC_BASE_DIR")
if not base_dir then
    local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "psoc.lua"
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
    config = load_local("config_processing.lua")
end

local utils = rawget(_G, "PRISMATIC_UTILS")
if not utils then
    utils = load_local("utils.lua")
end

local M = {}
local FINAL_COLOR_SETTLE_SECONDS = 2.0

local PSOC_REQUIREMENTS = {
    ["kubejs:photonic_soc_cyan"] = 1,
    ["kubejs:photonic_soc_yellow"] = 1,
    ["kubejs:photonic_soc_magenta"] = 1,
    ["kubejs:photonic_soc_inert"] = 3,
}

-- Sequence provided by user:
-- start crucible red, then:
-- cyan; inert; yellow; inert; magenta; inert
-- end crucible red, output 3 active.
local PSOC_SEQUENCE = {
    { item = "kubejs:photonic_soc_cyan", color = "red", label = "cyan @ red -> active, crucible cyan" },
    { item = "kubejs:photonic_soc_inert", color = "cyan", label = "inert @ cyan -> cyan, crucible blue" },
    { item = "kubejs:photonic_soc_yellow", color = "blue", label = "yellow @ blue -> active, crucible yellow" },
    { item = "kubejs:photonic_soc_inert", color = "yellow", label = "inert @ yellow -> yellow, crucible green" },
    { item = "kubejs:photonic_soc_magenta", color = "green", label = "magenta @ green -> active, crucible magenta" },
    { item = "kubejs:photonic_soc_inert", color = "magenta", label = "inert @ magenta -> magenta, crucible red" },
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

function M.run_psoc_cycle(on_status)
    emit_status(on_status, {
        phase = "precheck",
        message = "Checking PSOC ingredients",
    })

    local ready, missing = utils.has_required_items_in_internal_storage(PSOC_REQUIREMENTS)
    emit_status(on_status, {
        phase = "precheck",
        ingredients_ready = ready,
        missing = missing,
        message = ready and "Ingredients ready" or "Ingredients missing",
    })
    if not ready then
        return nil, missing
    end

    local last_step = nil
    for _, step in ipairs(PSOC_SEQUENCE) do
        local ok, err = utils.push_item_to_input_bus(step.item, step.color, function(readiness)
            emit_status(on_status, {
                phase = "step_wait",
                current_step = step.label,
                last_step = last_step,
                waiting_for = readiness.waiting_for,
                current_color = readiness.current_color,
                message = readiness.all_met and "Input conditions met" or "Waiting for input conditions",
            })
        end)
        if not ok then
            return nil, err
        end
        last_step = step.label
        emit_status(on_status, {
            phase = "step_done",
            current_step = nil,
            last_step = last_step,
            message = "Step finished",
        })
    end

    local deadline = os.clock() + FINAL_COLOR_SETTLE_SECONDS
    while true do
        local color, _, err = utils.read_crucible_color()
        if color == "red" then
            break
        end
        if os.clock() >= deadline then
            if color then
                return nil, ("psoc cycle finished on '%s' instead of 'red'"):format(color)
            end
            return nil, err
        end
        emit_status(on_status, {
            phase = "final_color_settle",
            current_step = nil,
            last_step = last_step,
            waiting_for = { "crucible final color red" },
            current_color = color,
            message = "Waiting for final color settle",
        })
        sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
    end

    emit_status(on_status, {
        phase = "output_move",
        current_step = nil,
        last_step = last_step,
        message = "Moving active PSOC x3 to output container",
    })

    for _ = 1, 3 do
        local moved, move_err = push_one_item_by_name(
            config.INTERNAL_STORAGE_CONTAINER,
            config.OUTPUT_CONTAINER,
            "kubejs:photonic_soc_active"
        )
        if not moved then
            return nil, move_err
        end
    end

    emit_status(on_status, {
        phase = "done",
        current_step = nil,
        last_step = last_step,
        ingredients_ready = true,
        message = "PSOC cycle complete",
    })
    return true
end

return M
