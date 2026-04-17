# PrismaticCrucible CraftOS Automation

Lua scripts for a ComputerCraft:Tweaked computer that automate Prismatic Crucible recipes in Monifactory beta 0.13.x.

## Recipes

### Chromatic Processing (`main_processing.lua`)
- `kubejs:blue_aligned_glass`
- `kubejs:photonic_soc_active` 

### Chromatic Transcendence (`main_transcendence.lua`)
- `kubejs:active_prismatic_core`
- `kubejs:supercritical_prismatic_core`
- `liquid null` using supercritical core (script submits core only; fluid output handled by machine hatches)

## Setup 
(todo example setup image)
1. Put the computer block at a place that can connect to all redstone sides listed below conveniently.
2. Place devices and connect them to the computer with modems and network cables. Let the output bus of the crucible point to the internal storage chest(`INTERNAL_STORAGE_CONTAINER`) of computer.
3.  Edit config files to match your modem names in your world:
   - `config_processing.lua`
   - `config_transcendence.lua` 
4. For chromatic transcendence mode , ensure enough **Liquid Transcendental Matrix** supplied for core crafting, and output hatch exists for nullify recipe.
5. Put required intermediates in internal storage chest and set the crucible's initial color according to the **Intermediates and Initial Color Requirements** section below
6. Put pattern providers on the input containers, and connect me emitters with crafting cards to AE2_CRAFT_TRIGGER_SIDE if you want to trigger crafting with AE2 crafting CPU. Alternatively, you can use a manual redstone switch or any other redstone signal source to trigger the process.
7. Start the desired runner on the CC computer:
   - `main_processing.lua` for glass/Photonic SOC
   - `main_transcendence.lua` for cores/nullify

### Peripheral List and Config Mapping

#### Shared

- `INTERNAL_STORAGE_CONTAINER`: the container be regarded as the internal storage of the system;
- `STATUS_MONITOR`(Optional): shows current cycle status, active recipe, and error messages if any;
- `OUTPUT_CONTAINER`: the container where the final crafted items are deposited. Do not confused with the crucible output bus, which should point to the `INTERNAL_STORAGE_CONTAINER` instead;
- `CRUCIBLE_INPUT_BUS`: the input bus of the Prismatic Crucible;
- Redstone sides:
  - `DEFAULT_CHROMA_SENSOR_SIDE`: connect to a basic chroma sensor to read crucible color.
  - `CRUCIBLE_WORKING_SIGNAL_SIDE`: connect to the crucible's activity detector cover.
  - `AE2_CRAFT_TRIGGER_SIDE` : connect to `OR` gates of some me emitters with crafting cards to trigger crafting.

#### Chromatic Processing

- `INPUT_CONTAINER`: the container where you put input items for processing cycles. Connect your AE2 pattern provider to this container.

#### Chromatic Transcendence

- `ACTIVE_CORE_INPUT_CONTAINER`: the container for inputting materials for active core crafting cycles
- `SUPERCRITICAL_CORE_INPUT_CONTAINER`: the container for inputting materials for supercritical core crafting cycles and inputing supercritical cores for nullify cycles.

### Intermediates and Initial Color Requirements

#### Chromatic Processing

- Required crucible initial color: `red`
- Blue aligned glass: `kubejs:green_aligned_glass x1`
- Active psoc: `kubejs:photonic_soc_cyan x1`, `kubejs:photonic_soc_yellow x1`, `kubejs:photonic_soc_magenta x1`

#### Chromatic Transcendence

- Required crucible initial color: `magenta` (just use one stabilizer for red crucible)

```
active_intermediates = [
  "red",
  "yellow",
  "green",
  "cyan",
  "blue",
]
supercritical_intermediates = active_intermediates + [
  "active", # magenta
  "orange",
  "lime",
  "teal",
  "azure",
  "indigo",
]
```

- Active core cycle: `[f"kubejs:{color}_prismatic_core" for color in active_intermediates]` +
- Supercritical core cycle: `[f"kubejs:{color}_prismatic_core" for color in supercritical_intermediates]` + `kubejs:chromatic_capacitor_empty` x 1
- Nullify cycle: `None`.



## Usage

Trigger model (both mains):
- Program remains in standby while trigger redstone is OFF to save tps.
- It activates on rising edge (OFF -> ON).
- While trigger stays ON, it keeps checking input and runs craft cycles whenever full valid batch exists.
- If trigger turns OFF, it returns to standby after current cycle completes.

### Processing mode

Input chest (`INPUT_CONTAINER`):
- Blue glass cycle trigger: `kubejs:lyso_ce_glass x1`
- PSOC cycle trigger: `kubejs:photonic_soc_inert x3`

Output chest (`OUTPUT_CONTAINER`):
- Receives crafted `kubejs:blue_aligned_glass x 1`
- Receives crafted `kubejs:photonic_soc_active x 3` 

### Transcendence mode

Active-core input chest (`ACTIVE_CORE_INPUT_CONTAINER`) batch:
- `kubejs:inert_prismatic_core x1`
- `kubejs:chromatic_stabilizer x3`

Super/nullify input chest (`SUPERCRITICAL_CORE_INPUT_CONTAINER`) batches:
- Supercritical core cycle: `kubejs:inert_prismatic_core x1` + `kubejs:chromatic_stabilizer x3`
- Nullify cycle: `kubejs:supercritical_prismatic_core x1`


Output chest (`OUTPUT_CONTAINER`):
- Receives crafted `kubejs:active_prismatic_core x 1`
- Receives crafted `kubejs:supercritical_prismatic_core x 1`
- Nullify fluid output is not moved by script (handled by your machine fluid outputs)
