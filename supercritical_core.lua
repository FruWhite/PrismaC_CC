local base_dir = rawget(_G, "PRISMATIC_BASE_DIR")
if not base_dir then
    local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "supercritical_core.lua"
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
local RANDOM_COLOR_SETTLE_SECONDS = 2.0

local function emit_status(cb, payload)
    if cb then
        cb(payload)
    end
end

local function wait_until_idle(on_status, last_step)
    while utils.is_crucible_working() do
        emit_status(on_status, {
            phase = "step_processing",
            last_step = last_step,
            waiting_for = { "crucible not working" },
            message = "Waiting for crucible to finish step",
        })
        sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
    end
end

local function run_step(item_name, required_color, on_status, step_label, last_step)
    emit_status(on_status, {
        phase = "step_wait",
        current_step = step_label,
        last_step = last_step,
        waiting_for = {},
        message = "Waiting for input conditions",
    })

    local ok, err = utils.push_item_to_input_bus(item_name, required_color, function(readiness)
        emit_status(on_status, {
            phase = "step_wait",
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
        current_step = step_label,
        last_step = last_step,
        message = "Input pushed to crucible",
    })

    wait_until_idle(on_status, last_step)
    return true
end

local function read_color_or_error()
    local color, _, err = utils.read_crucible_color()
    if not color then
        return nil, err
    end
    return color
end

local function wait_for_color_in(allowed_set, branch_name, on_status, last_step)
    local deadline = os.clock() + RANDOM_COLOR_SETTLE_SECONDS
    while true do
        local color, err = read_color_or_error()
        if not color then
            return nil, err
        end
        if allowed_set[color] then
            return color
        end
        if os.clock() >= deadline then
            return nil, ("random %s unexpected color '%s'"):format(branch_name, color)
        end

        local expected = {}
        for c, _ in pairs(allowed_set) do
            expected[#expected + 1] = c
        end
        table.sort(expected)
        emit_status(on_status, {
            phase = "random_settle",
            last_step = last_step,
            current_color = color,
            waiting_for = { "color in {" .. table.concat(expected, "/") .. "}" },
            message = "Waiting random branch color settle",
        })
        sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
    end
end

local function get_inventory(name)
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

local function push_all_item_by_name(source_name, target_name, item_name)
    local source = get_inventory(source_name)
    local total = 0
    local changed = true

    while changed do
        changed = false
        for slot, stack in pairs(source.list()) do
            if stack.name == item_name and stack.count > 0 then
                local moved = source.pushItems(target_name, slot, stack.count)
                if moved > 0 then
                    total = total + moved
                    changed = true
                end
            end
        end
    end

    return total
end

function M.run_supercritical_core_cycle(on_status)
    emit_status(on_status, {
        phase = "precheck",
        message = "Checking supercritical ingredient availability",
    })
    local ready, missing = utils.has_required_items_in_internal_storage(config.SUPERCRITICAL_CORE_STORAGE_REQUIREMENTS)
    emit_status(on_status, {
        phase = "precheck",
        ingredients_ready = ready,
        missing = missing,
        message = ready and "Ingredients ready" or "Ingredients missing",
    })
    if not ready then
        return nil, missing
    end

    local color, color_err = read_color_or_error()
    if not color then
        return nil, color_err
    end
    if color ~= "magenta" then
        return nil, ("supercritical cycle requires start color 'magenta', got '%s'"):format(color)
    end

    local last_step = nil
    local function step(item, color_need, label)
        local ok, err = run_step(item, color_need, on_status, label, last_step)
        if not ok then
            return nil, err
        end
        last_step = label
        emit_status(on_status, {
            phase = "step_done",
            current_step = nil,
            last_step = last_step,
            message = "Step finished",
        })
        return true
    end

    -- Opening sequence
    local ok, err = step("kubejs:chromatic_capacitor_empty", "magenta", "charge magenta capacitor")
    if not ok then return nil, err end
    ok, err = step("kubejs:blue_prismatic_core", "magenta", "blue @ magenta")
    if not ok then return nil, err end
    ok, err = step("kubejs:cyan_prismatic_core", "blue", "cyan @ blue")
    if not ok then return nil, err end
    ok, err = step("kubejs:chromatic_capacitor_magenta", "red", "discharge magenta capacitor to pink")
    if not ok then return nil, err end
    ok, err = step("kubejs:indigo_prismatic_core", "pink", "indigo @ pink -> supercritical")
    if not ok then return nil, err end

    -- B branch
    ok, err = step("kubejs:lime_prismatic_core", "teal", "lime @ teal (random B)")
    if not ok then return nil, err end
    color, color_err = wait_for_color_in({ blue = true, cyan = true }, "B", on_status, last_step)
    if not color then return nil, color_err end
    if color == "blue" then
        ok, err = step("kubejs:chromatic_stabilizer", "blue", "stabilizer blue->cyan")
        if not ok then return nil, err end
    end
    ok, err = step("kubejs:chromatic_capacitor_empty", "cyan", "charge cyan capacitor")
    if not ok then return nil, err end
    ok, err = step("kubejs:green_prismatic_core", "cyan", "green @ cyan")
    if not ok then return nil, err end
    ok, err = step("kubejs:yellow_prismatic_core", "green", "yellow @ green")
    if not ok then return nil, err end
    ok, err = step("kubejs:chromatic_capacitor_cyan", "blue", "discharge cyan capacitor to azure")
    if not ok then return nil, err end

    -- A branch
    ok, err = step("kubejs:teal_prismatic_core", "azure", "teal @ azure")
    if not ok then return nil, err end
    ok, err = step("kubejs:active_prismatic_core", "orange", "active @ orange (random A)")
    if not ok then return nil, err end
    color, color_err = wait_for_color_in({ green = true, yellow = true }, "A", on_status, last_step)
    if not color then return nil, color_err end
    if color == "green" then
        ok, err = step("kubejs:chromatic_stabilizer", "green", "stabilizer green->yellow")
        if not ok then return nil, err end
    end
    ok, err = step("kubejs:chromatic_capacitor_empty", "yellow", "charge yellow capacitor")
    if not ok then return nil, err end
    ok, err = step("kubejs:red_prismatic_core", "yellow", "red @ yellow")
    if not ok then return nil, err end
    ok, err = step("kubejs:inert_prismatic_core", "red", "inert @ red")
    if not ok then return nil, err end
    ok, err = step("kubejs:chromatic_capacitor_yellow", "green", "discharge yellow capacitor to lime")
    if not ok then return nil, err end

    -- Ending C branch
    ok, err = step("kubejs:orange_prismatic_core", "lime", "orange @ lime")
    if not ok then return nil, err end
    ok, err = step("kubejs:azure_prismatic_core", "indigo", "azure @ indigo (random C)")
    if not ok then return nil, err end
    color, color_err = wait_for_color_in({ red = true, magenta = true }, "C", on_status, last_step)
    if not color then return nil, color_err end
    if color == "red" then
        ok, err = step("kubejs:chromatic_stabilizer", "red", "stabilizer red->magenta")
        if not ok then return nil, err end
    end

    color, color_err = wait_for_color_in({ magenta = true }, "final", on_status, last_step)
    if not color then return nil, color_err end

    -- Output handling
    emit_status(on_status, {
        phase = "output_move",
        current_step = nil,
        last_step = last_step,
        message = "Moving supercritical core to output",
    })
    local moved, move_err = push_one_item_by_name(
        config.INTERNAL_STORAGE_CONTAINER,
        config.OUTPUT_CONTAINER,
        "kubejs:supercritical_prismatic_core"
    )
    if not moved then
        return nil, move_err
    end

    local extra_stabs = push_all_item_by_name(
        config.INTERNAL_STORAGE_CONTAINER,
        config.OUTPUT_CONTAINER,
        "kubejs:chromatic_stabilizer"
    )

    emit_status(on_status, {
        phase = "done",
        current_step = nil,
        last_step = last_step,
        ingredients_ready = true,
        extra_stabilizers_moved = extra_stabs,
        message = "Supercritical cycle complete",
    })

    return true
end

return M
