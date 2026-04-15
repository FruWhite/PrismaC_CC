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

local _ = psoc
_ = prism_glass

print("main_processing.lua loaded.")
print("Processing-mode automation not implemented yet.")
