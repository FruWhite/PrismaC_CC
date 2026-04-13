# Copilot Instructions for PrismaticCrucible

This project is for writing **Lua scripts** that run on a **ComputerCraft: Tweaked** computer (CraftOS) to automate the **Prismatic Crucible** workflow in the **Monifactory** modpack.

## Project Goal

Implement reliable CraftOS automation that:
- accepts incoming ingredients,
- detects the Prismatic Crucible's current machine/state progression,
- inserts the correct ingredient at the correct time and in the correct order,
- and optionally visualizes status on an attached monitor.

Target outputs include both major lines shown in project assets:
- **PSoC recipes** (`RecipePics/psoc`)
- **Active/Supercritical core recipes** (`RecipePics/cores`)

## Source of Truth and Reference Priority

When behavior is ambiguous, use references in this order:
1. **`./kubejs_codes_selected_for_ref/Prismatic_Crucible.js`** (most reliable recipe/state logic source)
2. **`./description.md`** (FTB quest text summary)
3. **`./RecipePics/`** (visual recipe aids, grouped by product line)

Only implement **Lua CraftOS computer code** in this repository.  
Do **not** rewrite or modify KubeJS recipe definitions as part of automation logic.

## Crucible Color Index (Canonical)

Use this fixed color-number mapping whenever logic depends on `outputStatesRelative` or state-wheel movement:

`1 RED, 2 ORANGE, 3 YELLOW, 4 LIME, 5 GREEN, 6 TEAL, 7 CYAN, 8 AZURE, 9 BLUE, 10 INDIGO, 11 MAGENTA, 12 PINK`

## Platform Documentation

Use these docs when implementing APIs/peripheral behavior:
- CraftOS-PC docs: https://www.craftos-pc.cc/docs/
- ComputerCraft: Tweaked docs: https://tweaked.cc/

Prefer official CC:Tweaked peripheral and event APIs (`peripheral`, `redstone`, `os.pullEvent`, `term`, `monitor`, inventory transfer methods) over custom assumptions.

## Implementation Expectations

- Build automation as a **state machine** (explicit states + transitions).
- Keep recipe/state mapping data-driven (tables), not hard-coded scattered conditionals.
- Validate machine state before item insertion; fail loudly on unknown/invalid states.
- Preserve strict ordering and timing guarantees for ingredient injection.
- Make retries controlled and bounded; report actionable errors instead of silent failure.
- Separate concerns:
  - `utils.lua`: shared helpers (logging, peripheral lookup, safe transfers, formatting)
  - recipe/state data module(s): mappings and transition rules
  - main runner script(s): orchestration loop and I/O handling

## Coding Style

- Use clear, small functions and descriptive names tied to machine concepts.
- Prefer deterministic behavior over "best effort" heuristics.
- Add brief comments only where machine logic is non-obvious.
- Keep scripts compatible with CraftOS Lua runtime constraints.

## Operator UX (Optional but Encouraged)

If monitor UI is present, display:
- current phase/state,
- expected next ingredient,
- last successful transfer,
- warnings/errors and recovery hints.

If no monitor exists, provide equivalent terminal output.
