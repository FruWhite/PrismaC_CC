local base_dir = rawget(_G, "PRISMATIC_BASE_DIR")
if not base_dir then
    local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "nullify.lua"
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

local NULLIFY_REQUIREMENTS = {
    ["kubejs:supercritical_prismatic_core"] = 1,
}

local function emit_status(cb, payload)
    if cb then
        cb(payload)
    end
end

local function read_required_color()
    local color, _, err = utils.read_crucible_color()
    if not color then
        return nil, err
    end
    return color
end

function M.run_nullify_cycle(on_status)
    emit_status(on_status, {
        phase = "precheck",
        message = "Checking nullify ingredient availability",
    })

    local ready, missing = utils.has_required_items_in_internal_storage(NULLIFY_REQUIREMENTS)
    emit_status(on_status, {
        phase = "precheck",
        ingredients_ready = ready,
        missing = missing,
        message = ready and "Ingredients ready" or "Ingredients missing",
    })
    if not ready then
        return nil, missing
    end

    local required_color, color_err = read_required_color()
    if not required_color then
        return nil, color_err
    end

    local step_label = "supercritical core -> liquid null"
    local ok, err = utils.push_item_to_input_bus("kubejs:supercritical_prismatic_core", required_color, function(readiness)
        emit_status(on_status, {
            phase = "step_wait",
            current_step = step_label,
            waiting_for = readiness.waiting_for,
            current_color = readiness.current_color,
            message = readiness.all_met and "Input conditions met" or "Waiting for input conditions",
        })
    end)
    if not ok then
        return nil, err
    end

    emit_status(on_status, {
        phase = "step_done",
        current_step = nil,
        last_step = step_label,
        message = "Nullify step submitted",
    })

    emit_status(on_status, {
        phase = "done",
        current_step = nil,
        last_step = step_label,
        ingredients_ready = true,
        message = "Nullify cycle complete",
    })
    return true
end

return M
