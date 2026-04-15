local CONFIG = {}

CONFIG.DEFAULT_CHROMA_SENSOR_SIDE = "bottom"
CONFIG.CRUCIBLE_WORKING_SIGNAL_SIDE = "left"
CONFIG.BUS_CHECK_INTERVAL_SECONDS = 0.1
CONFIG.AE2_CRAFT_TRIGGER_SIDE = "right"

-- Peripheral names (edit to match your world/wired modem names).
CONFIG.ACTIVE_CORE_INPUT_CONTAINER = "minecraft:barrel_2"
CONFIG.SUPERCRITICAL_CORE_INPUT_CONTAINER = "minecraft:barrel_4"
CONFIG.INTERNAL_STORAGE_CONTAINER = "minecraft:barrel_0"
CONFIG.CRUCIBLE_INPUT_BUS = "gtceu:uv_input_bus_0"
CONFIG.OUTPUT_CONTAINER = "minecraft:barrel_3"
CONFIG.STATUS_MONITOR = "monitor_0"

CONFIG.PRISMATIC_COLOR_BY_SIGNAL = {
    [1] = "red",
    [2] = "orange",
    [3] = "yellow",
    [4] = "lime",
    [5] = "green",
    [6] = "teal",
    [7] = "cyan",
    [8] = "azure",
    [9] = "blue",
    [10] = "indigo",
    [11] = "magenta",
    [12] = "pink",
}

-- Required stock in internal storage for one inert -> active core cycle.
-- Uses official core ids: kubejs:${coreIn}_prismatic_core
CONFIG.ACTIVE_CORE_STORAGE_REQUIREMENTS = {
    ["kubejs:chromatic_stabilizer"] = 3,
    ["kubejs:inert_prismatic_core"] = 1,
    ["kubejs:red_prismatic_core"] = 1,
    ["kubejs:yellow_prismatic_core"] = 1,
    ["kubejs:green_prismatic_core"] = 1,
    ["kubejs:cyan_prismatic_core"] = 1,
    ["kubejs:blue_prismatic_core"] = 1,
}

CONFIG.SUPERCRITICAL_CORE_STORAGE_REQUIREMENTS = {
    ["kubejs:chromatic_stabilizer"] = 3,
    ["kubejs:chromatic_capacitor_empty"] = 1,
    ["kubejs:inert_prismatic_core"] = 1,
    ["kubejs:red_prismatic_core"] = 1,
    ["kubejs:yellow_prismatic_core"] = 1,
    ["kubejs:green_prismatic_core"] = 1,
    ["kubejs:cyan_prismatic_core"] = 1,
    ["kubejs:blue_prismatic_core"] = 1,
    ["kubejs:active_prismatic_core"] = 1,
    ["kubejs:orange_prismatic_core"] = 1,
    ["kubejs:lime_prismatic_core"] = 1,
    ["kubejs:teal_prismatic_core"] = 1,
    ["kubejs:azure_prismatic_core"] = 1,
    ["kubejs:indigo_prismatic_core"] = 1,
}

return CONFIG
