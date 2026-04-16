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
local OPENING_STEPS = {
    { item = "kubejs:chromatic_capacitor_empty", color = "magenta", label = "charge magenta capacitor" },
    { item = "kubejs:blue_prismatic_core", color = "magenta", label = "blue @ magenta" },
    { item = "kubejs:cyan_prismatic_core", color = "blue", label = "cyan @ blue" },
    { item = "kubejs:chromatic_capacitor_magenta", color = "red", label = "discharge magenta capacitor to pink" },
    { item = "kubejs:indigo_prismatic_core", color = "pink", label = "indigo @ pink -> supercritical" },
}

local B_BRANCH_STEPS = {
    { item = "kubejs:lime_prismatic_core", color = "teal", label = "lime @ teal (random B)" },
}

local B_AFTER_STEPS = {
    { item = "kubejs:chromatic_capacitor_empty", color = "cyan", label = "charge cyan capacitor" },
    { item = "kubejs:green_prismatic_core", color = "cyan", label = "green @ cyan" },
    { item = "kubejs:yellow_prismatic_core", color = "green", label = "yellow @ green" },
    { item = "kubejs:chromatic_capacitor_cyan", color = "blue", label = "discharge cyan capacitor to azure" },
}

local A_BRANCH_STEPS = {
    { item = "kubejs:teal_prismatic_core", color = "azure", label = "teal @ azure" },
    { item = "kubejs:active_prismatic_core", color = "orange", label = "active @ orange (random A)" },
}

local A_AFTER_STEPS = {
    { item = "kubejs:chromatic_capacitor_empty", color = "yellow", label = "charge yellow capacitor" },
    { item = "kubejs:red_prismatic_core", color = "yellow", label = "red @ yellow" },
    { item = "kubejs:inert_prismatic_core", color = "red", label = "inert @ red" },
    { item = "kubejs:chromatic_capacitor_yellow", color = "green", label = "discharge yellow capacitor to lime" },
}

local C_BRANCH_STEPS = {
    { item = "kubejs:orange_prismatic_core", color = "lime", label = "orange @ lime" },
    { item = "kubejs:azure_prismatic_core", color = "indigo", label = "azure @ indigo (random C)" },
}

local function wait_until_idle(on_status, last_step)
    while utils.is_crucible_working() do
        utils.emit_status(on_status, {
            phase = "step_processing",
            last_step = last_step,
            waiting_for = { "crucible not working" },
            message = "Waiting for crucible to finish step",
        })
        sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
    end
end

local function run_step(item_name, required_color, on_status, step_label, last_step)
    utils.emit_status(on_status, {
        phase = "step_wait",
        current_step = step_label,
        last_step = last_step,
        waiting_for = {},
        message = "Waiting for input conditions",
    })

    local ok, err = utils.push_item_to_input_bus(item_name, required_color, function(readiness)
        utils.emit_status(on_status, {
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

    utils.emit_status(on_status, {
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
        utils.emit_status(on_status, {
            phase = "random_settle",
            last_step = last_step,
            current_color = color,
            waiting_for = { "color in {" .. table.concat(expected, "/") .. "}" },
            message = "Waiting random branch color settle",
        })
        sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
    end
end

local function run_steps(step_fn, steps)
    for _, s in ipairs(steps) do
        local ok, err = step_fn(s.item, s.color, s.label)
        if not ok then
            return nil, err
        end
    end
    return true
end

function M.run_supercritical_core_cycle(on_status)
    local ready, missing = utils.check_cycle_requirements(
        config.SUPERCRITICAL_CORE_STORAGE_REQUIREMENTS,
        on_status,
        "Checking supercritical ingredient availability"
    )
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
        utils.emit_status(on_status, {
            phase = "step_done",
            current_step = nil,
            last_step = last_step,
            message = "Step finished",
        })
        return true
    end

    -- Opening sequence
    local ok, err = run_steps(step, OPENING_STEPS)
    if not ok then return nil, err end

    -- B branch
    ok, err = run_steps(step, B_BRANCH_STEPS)
    if not ok then return nil, err end
    color, color_err = wait_for_color_in({ blue = true, cyan = true }, "B", on_status, last_step)
    if not color then return nil, color_err end
    if color == "blue" then
        ok, err = step("kubejs:chromatic_stabilizer", "blue", "stabilizer blue->cyan")
        if not ok then return nil, err end
    end
    ok, err = run_steps(step, B_AFTER_STEPS)
    if not ok then return nil, err end

    -- A branch
    ok, err = run_steps(step, A_BRANCH_STEPS)
    if not ok then return nil, err end
    color, color_err = wait_for_color_in({ green = true, yellow = true }, "A", on_status, last_step)
    if not color then return nil, color_err end
    if color == "green" then
        ok, err = step("kubejs:chromatic_stabilizer", "green", "stabilizer green->yellow")
        if not ok then return nil, err end
    end
    ok, err = run_steps(step, A_AFTER_STEPS)
    if not ok then return nil, err end

    -- Ending C branch
    ok, err = run_steps(step, C_BRANCH_STEPS)
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
    utils.emit_status(on_status, {
        phase = "output_move",
        current_step = nil,
        last_step = last_step,
        message = "Moving supercritical core to output",
    })
    local moved, move_err = utils.push_one_item_by_name(
        config.INTERNAL_STORAGE_CONTAINER,
        config.OUTPUT_CONTAINER,
        "kubejs:supercritical_prismatic_core"
    )
    if not moved then
        return nil, move_err
    end

    local extra_stabs = utils.push_all_item_by_name(
        config.INTERNAL_STORAGE_CONTAINER,
        config.OUTPUT_CONTAINER,
        "kubejs:chromatic_stabilizer"
    )

    utils.emit_status(on_status, {
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
