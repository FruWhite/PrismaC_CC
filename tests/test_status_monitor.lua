local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "tests/test_status_monitor.lua"
local project_root = fs.combine(fs.getDir(running_program), "..")

local config = dofile(fs.combine(project_root, "config_transcendence.lua"))
_G.PRISMATIC_CONFIG = config
local utils = dofile(fs.combine(project_root, "utils.lua"))

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

local monitor = wrap_if_exists(config.STATUS_MONITOR)
if monitor and monitor.setTextScale then
    monitor.setTextScale(0.5)
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

local function sample_status()
    local ext = inventory_status(config.ACTIVE_CORE_INPUT_CONTAINER)
    local sup = inventory_status(config.SUPERCRITICAL_CORE_INPUT_CONTAINER)
    local int = inventory_status(config.INTERNAL_STORAGE_CONTAINER)
    local bus = inventory_status(config.CRUCIBLE_INPUT_BUS)
    local out = inventory_status(config.OUTPUT_CONTAINER)

    local chroma_signal = read_analog_input(config.DEFAULT_CHROMA_SENSOR_SIDE)
    local chroma_color = utils.decode_chroma_sensor_signal(chroma_signal)
    local working_signal = read_analog_input(config.CRUCIBLE_WORKING_SIGNAL_SIDE)
    local trigger_signal = read_analog_input(config.AE2_CRAFT_EMITTER_SIDE)

    return {
        monitor_ok = monitor ~= nil,
        ext = ext,
        sup = sup,
        int = int,
        bus = bus,
        out = out,
        chroma_signal = chroma_signal,
        chroma_color = chroma_color or "invalid",
        working_signal = working_signal,
        trigger_signal = trigger_signal,
    }
end

local function serialize_status(s)
    return table.concat({
        tostring(s.monitor_ok),
        tostring(s.ext.ok), tostring(s.ext.slots), tostring(s.ext.total), top_items_text(s.ext, 32),
        tostring(s.sup.ok), tostring(s.sup.slots), tostring(s.sup.total), top_items_text(s.sup, 32),
        tostring(s.int.ok), tostring(s.int.slots), tostring(s.int.total), top_items_text(s.int, 32),
        tostring(s.bus.ok), tostring(s.bus.slots), tostring(s.bus.total), top_items_text(s.bus, 32),
        tostring(s.out.ok), tostring(s.out.slots), tostring(s.out.total), top_items_text(s.out, 32),
        tostring(s.chroma_signal), tostring(s.chroma_color),
        tostring(s.working_signal), tostring(s.trigger_signal),
    }, "|")
end

local started = os.clock()
local last_change = started
local change_count = 0
local last_snapshot = nil

while true do
    local s = sample_status()
    local snapshot = serialize_status(s)
    if snapshot ~= last_snapshot then
        change_count = change_count + 1
        last_change = os.clock()
        last_snapshot = snapshot
    end

    local lines = {
        "PrismaticCrucible wiring/status test",
        ("uptime: %.1fs   changes: %d"):format(os.clock() - started, change_count),
        ("last change: %.1fs ago"):format(os.clock() - last_change),
        "",
        ("monitor(%s): %s"):format(tostring(config.STATUS_MONITOR), bool_text(s.monitor_ok)),
        ("active-in(%s): %s slots=%d items=%d"):format(config.ACTIVE_CORE_INPUT_CONTAINER, bool_text(s.ext.ok), s.ext.slots, s.ext.total),
        ("  ids/counts: %s"):format(top_items_text(s.ext, 4)),
        ("super-in(%s): %s slots=%d items=%d"):format(config.SUPERCRITICAL_CORE_INPUT_CONTAINER, bool_text(s.sup.ok), s.sup.slots, s.sup.total),
        ("  ids/counts: %s"):format(top_items_text(s.sup, 4)),
        ("internal(%s): %s slots=%d items=%d"):format(config.INTERNAL_STORAGE_CONTAINER, bool_text(s.int.ok), s.int.slots, s.int.total),
        ("  ids/counts: %s"):format(top_items_text(s.int, 4)),
        ("inputbus(%s): %s slots=%d items=%d"):format(config.CRUCIBLE_INPUT_BUS, bool_text(s.bus.ok), s.bus.slots, s.bus.total),
        ("  ids/counts: %s"):format(top_items_text(s.bus, 4)),
        ("output(%s): %s slots=%d items=%d"):format(config.OUTPUT_CONTAINER, bool_text(s.out.ok), s.out.slots, s.out.total),
        ("  ids/counts: %s"):format(top_items_text(s.out, 4)),
        "",
        ("chroma side=%s  signal=%d  color=%s"):format(config.DEFAULT_CHROMA_SENSOR_SIDE, s.chroma_signal, s.chroma_color),
        ("working side=%s signal=%d  state=%s"):format(
            config.CRUCIBLE_WORKING_SIGNAL_SIDE,
            s.working_signal,
            s.working_signal > 0 and "WORKING" or "IDLE"
        ),
        ("trigger side=%s signal=%d  state=%s"):format(
            config.AE2_CRAFT_EMITTER_SIDE,
            s.trigger_signal,
            s.trigger_signal > 0 and "ON" or "OFF"
        ),
    }

    write_lines(lines)
    sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
end
