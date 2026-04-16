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

function M.run_psoc_cycle(on_status)
    local ready, missing = utils.check_cycle_requirements(
        PSOC_REQUIREMENTS,
        on_status,
        "Checking PSOC ingredients"
    )
    if not ready then
        return nil, missing
    end

    local ok, err, last_step = utils.run_sequence_steps(PSOC_SEQUENCE, on_status, {
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
        "psoc cycle finished on"
    )
    if not ok then
        return nil, err
    end

    utils.emit_status(on_status, {
        phase = "output_move",
        current_step = nil,
        last_step = last_step,
        message = "Moving active PSOC x3 to output container",
    })

    for _ = 1, 3 do
        local moved, move_err = utils.push_one_item_by_name(
            config.INTERNAL_STORAGE_CONTAINER,
            config.OUTPUT_CONTAINER,
            "kubejs:photonic_soc_active"
        )
        if not moved then
            return nil, move_err
        end
    end

    utils.emit_status(on_status, {
        phase = "done",
        current_step = nil,
        last_step = last_step,
        ingredients_ready = true,
        message = "PSOC cycle complete",
    })
    return true
end

return M
