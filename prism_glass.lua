local base_dir = rawget(_G, "PRISMATIC_BASE_DIR")
if not base_dir then
    local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "prism_glass.lua"
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

local BLUE_GLASS_REQUIREMENTS = {
    ["kubejs:lyso_ce_glass"] = 1,
    ["kubejs:red_aligned_glass"] = 1,
    ["kubejs:green_aligned_glass"] = 1,
}

local BLUE_GLASS_SEQUENCE = {
    { item = "kubejs:lyso_ce_glass", color = "red", label = "lyso_ce_glass @ red -> red_aligned" },
    { item = "kubejs:green_aligned_glass", color = "blue", label = "green_aligned @ blue -> blue_aligned" },
    { item = "kubejs:red_aligned_glass", color = "green", label = "red_aligned @ green -> green_aligned" },
}

function M.run_blue_aligned_glass_cycle(on_status)
    local ready, missing = utils.check_cycle_requirements(
        BLUE_GLASS_REQUIREMENTS,
        on_status,
        "Checking blue aligned glass ingredients"
    )
    if not ready then
        return nil, missing
    end

    local ok, err, last_step = utils.run_sequence_steps(BLUE_GLASS_SEQUENCE, on_status, {
        wait_idle_after_push = false,
        include_step_index = false,
    })
    if not ok then
        return nil, err
    end

    ok, err = utils.wait_for_final_color(
        "red",
        FINAL_COLOR_SETTLE_SECONDS,
        on_status,
        last_step,
        "prism glass cycle finished on"
    )
    if not ok then
        return nil, err
    end

    utils.emit_status(on_status, {
        phase = "output_move",
        current_step = nil,
        last_step = last_step,
        message = "Moving blue aligned glass to output container",
    })

    local moved, move_err = utils.push_one_item_by_name(
        config.INTERNAL_STORAGE_CONTAINER,
        config.OUTPUT_CONTAINER,
        "kubejs:blue_aligned_glass"
    )
    if not moved then
        return nil, move_err
    end

    utils.emit_status(on_status, {
        phase = "done",
        current_step = nil,
        last_step = last_step,
        ingredients_ready = true,
        message = "Blue aligned glass cycle complete",
    })
    return true
end

return M
