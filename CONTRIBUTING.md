# Contributing to Benchmarkr

Benchmarkr is a dependency-free Roblox Studio plugin written in plain, untyped Luau. Contributions
should keep the benchmark engine deterministic, the UI readable in both Studio themes, and every UI
control tied to a clear user action.

## Set up the toolchain

Install the versions pinned in `rokit.toml`:

```sh
rokit install
```

The repository uses:

- Rojo to build the plugin model;
- Lune to run pure Luau tests and inspect the built model;
- Selene for linting;
- StyLua for formatting.

## Project layout

```text
src/
├── Core/       Pure runner, statistics, profiler, history, and report modules
├── Studio/     Plugin lifecycle, ModuleScript loading, templates, and RBXM reports
├── UI/         Native Studio widget, shared elements, icons, theme, and charts
└── Main.server.lua
tests/          Lune tests for pure modules and the built plugin structure
examples/       Example benchmark suites
```

Core modules use conditional requires so the same source runs under Roblox and Lune. Keep Studio
APIs out of `src/Core` so its behavior remains testable without Studio.

## Validate a change

Run the complete local validation sequence from the repository root:

```sh
stylua --check src tests examples
selene src tests examples
lune run tests/run.luau
mkdir -p build
rojo build -o build/Benchmarkr.rbxm
lune run tests/inspect_model.luau
```

Use `stylua src tests examples` to apply formatting when the check fails.

For a UI change, also install the rebuilt RBXM in Studio and check:

- dark and light Studio themes;
- the minimum widget size of 760 by 480;
- a narrow layout and the default 1120 by 720 layout;
- long suite, case, and profiler labels;
- empty, running, successful, cancelled, failed, history, baseline, and modal states;
- hover, zoom, pan, case visibility, and profiler drill-down.

## Coding conventions

- Use plain, untyped Luau.
- Put platform-independent logic in `src/Core` and cover it with Lune tests.
- Keep setup, rendering, and yields outside measured benchmark regions.
- Preserve prior results when a run fails or is cancelled.
- Give every control a visible text label even when it also has a symbol.
- Define UI symbols in `src/UI/Icons.lua` with `utf8.char`; do not paste encoded glyph bytes into
  source files.
- Use theme palette keys instead of hard-coded UI colors unless the color encodes series identity.
- Validate external or saved data before rendering it.

## Report compatibility

`Report.SCHEMA_VERSION` and `History.SCHEMA_VERSION` are persistence boundaries. Do not change a
stored shape without deciding how older values will be rejected or migrated. Report validators,
compaction, CSV export, RBXM import, history normalization, and their tests should change together.

## Testing benchmark logic

Runner tests inject a deterministic clock and a no-op yield function. Prefer these dependencies over
wall-clock assertions, which are unreliable. Add focused tests for success and failure paths when
changing validation, lifecycle behavior, statistics, sampling, history, or reports.

## Build artifact

The release artifact is `build/Benchmarkr.rbxm`. `tests/inspect_model.luau` verifies its root model,
entry script, expected folders, and graph modes. Build it only after source checks pass.
