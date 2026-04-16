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

local function format_step(step)
    return ("%s @ %s"):format(step.item, step.color)
end

function M.run_active_core_cycle(on_status)
    local ready, missing = utils.check_cycle_requirements(
        config.ACTIVE_CORE_STORAGE_REQUIREMENTS,
        on_status,
        "Checking active core ingredient availability"
    )
    if not ready then
        return nil, missing
    end

    local ok, err, last_step = utils.run_sequence_steps(ACTIVE_CORE_SEQUENCE, on_status, {
        wait_idle_after_push = true,
        include_step_index = true,
        format_step = format_step,
    })
    if not ok then
        return nil, err
    end

    ok, err = utils.wait_for_final_color(
        "magenta",
        FINAL_COLOR_SETTLE_SECONDS,
        on_status,
        last_step,
        "cycle finished on"
    )
    if not ok then
        return nil, err
    end

    utils.emit_status(on_status, {
        phase = "output_move",
        current_step = nil,
        last_step = last_step,
        message = "Moving active core to output container",
    })

    local moved, move_err = utils.push_one_item_by_name(
        config.INTERNAL_STORAGE_CONTAINER,
        config.OUTPUT_CONTAINER,
        "kubejs:active_prismatic_core"
    )
    if not moved then
        return nil, move_err
    end

    utils.emit_status(on_status, {
        phase = "done",
        current_step = nil,
        last_step = last_step,
        ingredients_ready = true,
        message = "Active core cycle complete",
    })

    return true
end

return M
