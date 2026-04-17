local CONFIG = {}

CONFIG.DEFAULT_CHROMA_SENSOR_SIDE = "bottom"
CONFIG.CRUCIBLE_WORKING_SIGNAL_SIDE = "left"
CONFIG.BUS_CHECK_INTERVAL_SECONDS = 0.1
CONFIG.AE2_CRAFT_EMITTER_SIDE = "right"

CONFIG.INPUT_CONTAINER = "minecraft:barrel_6"
CONFIG.INTERNAL_STORAGE_CONTAINER = "minecraft:barrel_7"
CONFIG.CRUCIBLE_INPUT_BUS = "gtceu:uv_input_bus_1"
CONFIG.OUTPUT_CONTAINER = "minecraft:barrel_5"
CONFIG.STATUS_MONITOR = "monitor_1"

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
