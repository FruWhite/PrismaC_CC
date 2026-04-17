local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "main_processing.lua"
local base_dir = fs.getDir(running_program)
_G.PRISMATIC_BASE_DIR = base_dir

local function load_local(name)
    if base_dir and base_dir ~= "" then
        return dofile(fs.combine(base_dir, name))
    end
    return dofile(name)
end

local config = load_local("config_processing.lua")
_G.PRISMATIC_CONFIG = config

local utils = load_local("utils.lua")
_G.PRISMATIC_UTILS = utils

local psoc = load_local("psoc.lua")
local prism_glass = load_local("prism_glass.lua")

local CHECK_INTERVAL = config.BUS_CHECK_INTERVAL_SECONDS or 0.1

local REQUIRED_PSOC_TRIGGER_INPUT = {
    ["kubejs:photonic_soc_inert"] = 3,
}

local REQUIRED_PRISM_GLASS_TRIGGER_INPUT = {
    ["kubejs:lyso_ce_glass"] = 1,
}

local state = {
    started = os.clock(),
    last_change = os.clock(),
    change_count = 0,
    last_snapshot = nil,
    loop_status = "booting",
    last_error = nil,
    craft = {
        phase = "idle",
        message = "Idle",
        ingredients_ready = nil,
        current_step = nil,
        last_step = nil,
        waiting_for = {},
    },
}

local monitor = utils.wrap_if_exists(config.STATUS_MONITOR)
if monitor and monitor.setTextScale then
    monitor.setTextScale(0.5)
end

local STATUS_SECTIONS = {
    { label = "input", name = config.INPUT_CONTAINER, max_items = 4 },
    {
        label = "internal",
        name = config.INTERNAL_STORAGE_CONTAINER,
        max_items = 4,
        detail_builder = utils.format_processing_internal,
    },
    { label = "inputbus", name = config.CRUCIBLE_INPUT_BUS, max_items = 4 },
    { label = "output", name = config.OUTPUT_CONTAINER, max_items = 4 },
}

local STATUS_RENDER_OPTS = {
    title = "PrismaticCrucible processing status",
    state = state,
    config = config,
    sections = STATUS_SECTIONS,
    monitor_ok = monitor ~= nil,
    target = monitor or term,
    max_items_default = 4,
}

local function run_once_if_ready(input)
    if next(input.list()) == nil then
        state.loop_status = "waiting input"
        utils.update_craft_state(state, {
            phase = "idle",
            message = "No input items",
            waiting_for = {},
        })
        return
    end

    if utils.has_required_batch(input, REQUIRED_PSOC_TRIGGER_INPUT) then
        state.loop_status = "importing psoc batch"
        local moved, move_err = utils.import_batch_to_internal(
            input,
            config.INTERNAL_STORAGE_CONTAINER,
            REQUIRED_PSOC_TRIGGER_INPUT
        )
        if not moved then
            state.last_error = "PSOC import failed: " .. tostring(move_err)
            state.loop_status = "import failed"
            return
        end

        state.last_error = nil
        state.loop_status = "running psoc cycle"
        local ok, cycle_err = psoc.run_psoc_cycle(function(payload)
            utils.update_craft_state(state, payload)
            utils.render_status(STATUS_RENDER_OPTS)
        end)
        if not ok then
            state.last_error = "PSOC cycle failed: " .. tostring(cycle_err)
            state.loop_status = "cycle failed"
            return
        end

        state.last_error = nil
        state.loop_status = "psoc cycle complete"
        utils.update_craft_state(state, {
            phase = "done",
            message = "PSOC cycle complete",
            waiting_for = {},
        })
        return
    end

    if utils.has_required_batch(input, REQUIRED_PRISM_GLASS_TRIGGER_INPUT) then
        state.loop_status = "importing prism batch"
        local moved, move_err = utils.import_batch_to_internal(
            input,
            config.INTERNAL_STORAGE_CONTAINER,
            REQUIRED_PRISM_GLASS_TRIGGER_INPUT
        )
        if not moved then
            state.last_error = "Prism import failed: " .. tostring(move_err)
            state.loop_status = "import failed"
            return
        end

        state.last_error = nil
        state.loop_status = "running prism glass cycle"
        local ok, cycle_err = prism_glass.run_blue_aligned_glass_cycle(function(payload)
            utils.update_craft_state(state, payload)
            utils.render_status(STATUS_RENDER_OPTS)
        end)
        if not ok then
            state.last_error = "Prism glass cycle failed: " .. tostring(cycle_err)
            state.loop_status = "cycle failed"
            return
        end

        state.last_error = nil
        state.loop_status = "prism glass cycle complete"
        utils.update_craft_state(state, {
            phase = "done",
            message = "Blue aligned glass cycle complete",
            waiting_for = {},
        })
        return
    end

    state.loop_status = "waiting complete input batch"
    utils.update_craft_state(state, {
        phase = "idle",
        message = "Need photonic_soc_inert x3 or lyso_ce_glass x1 in input",
        waiting_for = {},
    })
end

local function main()
    local input = utils.get_inventory(config.INPUT_CONTAINER)
    if type(input.pushItems) ~= "function" then
        error(("peripheral '%s' cannot push items (missing pushItems method)"):format(config.INPUT_CONTAINER), 2)
    end

    local active_mode = utils.is_trigger_on(config.AE2_CRAFT_EMITTER_SIDE)
    state.loop_status = active_mode and "wake" or "sleep"
    utils.render_status(STATUS_RENDER_OPTS)

    while true do
        if not active_mode then
            -- Sleep mode: wait only for rising edge.
            local event = { os.pullEvent("redstone") }
            if event[1] == "redstone" and utils.is_trigger_on(config.AE2_CRAFT_EMITTER_SIDE) then
                active_mode = true
                state.loop_status = "wake"
                utils.render_status(STATUS_RENDER_OPTS)
            end
        else
            -- Wake mode: keep checking input and crafting while trigger stays ON.
            run_once_if_ready(input)
            utils.render_status(STATUS_RENDER_OPTS)

            if not utils.is_trigger_on(config.AE2_CRAFT_EMITTER_SIDE) then
                active_mode = false
                state.loop_status = "sleep"
                utils.render_status(STATUS_RENDER_OPTS)
            else
                sleep(CHECK_INTERVAL)
            end
        end
    end
end

main()
