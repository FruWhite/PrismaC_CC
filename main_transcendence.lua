local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "main_transcendence.lua"
local base_dir = fs.getDir(running_program)
_G.PRISMATIC_BASE_DIR = base_dir

local function load_local(name)
    if base_dir and base_dir ~= "" then
        return dofile(fs.combine(base_dir, name))
    end
    return dofile(name)
end

local config = load_local("config_transcendence.lua")
_G.PRISMATIC_CONFIG = config

local utils = load_local("utils.lua")
_G.PRISMATIC_UTILS = utils

local active_core = load_local("active_core.lua")
local supercritical_core = load_local("supercritical_core.lua")
local nullify = load_local("nullify.lua")

local CHECK_INTERVAL = config.BUS_CHECK_INTERVAL_SECONDS or 0.1

local REQUIRED_ACTIVE_TRIGGER_INPUT = {
    ["kubejs:inert_prismatic_core"] = 1,
    ["kubejs:chromatic_stabilizer"] = 3,
}

local REQUIRED_SUPER_TRIGGER_INPUT = {
    ["kubejs:inert_prismatic_core"] = 1,
    ["kubejs:chromatic_stabilizer"] = 3,
}

local REQUIRED_NULLIFY_TRIGGER_INPUT = {
    ["kubejs:supercritical_prismatic_core"] = 1,
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
    { label = "active-in", name = config.ACTIVE_CORE_INPUT_CONTAINER, max_items = 3 },
    { label = "super-in", name = config.SUPERCRITICAL_CORE_INPUT_CONTAINER, max_items = 3 },
    { label = "internal", name = config.INTERNAL_STORAGE_CONTAINER, max_items = 3 },
    { label = "inputbus", name = config.CRUCIBLE_INPUT_BUS, max_items = 3 },
    { label = "output", name = config.OUTPUT_CONTAINER, max_items = 3 },
}

local STATUS_RENDER_OPTS = {
    title = "PrismaticCrucible main status",
    state = state,
    config = config,
    sections = STATUS_SECTIONS,
    monitor_ok = monitor ~= nil,
    target = monitor or term,
    max_items_default = 3,
}

local function run_once_if_ready(active_input, super_input)
    local active_has_any = next(active_input.list()) ~= nil
    local super_has_any = next(super_input.list()) ~= nil
    if not active_has_any and not super_has_any then
        state.loop_status = "waiting input"
        utils.update_craft_state(state, {
            phase = "idle",
            message = "No input items",
            waiting_for = {},
        })
        return
    end

    if super_has_any and utils.has_required_batch(super_input, REQUIRED_NULLIFY_TRIGGER_INPUT) then
        state.loop_status = "importing nullify batch"
        local moved, move_err = utils.import_batch_to_internal(
            super_input,
            config.INTERNAL_STORAGE_CONTAINER,
            REQUIRED_NULLIFY_TRIGGER_INPUT
        )
        if not moved then
            state.last_error = "Nullify import failed: " .. tostring(move_err)
            state.loop_status = "import failed"
            return
        end

        state.last_error = nil
        state.loop_status = "running nullify cycle"
        local ok, cycle_err = nullify.run_nullify_cycle(function(payload)
            utils.update_craft_state(state, payload)
            utils.render_status(STATUS_RENDER_OPTS)
        end)
        if not ok then
            state.last_error = "Nullify cycle failed: " .. tostring(cycle_err)
            state.loop_status = "cycle failed"
            return
        end

        state.last_error = nil
        state.loop_status = "nullify cycle complete"
        utils.update_craft_state(state, {
            phase = "done",
            message = "Nullify cycle complete",
            waiting_for = {},
        })
        return
    end

    if super_has_any and utils.has_required_batch(super_input, REQUIRED_SUPER_TRIGGER_INPUT) then
        state.loop_status = "importing supercritical batch"
        local moved, move_err = utils.import_batch_to_internal(
            super_input,
            config.INTERNAL_STORAGE_CONTAINER,
            REQUIRED_SUPER_TRIGGER_INPUT
        )
        if not moved then
            state.last_error = "Super import failed: " .. tostring(move_err)
            state.loop_status = "import failed"
            return
        end

        state.last_error = nil
        state.loop_status = "running supercritical cycle"
        local ok, cycle_err = supercritical_core.run_supercritical_core_cycle(function(payload)
            utils.update_craft_state(state, payload)
            utils.render_status(STATUS_RENDER_OPTS)
        end)
        if not ok then
            state.last_error = "Supercritical cycle failed: " .. tostring(cycle_err)
            state.loop_status = "cycle failed"
            return
        end

        state.last_error = nil
        state.loop_status = "supercritical cycle complete"
        utils.update_craft_state(state, {
            phase = "done",
            message = "Supercritical cycle complete",
            waiting_for = {},
        })
        return
    end

    if active_has_any and utils.has_required_batch(active_input, REQUIRED_ACTIVE_TRIGGER_INPUT) then
        state.loop_status = "importing active batch"
        local moved, move_err = utils.import_batch_to_internal(
            active_input,
            config.INTERNAL_STORAGE_CONTAINER,
            REQUIRED_ACTIVE_TRIGGER_INPUT
        )
        if not moved then
            state.last_error = "Active import failed: " .. tostring(move_err)
            state.loop_status = "import failed"
            return
        end

        state.last_error = nil
        state.loop_status = "running active core cycle"
        local ok, cycle_err = active_core.run_active_core_cycle(function(payload)
            utils.update_craft_state(state, payload)
            utils.render_status(STATUS_RENDER_OPTS)
        end)
        if not ok then
            state.last_error = "Active core cycle failed: " .. tostring(cycle_err)
            state.loop_status = "cycle failed"
            return
        end

        state.last_error = nil
        state.loop_status = "active cycle complete"
        utils.update_craft_state(state, {
            phase = "done",
            message = "Active core cycle complete",
            waiting_for = {},
        })
        return
    end

    state.loop_status = "waiting complete input batch"
    utils.update_craft_state(state, {
        phase = "idle",
        message = "Need active(inert x1 + stab x3), super(inert x1 + stab x3), or supercritical x1(nullify)",
        waiting_for = {},
    })
end

local function main()
    local active_input = utils.get_inventory(config.ACTIVE_CORE_INPUT_CONTAINER)
    local super_input = utils.get_inventory(config.SUPERCRITICAL_CORE_INPUT_CONTAINER)
    if type(active_input.pushItems) ~= "function" then
        error(("peripheral '%s' cannot push items (missing pushItems method)"):format(config.ACTIVE_CORE_INPUT_CONTAINER), 2)
    end
    if type(super_input.pushItems) ~= "function" then
        error(("peripheral '%s' cannot push items (missing pushItems method)"):format(config.SUPERCRITICAL_CORE_INPUT_CONTAINER), 2)
    end

    local active_mode = utils.is_trigger_on(config.AE2_CRAFT_TRIGGER_SIDE)
    state.loop_status = active_mode and "wake" or "sleep"
    utils.render_status(STATUS_RENDER_OPTS)

    while true do
        if not active_mode then
            -- Sleep mode: wait only for rising edge.
            local event = { os.pullEvent("redstone") }
            if event[1] == "redstone" and utils.is_trigger_on(config.AE2_CRAFT_TRIGGER_SIDE) then
                active_mode = true
                state.loop_status = "wake"
                utils.render_status(STATUS_RENDER_OPTS)
            end
        else
            -- Wake mode: keep checking input and crafting while trigger stays ON.
            run_once_if_ready(active_input, super_input)
            utils.render_status(STATUS_RENDER_OPTS)

            if not utils.is_trigger_on(config.AE2_CRAFT_TRIGGER_SIDE) then
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
