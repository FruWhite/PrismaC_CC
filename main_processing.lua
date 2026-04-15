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

local function read_analog_input(side)
    if redstone.getAnalogInput then
        return redstone.getAnalogInput(side)
    end
    return redstone.getAnalogueInput(side)
end

local function wrap_if_exists(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return peripheral.wrap(name)
end

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

local monitor = wrap_if_exists(config.STATUS_MONITOR)
if monitor and monitor.setTextScale then
    monitor.setTextScale(0.5)
end

local function inventory_status(peripheral_name)
    local inv = wrap_if_exists(peripheral_name)
    if not inv or type(inv.list) ~= "function" then
        return {
            ok = false,
            slots = 0,
            total = 0,
            by_name = {},
        }
    end

    local slots_used = 0
    local total_items = 0
    local by_name = {}
    for _, stack in pairs(inv.list()) do
        slots_used = slots_used + 1
        total_items = total_items + stack.count
        by_name[stack.name] = (by_name[stack.name] or 0) + stack.count
    end

    return {
        ok = true,
        slots = slots_used,
        total = total_items,
        by_name = by_name,
    }
end

local function top_items_text(status, max_items)
    if not status.ok then
        return "n/a"
    end

    local names = {}
    for item_name, _ in pairs(status.by_name) do
        names[#names + 1] = item_name
    end
    table.sort(names)

    if #names == 0 then
        return "(empty)"
    end

    local parts = {}
    local limit = math.min(#names, max_items)
    for i = 1, limit do
        local name = names[i]
        parts[#parts + 1] = ("%s:%d"):format(name, status.by_name[name])
    end
    if #names > max_items then
        parts[#parts + 1] = ("... +%d more"):format(#names - max_items)
    end
    return table.concat(parts, " | ")
end

local function bool_text(v)
    if v then
        return "OK"
    end
    return "MISSING"
end

local function write_lines(lines)
    local target = monitor or term
    target.setBackgroundColor(colors.black)
    target.setTextColor(colors.white)
    target.clear()
    target.setCursorPos(1, 1)

    for i = 1, #lines do
        target.write(lines[i])
        if i < #lines then
            local _, h = target.getSize()
            local _, y = target.getCursorPos()
            if y < h then
                target.setCursorPos(1, y + 1)
            end
        end
    end
end

local function count_item_in_inventory(inv, item_name)
    local total = 0
    for _, stack in pairs(inv.list()) do
        if stack.name == item_name then
            total = total + stack.count
        end
    end
    return total
end

local function has_required_batch(container, requirements)
    for item_name, needed in pairs(requirements) do
        if count_item_in_inventory(container, item_name) < needed then
            return false
        end
    end
    return true
end

local function move_item_amount_by_name(source_inv, target_name, item_name, amount)
    local remaining = amount
    local snapshot = source_inv.list()

    for slot, stack in pairs(snapshot) do
        if remaining <= 0 then
            break
        end
        if stack.name == item_name and stack.count > 0 then
            local moved = source_inv.pushItems(target_name, slot, remaining)
            remaining = remaining - (moved or 0)
        end
    end

    if remaining > 0 then
        return nil, ("failed moving %s x%d (missing %d)"):format(item_name, amount, remaining)
    end
    return true
end

local function import_batch_to_internal(source_input, requirements)
    for item_name, needed in pairs(requirements) do
        local ok, err = move_item_amount_by_name(
            source_input,
            config.INTERNAL_STORAGE_CONTAINER,
            item_name,
            needed
        )
        if not ok then
            return nil, err
        end
    end
    return true
end

local function is_trigger_on()
    local side = config.AE2_CRAFT_TRIGGER_SIDE
    if type(side) ~= "string" or side == "" then
        error("AE2_CRAFT_TRIGGER_SIDE must be a non-empty string", 2)
    end
    return read_analog_input(side) > 0
end

local function update_craft_state(payload)
    for key, value in pairs(payload) do
        state.craft[key] = value
    end
end

local function render_status()
    local input = inventory_status(config.INPUT_CONTAINER)
    local int = inventory_status(config.INTERNAL_STORAGE_CONTAINER)
    local bus = inventory_status(config.CRUCIBLE_INPUT_BUS)
    local out = inventory_status(config.OUTPUT_CONTAINER)

    local chroma_signal = read_analog_input(config.DEFAULT_CHROMA_SENSOR_SIDE)
    local chroma_color = utils.decode_chroma_sensor_signal(chroma_signal) or "invalid"
    local working_signal = read_analog_input(config.CRUCIBLE_WORKING_SIGNAL_SIDE)
    local trigger_signal = read_analog_input(config.AE2_CRAFT_TRIGGER_SIDE)

    local waiting_for = state.craft.waiting_for
    local waiting_text = "none"
    if type(waiting_for) == "table" and #waiting_for > 0 then
        waiting_text = table.concat(waiting_for, "; ")
    end

    local lines = {
        "PrismaticCrucible processing status",
        ("uptime: %.1fs  changes: %d"):format(os.clock() - state.started, state.change_count),
        ("last change: %.1fs ago"):format(os.clock() - state.last_change),
        ("loop: %s"):format(state.loop_status),
        ("error: %s"):format(state.last_error or "none"),
        "",
        ("monitor(%s): %s"):format(tostring(config.STATUS_MONITOR), bool_text(monitor ~= nil)),
        ("input(%s): %s slots=%d items=%d"):format(config.INPUT_CONTAINER, bool_text(input.ok), input.slots, input.total),
        ("  ids/counts: %s"):format(top_items_text(input, 4)),
        ("internal(%s): %s slots=%d items=%d"):format(config.INTERNAL_STORAGE_CONTAINER, bool_text(int.ok), int.slots, int.total),
        ("  ids/counts: %s"):format(top_items_text(int, 4)),
        ("inputbus(%s): %s slots=%d items=%d"):format(config.CRUCIBLE_INPUT_BUS, bool_text(bus.ok), bus.slots, bus.total),
        ("  ids/counts: %s"):format(top_items_text(bus, 4)),
        ("output(%s): %s slots=%d items=%d"):format(config.OUTPUT_CONTAINER, bool_text(out.ok), out.slots, out.total),
        ("  ids/counts: %s"):format(top_items_text(out, 4)),
        "",
        ("chroma side=%s  signal=%d  color=%s"):format(config.DEFAULT_CHROMA_SENSOR_SIDE, chroma_signal, chroma_color),
        ("working side=%s signal=%d  state=%s"):format(
            config.CRUCIBLE_WORKING_SIGNAL_SIDE,
            working_signal,
            working_signal > 0 and "WORKING" or "IDLE"
        ),
        ("trigger side=%s signal=%d  state=%s"):format(
            config.AE2_CRAFT_TRIGGER_SIDE,
            trigger_signal,
            trigger_signal > 0 and "ON" or "OFF"
        ),
        "",
        ("craft phase: %s"):format(state.craft.phase or "unknown"),
        ("ingredients ready: %s"):format(
            state.craft.ingredients_ready == nil and "n/a" or tostring(state.craft.ingredients_ready)
        ),
        ("current step: %s"):format(state.craft.current_step or "none"),
        ("last step: %s"):format(state.craft.last_step or "none"),
        ("waiting for: %s"):format(waiting_text),
        ("craft msg: %s"):format(state.craft.message or "none"),
    }

    local snapshot = table.concat(lines, "\n")
    if snapshot ~= state.last_snapshot then
        state.change_count = state.change_count + 1
        state.last_change = os.clock()
        state.last_snapshot = snapshot
    end

    write_lines(lines)
end

local function run_once_if_ready(input)
    if next(input.list()) == nil then
        state.loop_status = "waiting input"
        update_craft_state({
            phase = "idle",
            message = "No input items",
            waiting_for = {},
        })
        return
    end

    if has_required_batch(input, REQUIRED_PSOC_TRIGGER_INPUT) then
        state.loop_status = "importing psoc batch"
        local moved, move_err = import_batch_to_internal(input, REQUIRED_PSOC_TRIGGER_INPUT)
        if not moved then
            state.last_error = "PSOC import failed: " .. tostring(move_err)
            state.loop_status = "import failed"
            return
        end

        state.last_error = nil
        state.loop_status = "running psoc cycle"
        local ok, cycle_err = psoc.run_psoc_cycle(function(payload)
            update_craft_state(payload)
            render_status()
        end)
        if not ok then
            state.last_error = "PSOC cycle failed: " .. tostring(cycle_err)
            state.loop_status = "cycle failed"
            return
        end

        state.last_error = nil
        state.loop_status = "psoc cycle complete"
        update_craft_state({
            phase = "done",
            message = "PSOC cycle complete",
            waiting_for = {},
        })
        return
    end

    if has_required_batch(input, REQUIRED_PRISM_GLASS_TRIGGER_INPUT) then
        state.loop_status = "importing prism batch"
        local moved, move_err = import_batch_to_internal(input, REQUIRED_PRISM_GLASS_TRIGGER_INPUT)
        if not moved then
            state.last_error = "Prism import failed: " .. tostring(move_err)
            state.loop_status = "import failed"
            return
        end

        state.last_error = nil
        state.loop_status = "running prism glass cycle"
        local ok, cycle_err = prism_glass.run_blue_aligned_glass_cycle(function(payload)
            update_craft_state(payload)
            render_status()
        end)
        if not ok then
            state.last_error = "Prism glass cycle failed: " .. tostring(cycle_err)
            state.loop_status = "cycle failed"
            return
        end

        state.last_error = nil
        state.loop_status = "prism glass cycle complete"
        update_craft_state({
            phase = "done",
            message = "Blue aligned glass cycle complete",
            waiting_for = {},
        })
        return
    end

    state.loop_status = "waiting complete input batch"
    update_craft_state({
        phase = "idle",
        message = "Need photonic_soc_inert x3 or lyso_ce_glass x1 in input",
        waiting_for = {},
    })
end

local function main()
    local input = get_inventory(config.INPUT_CONTAINER)
    if type(input.pushItems) ~= "function" then
        error(("peripheral '%s' cannot push items (missing pushItems method)"):format(config.INPUT_CONTAINER), 2)
    end

    local active_mode = is_trigger_on()
    state.loop_status = active_mode and "wake" or "sleep"
    render_status()

    while true do
        if not active_mode then
            -- Sleep mode: wait only for rising edge.
            local event = { os.pullEvent("redstone") }
            if event[1] == "redstone" and is_trigger_on() then
                active_mode = true
                state.loop_status = "wake"
                render_status()
            end
        else
            -- Wake mode: keep checking input and crafting while trigger stays ON.
            run_once_if_ready(input)
            render_status()

            if not is_trigger_on() then
                active_mode = false
                state.loop_status = "sleep"
                render_status()
            else
                sleep(CHECK_INTERVAL)
            end
        end
    end
end

main()
