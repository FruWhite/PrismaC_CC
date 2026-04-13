local CONFIG = {}

CONFIG.DEFAULT_CHROMA_SENSOR_SIDE = "back"
CONFIG.CRUCIBLE_WORKING_SIGNAL_SIDE = "right"
CONFIG.BUS_CHECK_INTERVAL_SECONDS = 0.1
CONFIG.AE2_CRAFT_TRIGGER_SIDE = "left"

-- Peripheral names (edit to match your world/wired modem names).
CONFIG.EXTERNAL_INPUT_CONTAINER = "input_container"
CONFIG.INTERNAL_STORAGE_CONTAINER = "internal_storage_container"
CONFIG.CRUCIBLE_INPUT_BUS = "prismatic_crucible_input_bus"
CONFIG.OUTPUT_CONTAINER = "output_container"

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

return CONFIG
