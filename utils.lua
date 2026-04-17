local M = {}
local base_dir = rawget(_G, "PRISMATIC_BASE_DIR")
if not base_dir then
    local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "utils.lua"
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

M.DEFAULT_CHROMA_SENSOR_SIDE = config.DEFAULT_CHROMA_SENSOR_SIDE
M.CRUCIBLE_WORKING_SIGNAL_SIDE = config.CRUCIBLE_WORKING_SIGNAL_SIDE
M.BUS_CHECK_INTERVAL_SECONDS = config.BUS_CHECK_INTERVAL_SECONDS or 0.1
M.ACTIVE_CORE_INPUT_CONTAINER = config.ACTIVE_CORE_INPUT_CONTAINER
M.SUPERCRITICAL_CORE_INPUT_CONTAINER = config.SUPERCRITICAL_CORE_INPUT_CONTAINER
M.INTERNAL_STORAGE_CONTAINER = config.INTERNAL_STORAGE_CONTAINER
M.CRUCIBLE_INPUT_BUS = config.CRUCIBLE_INPUT_BUS
M.PRISMATIC_COLOR_BY_SIGNAL = config.PRISMATIC_COLOR_BY_SIGNAL

function M.read_analog_input(side)
    if type(side) ~= "string" or side == "" then
        error("redstone side must be a non-empty string", 2)
    end
    if redstone.getAnalogInput then
        return redstone.getAnalogInput(side)
    end
    return redstone.getAnalogueInput(side)
end

function M.wrap_if_exists(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return peripheral.wrap(name)
end

function M.get_inventory(name)
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

function M.count_item_in_inventory(inv, item_name)
    if type(inv) ~= "table" or type(inv.list) ~= "function" then
        error("inv must be an inventory peripheral", 2)
    end
    if type(item_name) ~= "string" or item_name == "" then
        error("item_name must be a non-empty string", 2)
    end

    local total = 0
    for _, stack in pairs(inv.list()) do
        if stack.name == item_name then
            total = total + stack.count
        end
    end
    return total
end

function M.has_required_batch(container, requirements)
    if type(container) ~= "table" or type(container.list) ~= "function" then
        error("container must be an inventory peripheral", 2)
    end
    if type(requirements) ~= "table" then
        error("requirements must be a table", 2)
    end

    for item_name, needed in pairs(requirements) do
        if M.count_item_in_inventory(container, item_name) < needed then
            return false
        end
    end
    return true
end

function M.move_item_amount_by_name(source_inv, target_name, item_name, amount)
    if type(source_inv) ~= "table" or type(source_inv.list) ~= "function" then
        error("source_inv must be an inventory peripheral", 2)
    end
    if type(source_inv.pushItems) ~= "function" then
        error("source_inv must support pushItems", 2)
    end
    if type(target_name) ~= "string" or target_name == "" then
        error("target_name must be a non-empty string", 2)
    end
    if type(item_name) ~= "string" or item_name == "" then
        error("item_name must be a non-empty string", 2)
    end
    if type(amount) ~= "number" or amount < 1 then
        error("amount must be a number >= 1", 2)
    end

    local remaining = math.floor(amount)
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

function M.import_batch_to_internal(source_input, target_name, requirements)
    if type(source_input) ~= "table" or type(source_input.list) ~= "function" or type(source_input.pushItems) ~= "function" then
        error("source_input must be an inventory peripheral with pushItems", 2)
    end
    if type(target_name) ~= "string" or target_name == "" then
        error("target_name must be a non-empty string", 2)
    end
    if type(requirements) ~= "table" then
        error("requirements must be a table", 2)
    end

    for item_name, needed in pairs(requirements) do
        local ok, err = M.move_item_amount_by_name(source_input, target_name, item_name, needed)
        if not ok then
            return nil, err
        end
    end
    return true
end

function M.is_signal_on(side)
    return M.read_analog_input(side) > 0
end

function M.inventory_status(peripheral_name)
    local inv = M.wrap_if_exists(peripheral_name)
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

function M.top_items_text(status, max_items)
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

local PRISMATIC_COLOR_ORDER = {
    "red", "orange", "yellow", "lime", "green", "teal",
    "cyan", "azure", "blue", "indigo", "magenta", "pink",
}

local function join_count_parts(parts)
    if #parts == 0 then
        return "none"
    end
    return table.concat(parts, "; ")
end

local function count_parts_in_order(order, counts)
    local parts = {}
    for _, key in ipairs(order) do
        local amount = counts[key]
        if amount and amount > 0 then
            parts[#parts + 1] = ("%s %d"):format(key, amount)
        end
    end
    return parts
end

function M.format_transcendence_internal(status)
    local by_name = status.by_name or {}
    local core_counts = { inert = 0 }
    local capacitor_counts = { empty = 0 }
    local stabilizers = 0

    for item_name, amount in pairs(by_name) do
        if item_name == "kubejs:chromatic_stabilizer" then
            stabilizers = stabilizers + amount
        elseif item_name == "kubejs:inert_prismatic_core" then
            core_counts.inert = core_counts.inert + amount
        else
            local core_name = item_name:match("^kubejs:([a-z_]+)_prismatic_core$")
            if core_name then
                core_counts[core_name] = (core_counts[core_name] or 0) + amount
            else
                local cap_name = item_name:match("^kubejs:chromatic_capacitor_([a-z_]+)$")
                if cap_name then
                    if cap_name == "empty" then
                        capacitor_counts.empty = (capacitor_counts.empty or 0) + amount
                    else
                        capacitor_counts[cap_name] = (capacitor_counts[cap_name] or 0) + amount
                    end
                end
            end
        end
    end

    local core_order_line_1 = { "inert", "red", "orange", "yellow", "lime", "green", "teal" }
    local core_order_line_2 = { "cyan", "azure", "blue", "indigo", "magenta", "pink", "active", "supercritical" }

    local capacitor_order = { "empty" }
    for _, color in ipairs(PRISMATIC_COLOR_ORDER) do
        capacitor_order[#capacitor_order + 1] = color
    end

    local core_parts_1 = count_parts_in_order(core_order_line_1, core_counts)
    local core_parts_2 = count_parts_in_order(core_order_line_2, core_counts)
    local capacitor_parts = count_parts_in_order(capacitor_order, capacitor_counts)

    local lines = {
        ("  cores: %s"):format(join_count_parts(core_parts_1)),
    }
    if #core_parts_2 > 0 then
        lines[#lines + 1] = ("         %s"):format(join_count_parts(core_parts_2))
    end
    lines[#lines + 1] = ("  stabilizers: %d"):format(stabilizers)
    lines[#lines + 1] = ("  capacitors: %s"):format(join_count_parts(capacitor_parts))
    return lines
end

function M.format_processing_internal(status)
    local by_name = status.by_name or {}
    local glass_counts = {}
    local psoc_counts = {}

    for item_name, amount in pairs(by_name) do
        local glass_name = item_name:match("^kubejs:([a-z_]+)_aligned_glass$")
        if glass_name then
            glass_counts[glass_name] = (glass_counts[glass_name] or 0) + amount
        elseif item_name == "kubejs:lyso_ce_glass" then
            glass_counts.lyso = (glass_counts.lyso or 0) + amount
        else
            local psoc_name = item_name:match("^kubejs:photonic_soc_([a-z_]+)$")
            if psoc_name then
                psoc_counts[psoc_name] = (psoc_counts[psoc_name] or 0) + amount
            end
        end
    end

    local glass_order = { "lyso", "red", "yellow", "green", "cyan", "blue", "magenta" }
    local psoc_order = { "inert", "red", "yellow", "green", "cyan", "blue", "magenta", "active" }

    local glass_parts = count_parts_in_order(glass_order, glass_counts)
    local psoc_parts = count_parts_in_order(psoc_order, psoc_counts)

    return {
        ("  glass: %s"):format(join_count_parts(glass_parts)),
        ("  psoc: %s"):format(join_count_parts(psoc_parts)),
    }
end

function M.bool_text(v)
    if v then
        return "OK"
    end
    return "MISSING"
end

function M.is_trigger_on(trigger_side)
    if type(trigger_side) ~= "string" or trigger_side == "" then
        error("trigger_side must be a non-empty string", 2)
    end
    return M.is_signal_on(trigger_side)
end

function M.update_craft_state(state, payload)
    if type(state) ~= "table" then
        error("state must be a table", 2)
    end
    if type(payload) ~= "table" then
        error("payload must be a table", 2)
    end
    if type(state.craft) ~= "table" then
        state.craft = {}
    end
    for key, value in pairs(payload) do
        state.craft[key] = value
    end
end

function M.emit_status(cb, payload)
    if cb then
        cb(payload)
    end
end

M.TEXT_COLOR_BY_NAME = {
    red = colors.red,
    orange = colors.orange,
    yellow = colors.yellow,
    lime = colors.lime,
    green = colors.green,
    teal = colors.cyan,
    cyan = colors.cyan,
    azure = colors.lightBlue,
    blue = colors.blue,
    indigo = colors.purple,
    magenta = colors.magenta,
    pink = colors.pink,
}

function M.get_text_color_for_word(word)
    if type(word) ~= "string" or word == "" then
        return nil
    end
    return M.TEXT_COLOR_BY_NAME[string.lower(word)]
end

local function write_colorized_line(target, text, default_color)
    local cursor = 1
    while cursor <= #text do
        local s, e, word = text:find("([A-Za-z]+)", cursor)
        if not s then
            target.setTextColor(default_color)
            target.write(text:sub(cursor))
            break
        end

        if s > cursor then
            target.setTextColor(default_color)
            target.write(text:sub(cursor, s - 1))
        end

        local word_color = M.get_text_color_for_word(word) or default_color
        target.setTextColor(word_color)
        target.write(word)
        cursor = e + 1
    end
end

function M.write_lines(target, lines)
    if target == nil then
        target = term
    end
    local default_color = colors.white
    target.setBackgroundColor(colors.black)
    target.setTextColor(default_color)
    target.clear()
    target.setCursorPos(1, 1)

    for i = 1, #lines do
        write_colorized_line(target, tostring(lines[i]), default_color)
        if i < #lines then
            local _, h = target.getSize()
            local _, y = target.getCursorPos()
            if y < h then
                target.setCursorPos(1, y + 1)
            end
        end
    end
    target.setTextColor(default_color)
end

function M.render_status(opts)
    if type(opts) ~= "table" then
        error("opts must be a table", 2)
    end
    local state = opts.state
    local config = opts.config
    local sections = opts.sections
    local title = opts.title or "Status"
    local target = opts.target or term
    local max_items_default = opts.max_items_default or 3

    if type(state) ~= "table" then
        error("opts.state must be a table", 2)
    end
    if type(config) ~= "table" then
        error("opts.config must be a table", 2)
    end
    if type(sections) ~= "table" then
        error("opts.sections must be a table", 2)
    end

    local section_lines = {}
    for _, section in ipairs(sections) do
        local status = M.inventory_status(section.name)
        local label = section.label or "inventory"
        local max_items = section.max_items or max_items_default
        section_lines[#section_lines + 1] = (
            ("%s(%s): %s slots=%d items=%d"):format(
                label,
                tostring(section.name),
                M.bool_text(status.ok),
                status.slots,
                status.total
            )
        )
        if type(section.detail_builder) == "function" then
            local detail_lines = section.detail_builder(status, section)
            if type(detail_lines) == "table" then
                for _, detail in ipairs(detail_lines) do
                    section_lines[#section_lines + 1] = tostring(detail)
                end
            end
        else
            section_lines[#section_lines + 1] = ("  ids/counts: %s"):format(M.top_items_text(status, max_items))
        end
    end

    local chroma_signal = M.read_analog_input(config.DEFAULT_CHROMA_SENSOR_SIDE)
    local chroma_color = M.decode_chroma_sensor_signal(chroma_signal) or "invalid"
    local working_signal = M.read_analog_input(config.CRUCIBLE_WORKING_SIGNAL_SIDE)
    local trigger_signal = M.read_analog_input(config.AE2_CRAFT_EMITTER_SIDE)

    local waiting_for = state.craft and state.craft.waiting_for
    local waiting_text = "none"
    if type(waiting_for) == "table" and #waiting_for > 0 then
        waiting_text = table.concat(waiting_for, "; ")
    end

    local lines = {
        title,
        ("uptime: %.1fs  changes: %d"):format(os.clock() - (state.started or os.clock()), state.change_count or 0),
        ("last change: %.1fs ago"):format(os.clock() - (state.last_change or os.clock())),
        ("loop: %s"):format(state.loop_status or "unknown"),
        ("error: %s"):format(state.last_error or "none"),
        "",
        ("monitor(%s): %s"):format(tostring(config.STATUS_MONITOR), M.bool_text(opts.monitor_ok == true)),
    }

    for _, line in ipairs(section_lines) do
        lines[#lines + 1] = line
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = ("chroma side=%s  signal=%d  color=%s"):format(config.DEFAULT_CHROMA_SENSOR_SIDE, chroma_signal, chroma_color)
    lines[#lines + 1] = ("working side=%s signal=%d  state=%s"):format(
        config.CRUCIBLE_WORKING_SIGNAL_SIDE,
        working_signal,
        working_signal > 0 and "WORKING" or "IDLE"
    )
    lines[#lines + 1] = ("trigger side=%s signal=%d  state=%s"):format(
        config.AE2_CRAFT_EMITTER_SIDE,
        trigger_signal,
        trigger_signal > 0 and "ON" or "OFF"
    )
    lines[#lines + 1] = ""
    local craft = state.craft or {}
    local ingredients_ready_text = "n/a"
    if craft.ingredients_ready ~= nil then
        ingredients_ready_text = tostring(craft.ingredients_ready)
    end

    lines[#lines + 1] = ("craft phase: %s"):format(craft.phase or "unknown")
    lines[#lines + 1] = ("ingredients ready: %s"):format(ingredients_ready_text)
    lines[#lines + 1] = ("current step: %s"):format(craft.current_step or "none")
    lines[#lines + 1] = ("last step: %s"):format(craft.last_step or "none")
    lines[#lines + 1] = ("waiting for: %s"):format(waiting_text)
    lines[#lines + 1] = ("craft msg: %s"):format(craft.message or "none")

    local snapshot = table.concat(lines, "\n")
    if snapshot ~= state.last_snapshot then
        state.change_count = (state.change_count or 0) + 1
        state.last_change = os.clock()
        state.last_snapshot = snapshot
    end

    M.write_lines(target, lines)
    return lines
end

function M.decode_chroma_sensor_signal(signal)
    if type(signal) ~= "number" then
        error("signal must be a number", 2)
    end

    signal = math.floor(signal)
    local color = M.PRISMATIC_COLOR_BY_SIGNAL[signal]
    if not color then
        return nil, ("invalid chroma sensor signal %d (expected 1..12)"):format(signal)
    end

    return color
end

function M.is_crucible_working()
    local side = M.CRUCIBLE_WORKING_SIGNAL_SIDE
    if type(side) ~= "string" or side == "" then
        error("CRUCIBLE_WORKING_SIGNAL_SIDE must be a non-empty string", 2)
    end
    return M.read_analog_input(side) > 0
end

function M.read_crucible_color()
    local side = M.DEFAULT_CHROMA_SENSOR_SIDE
    if type(side) ~= "string" or side == "" then
        error("DEFAULT_CHROMA_SENSOR_SIDE must be a non-empty string", 2)
    end

    local signal = M.read_analog_input(side)
    local color, err = M.decode_chroma_sensor_signal(signal)
    if not color then
        return nil, signal, err
    end

    return color, signal
end

function M.is_crucible_input_bus_empty()
    local input_bus = M.get_inventory(M.CRUCIBLE_INPUT_BUS)
    return next(input_bus.list()) == nil
end

function M.get_input_push_readiness(required_color)
    if type(required_color) ~= "string" or required_color == "" then
        error("required_color must be a non-empty string", 2)
    end

    local normalized = string.lower(required_color)
    local working = M.is_crucible_working()
    local current_color, signal, color_err = M.read_crucible_color()
    local input_bus_empty = M.is_crucible_input_bus_empty()

    local waiting_for = {}
    if working then
        waiting_for[#waiting_for + 1] = "crucible not working"
    end
    if not current_color then
        waiting_for[#waiting_for + 1] = "valid crucible color signal"
    elseif current_color ~= normalized then
        waiting_for[#waiting_for + 1] = ("crucible color '%s' == '%s'"):format(current_color, normalized)
    end
    if not input_bus_empty then
        waiting_for[#waiting_for + 1] = "input bus empty"
    end

    return {
        required_color = normalized,
        crucible_working = working,
        current_color = current_color,
        current_signal = signal,
        color_error = color_err,
        input_bus_empty = input_bus_empty,
        waiting_for = waiting_for,
        all_met = #waiting_for == 0,
    }
end

function M.has_required_items_in_internal_storage(requirements)
    if type(requirements) ~= "table" then
        error("requirements must be a table", 2)
    end

    local required_by_name = {}

    -- Supports:
    -- 1) array style: { {"mod:item_a", 4}, {"mod:item_b", 2} }
    -- 2) map style:   { ["mod:item_a"] = 4, ["mod:item_b"] = 2 }
    for key, value in pairs(requirements) do
        local item_name, amount

        if type(key) == "number" then
            if type(value) ~= "table" then
                error("array-style requirement must be {item_name, amount}", 2)
            end
            item_name = value[1]
            amount = value[2]
        else
            item_name = key
            amount = value
        end

        if type(item_name) ~= "string" or item_name == "" then
            error("item_name in requirements must be a non-empty string", 2)
        end
        if type(amount) ~= "number" or amount < 1 then
            error(("amount for '%s' must be a number >= 1"):format(item_name), 2)
        end

        amount = math.floor(amount)
        required_by_name[item_name] = (required_by_name[item_name] or 0) + amount
    end

    local storage = M.get_inventory(M.INTERNAL_STORAGE_CONTAINER)
    local available_by_name = {}

    for _, stack in pairs(storage.list()) do
        available_by_name[stack.name] = (available_by_name[stack.name] or 0) + stack.count
    end

    local missing = {}
    for item_name, needed in pairs(required_by_name) do
        local available = available_by_name[item_name] or 0
        if available < needed then
            missing[#missing + 1] = {
                item = item_name,
                needed = needed,
                available = available,
            }
        end
    end

    if #missing > 0 then
        return false, missing
    end

    return true
end

function M.push_one_item_by_name(source_name, target_name, item_name)
    local source = M.get_inventory(source_name)
    local source_items = source.list()
    local source_slot = nil

    for slot, stack in pairs(source_items) do
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

function M.push_all_item_by_name(source_name, target_name, item_name)
    local source = M.get_inventory(source_name)
    local total = 0
    local changed = true

    while changed do
        changed = false
        for slot, stack in pairs(source.list()) do
            if stack.name == item_name and stack.count > 0 then
                local moved = source.pushItems(target_name, slot, stack.count)
                if moved and moved > 0 then
                    total = total + moved
                    changed = true
                end
            end
        end
    end

    return total
end

function M.check_cycle_requirements(requirements, on_status, checking_message)
    M.emit_status(on_status, {
        phase = "precheck",
        message = checking_message or "Checking ingredients",
    })

    local ready, missing = M.has_required_items_in_internal_storage(requirements)
    M.emit_status(on_status, {
        phase = "precheck",
        ingredients_ready = ready,
        missing = missing,
        message = ready and "Ingredients ready" or "Ingredients missing",
    })
    return ready, missing
end

function M.wait_for_final_color(expected_color, settle_seconds, on_status, last_step, error_prefix)
    if type(expected_color) ~= "string" or expected_color == "" then
        error("expected_color must be a non-empty string", 2)
    end
    if type(settle_seconds) ~= "number" or settle_seconds < 0 then
        error("settle_seconds must be a number >= 0", 2)
    end

    local deadline = os.clock() + settle_seconds
    while true do
        local color, _, err = M.read_crucible_color()
        if color == expected_color then
            return true
        end
        if os.clock() >= deadline then
            if color then
                local prefix = error_prefix or "cycle finished on"
                return nil, ("%s '%s' instead of '%s'"):format(prefix, color, expected_color)
            end
            return nil, err
        end

        M.emit_status(on_status, {
            phase = "final_color_settle",
            current_step = nil,
            last_step = last_step,
            waiting_for = { "crucible final color " .. expected_color },
            current_color = color,
            message = "Waiting for final color settle",
        })
        sleep(M.BUS_CHECK_INTERVAL_SECONDS)
    end
end

function M.run_sequence_steps(sequence, on_status, opts)
    if type(sequence) ~= "table" then
        error("sequence must be a table", 2)
    end
    opts = opts or {}
    if type(opts) ~= "table" then
        error("opts must be a table", 2)
    end

    local wait_idle_after_push = opts.wait_idle_after_push == true
    local include_step_index = opts.include_step_index == true
    local format_step = opts.format_step
    if format_step ~= nil and type(format_step) ~= "function" then
        error("opts.format_step must be a function", 2)
    end

    local last_step = opts.initial_last_step
    for index, step in ipairs(sequence) do
        local step_label = step.label
        if not step_label and format_step then
            step_label = format_step(step, index)
        end
        if not step_label then
            step_label = ("%s @ %s"):format(step.item, step.color)
        end

        local base_payload = {
            current_step = step_label,
            last_step = last_step,
        }
        if include_step_index then
            base_payload.step_index = index
        end

        M.emit_status(on_status, {
            phase = "step_wait",
            current_step = base_payload.current_step,
            last_step = base_payload.last_step,
            step_index = base_payload.step_index,
            waiting_for = {},
            message = "Waiting for input conditions",
        })

        local ok, err = M.push_item_to_input_bus(step.item, step.color, function(readiness)
            M.emit_status(on_status, {
                phase = "step_wait",
                current_step = base_payload.current_step,
                last_step = base_payload.last_step,
                step_index = base_payload.step_index,
                waiting_for = readiness.waiting_for,
                current_color = readiness.current_color,
                crucible_working = readiness.crucible_working,
                input_bus_empty = readiness.input_bus_empty,
                message = readiness.all_met and "Input conditions met" or "Waiting for input conditions",
            })
        end)
        if not ok then
            return nil, err, last_step
        end

        M.emit_status(on_status, {
            phase = "step_submitted",
            current_step = base_payload.current_step,
            last_step = base_payload.last_step,
            step_index = base_payload.step_index,
            message = "Input pushed to crucible",
        })

        if wait_idle_after_push then
            while M.is_crucible_working() do
                M.emit_status(on_status, {
                    phase = "step_processing",
                    current_step = base_payload.current_step,
                    last_step = base_payload.last_step,
                    step_index = base_payload.step_index,
                    waiting_for = { "crucible not working" },
                    message = "Waiting for crucible to finish step",
                })
                sleep(M.BUS_CHECK_INTERVAL_SECONDS)
            end
        end

        last_step = step_label
        M.emit_status(on_status, {
            phase = "step_done",
            current_step = nil,
            last_step = last_step,
            step_index = include_step_index and index or nil,
            message = "Step finished",
        })
    end

    return true, last_step
end

function M.push_item_to_input_bus(item_name, required_color, on_wait_update)
    if type(item_name) ~= "string" or item_name == "" then
        error("item_name must be a non-empty string", 2)
    end
    if type(required_color) ~= "string" or required_color == "" then
        error("required_color must be a non-empty string", 2)
    end
    if on_wait_update ~= nil and type(on_wait_update) ~= "function" then
        error("on_wait_update must be a function or nil", 2)
    end

    required_color = string.lower(required_color)
    if type(M.BUS_CHECK_INTERVAL_SECONDS) ~= "number" or M.BUS_CHECK_INTERVAL_SECONDS < 0 then
        error("BUS_CHECK_INTERVAL_SECONDS must be a number >= 0", 2)
    end

    while true do
        local readiness = M.get_input_push_readiness(required_color)
        if on_wait_update then
            on_wait_update(readiness)
        end
        if readiness.all_met then
            break
        end

        sleep(M.BUS_CHECK_INTERVAL_SECONDS)
    end

    return M.push_one_item_by_name(M.INTERNAL_STORAGE_CONTAINER, M.CRUCIBLE_INPUT_BUS, item_name)
end

return M
