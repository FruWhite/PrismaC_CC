local CONFIG = {}

CONFIG.DEFAULT_CHROMA_SENSOR_SIDE = "bottom"
CONFIG.CRUCIBLE_WORKING_SIGNAL_SIDE = "left"
CONFIG.BUS_CHECK_INTERVAL_SECONDS = 0.1
CONFIG.AE2_CRAFT_TRIGGER_SIDE = "right"

CONFIG.PSOC_INPUT_CONTAINER = "minecraft:barrel_5"
CONFIG.PRISM_GLASS_INPUT_CONTAINER = "minecraft:barrel_6"
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

return CONFIG
