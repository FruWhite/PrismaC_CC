local running_program = shell and shell.getRunningProgram and shell.getRunningProgram() or "tests/test_status_monitor.lua"
local project_root = fs.combine(fs.getDir(running_program), "..")

local config = dofile(fs.combine(project_root, "config.lua"))
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

local function inventory_counts(peripheral_name)
    local inv = wrap_if_exists(peripheral_name)
    if not inv or type(inv.list) ~= "function" then
        return false, 0, 0
    end
    local slots_used = 0
    local total_items = 0
    for _, stack in pairs(inv.list()) do
        slots_used = slots_used + 1
        total_items = total_items + stack.count
    end
    return true, slots_used, total_items
end

local function bool_text(v)
    if v then
        return "OK"
    end
    return "MISSING"
end

local function sample_status()
    local ext_ok, ext_slots, ext_total = inventory_counts(config.EXTERNAL_INPUT_CONTAINER)
    local int_ok, int_slots, int_total = inventory_counts(config.INTERNAL_STORAGE_CONTAINER)
    local bus_ok, bus_slots, bus_total = inventory_counts(config.CRUCIBLE_INPUT_BUS)
    local out_ok, out_slots, out_total = inventory_counts(config.OUTPUT_CONTAINER)

    local chroma_signal = read_analog_input(config.DEFAULT_CHROMA_SENSOR_SIDE)
    local chroma_color = utils.decode_chroma_sensor_signal(chroma_signal)
    local working_signal = read_analog_input(config.CRUCIBLE_WORKING_SIGNAL_SIDE)
    local trigger_signal = read_analog_input(config.AE2_CRAFT_TRIGGER_SIDE)

    return {
        monitor_ok = monitor ~= nil,
        ext_ok = ext_ok,
        ext_slots = ext_slots,
        ext_total = ext_total,
        int_ok = int_ok,
        int_slots = int_slots,
        int_total = int_total,
        bus_ok = bus_ok,
        bus_slots = bus_slots,
        bus_total = bus_total,
        out_ok = out_ok,
        out_slots = out_slots,
        out_total = out_total,
        chroma_signal = chroma_signal,
        chroma_color = chroma_color or "invalid",
        working_signal = working_signal,
        trigger_signal = trigger_signal,
    }
end

local function serialize_status(s)
    return table.concat({
        tostring(s.monitor_ok),
        tostring(s.ext_ok), tostring(s.ext_slots), tostring(s.ext_total),
        tostring(s.int_ok), tostring(s.int_slots), tostring(s.int_total),
        tostring(s.bus_ok), tostring(s.bus_slots), tostring(s.bus_total),
        tostring(s.out_ok), tostring(s.out_slots), tostring(s.out_total),
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
        ("external(%s): %s slots=%d items=%d"):format(config.EXTERNAL_INPUT_CONTAINER, bool_text(s.ext_ok), s.ext_slots, s.ext_total),
        ("internal(%s): %s slots=%d items=%d"):format(config.INTERNAL_STORAGE_CONTAINER, bool_text(s.int_ok), s.int_slots, s.int_total),
        ("inputbus(%s): %s slots=%d items=%d"):format(config.CRUCIBLE_INPUT_BUS, bool_text(s.bus_ok), s.bus_slots, s.bus_total),
        ("output(%s): %s slots=%d items=%d"):format(config.OUTPUT_CONTAINER, bool_text(s.out_ok), s.out_slots, s.out_total),
        "",
        ("chroma side=%s  signal=%d  color=%s"):format(config.DEFAULT_CHROMA_SENSOR_SIDE, s.chroma_signal, s.chroma_color),
        ("working side=%s signal=%d  state=%s"):format(
            config.CRUCIBLE_WORKING_SIGNAL_SIDE,
            s.working_signal,
            s.working_signal > 0 and "WORKING" or "IDLE"
        ),
        ("trigger side=%s signal=%d  state=%s"):format(
            config.AE2_CRAFT_TRIGGER_SIDE,
            s.trigger_signal,
            s.trigger_signal > 0 and "ON" or "OFF"
        ),
    }

    write_lines(lines)
    sleep(config.BUS_CHECK_INTERVAL_SECONDS or 0.1)
end
