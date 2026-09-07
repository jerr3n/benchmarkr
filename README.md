# Benchmarkr

Benchmarkr is a dependency-free Roblox Studio plugin for comparing the performance of Luau
functions. It combines repeatable benchmark runs, median-focused statistics, interactive
distribution, per-run line, and percentile error-bar graphs, nested profiling, baseline comparisons, local history, and
portable reports in one dockable Studio widget.

Benchmarkr is inspired by [Boatbomber's Benchmarker](https://boatbomber.itch.io/benchmarker),
while remaining an independent open-source implementation.

## Install

Build the plugin from source:

```sh
rokit install
mkdir -p build
rojo build -o build/Benchmarkr.rbxm
```

Then install `build/Benchmarkr.rbxm` as a local plugin from Roblox Studio's Plugins folder. The
widget can be opened or closed with the **Benchmarkr** toolbar button.

## Write a benchmark

Create a ModuleScript, select it in Explorer, and click **Run**. The fastest starting point is the
plugin's **New benchmark** action, which inserts an undoable, documented example.

Existing Benchmarker-style suites work without changes:

```lua
return {
	ParameterGenerator = function(runIndex, caseName, isWarmup)
		-- This runs outside the measured region.
		return math.random(1, 1000)
	end,

	Functions = {
		["table.create"] = function(Profiler, value)
			Profiler.Begin("Allocate")
			local output = table.create(100)
			Profiler.End()

			Profiler.Begin("Fill")
			for index = 1, 100 do
				output[index] = value
			end
			Profiler.End()
		end,

		["empty table"] = function(Profiler, value)
			local output = {}
			for index = 1, 100 do
				output[index] = value
			end
		end,
	},

	Benchmarkr = {
		Id = "array-allocation",
		Name = "Array allocation",
		Runs = 500,
		WarmupRuns = 25,
		RandomizeOrder = true,
		Seed = 12345,
		BeforeAll = function() end,
		AfterAll = function(result) end,
	},
}
```

All fields under `Benchmarkr` are optional. Defaults are 500 measured runs, 25 warmups, and a
randomized case order. A generated seed is recorded with every result. Values entered in the
widget override the suite for that run; blank inputs use suite defaults.

`ParameterGenerator` receives the run index, case name, and warmup flag. Its return values are
passed to the case after the profiler. Older zero-argument generators simply ignore these extra
arguments. `BeforeAll` runs before warmups, and `AfterAll` receives a table whose `status` is
`success`, `cancelled`, or `error`.

Profiler scopes may nest, and repeated labels under the same parent are aggregated. Every
`Profiler.Begin()` must have a matching `Profiler.End()`. Time outside top-level scopes appears as
`[UNTRACKED]`, so that name is reserved.

## Read the results

- The case cards show P10, P50, P90, minimum, maximum, mean, total, and sample count. P50 is the
  primary comparison value because it is less sensitive to outliers than the mean.
- Click a colored checkbox to hide or show a case. Graph bounds update around visible cases.
- Switch between normalized distribution, per-run line, and P10-P50-P90 error-bar views. Hover for exact values,
  use the mouse wheel to zoom horizontally, drag to pan, and click **Reset view** to recover.
- Click a case card to inspect its profiler tree. Click a profiler block to focus its subtree and
  use the breadcrumbs to move back out.
- Use **Pin baseline** to compare future runs of the same suite. A stable `Benchmarkr.Id` keeps that
  association even if the ModuleScript moves.

Benchmarkr stores 20 compact recent results and one pinned baseline per suite in local plugin
settings. Exact summary and profiler statistics are retained; graphs keep 48 distribution bins and
up to 300 sample points. Opening a saved result from **History** does not rerun its code.

## Export and import

- **JSON** opens the complete structured report for copying.
- **CSV** opens a spreadsheet-friendly summary, including baseline deltas when available.
- **RBXM** saves a portable report folder containing chunked JSON and a CSV summary. Insert the
  `.rbxm` into another place and select the report folder to reopen it in Benchmarkr.

Reports exported immediately after a run contain every raw timing sample. A report reopened from
local history contains its exact statistics plus the compact graph data retained by history.

Studio does not expose arbitrary text-file writing to plugins, so JSON and CSV use a selectable
copy dialog. RBXM export temporarily changes Explorer selection, then restores it and removes its
temporary instance.

## Accuracy and safety

Benchmarkr measures with `os.clock()` and never subtracts guessed overhead. Results near the
observed timer floor are marked because their ordering may not be meaningful. Parameter generation,
warmups, progress rendering, and cooperative yields occur outside measured regions. Case order is
randomized by default to reduce systematic ordering bias.

`Benchmarkr.Seed` controls case ordering. Seed any randomness inside `ParameterGenerator`
separately when reproducible inputs matter.

Benchmark modules execute in the real open Studio place and can access or mutate anything their
code can reach. Review a suite before running it, do not perform DataStore or destructive operations,
and do not benchmark yielding work.

Each run requires a fresh temporary clone of the selected ModuleScript because Roblox caches a
ModuleScript after its first `require()`. Benchmarkr synchronizes current editor source for the
selected module and its descendants, preserves relative sibling lookup while loading, and removes
the clone afterward. Modules required from outside that cloned subtree still follow Roblox's normal
cache behavior.

## Develop

The project uses plain, untyped Luau and has no runtime packages.

```sh
rokit install
stylua --check src tests examples
selene src tests examples
lune run tests/run.luau
mkdir -p build
rojo build -o build/Benchmarkr.rbxm
lune run tests/inspect_model.luau
```

The pure modules under `src/Core` contain the runner, statistics, profiler aggregation, history,
and report formats. `src/Studio` owns plugin-only integration, while `src/UI` builds the native
Studio widget and charts.

## License

[MIT](LICENSE)
