# Getting started

This guide takes you from a source checkout to a useful benchmark result in Roblox Studio.

## Requirements

- Roblox Studio
- [Rokit](https://github.com/rojo-rbx/rokit)
- Git, if you are cloning the repository

Rokit installs the pinned versions of Rojo, Lune, Selene, and StyLua declared in `rokit.toml`.

## Build and install

From the repository root, run:

```sh
rokit install
mkdir -p build
rojo build -o build/Benchmarkr.rbxm
```

Install `build/Benchmarkr.rbxm` as a local plugin through Roblox Studio's Plugins management UI.
The **⏱ Benchmarkr** toolbar action opens and closes the dockable widget.

Rebuild and reinstall the model after changing the source. Benchmarkr has no runtime packages and
does not need an HTTP connection.

## Create your first suite

Open Benchmarkr and choose **＋ New benchmark**. The plugin creates a ModuleScript in the selected
container, or in `ServerStorage` when the current selection is not a suitable container. Creation
is undoable and the new script opens in the editor.

You can also create a ModuleScript yourself. A minimal suite looks like this:

```lua
return {
	Functions = {
		["ipairs"] = function()
			for _, value in ipairs({ 1, 2, 3, 4, 5 }) do
				local copy = value
			end
		end,

		["numeric for"] = function()
			local values = { 1, 2, 3, 4, 5 }
			for index = 1, #values do
				local copy = values[index]
			end
		end,
	},
}
```

Select exactly one benchmark ModuleScript in Explorer. The header changes to **Ready** when the
selection is runnable. Choose **▶ Run** to use the suite's configuration. Values typed into **Runs**
or **Warmup** override that configuration; leave an input blank to keep the suite value or default.

Runs must be an integer from 10 through 10,000. Warmups must be an integer from 0 through 1,000.

## Read the dashboard

The case panel uses P50, the median, as the main comparison. It is less sensitive to occasional
slow frames than the mean. Each case also includes:

- P10 and P90, which describe the middle 80 percent of measured timings
- minimum and maximum
- arithmetic mean and total measured time
- sample count
- a comparison with the fastest current case
- a baseline delta, when the suite has a baseline

The colored **✓** control shows or hides a case. Hiding a case also recalculates the graph bounds.
Select the rest of a case card to show its profiler data.

### Graph views

| Action | Meaning |
| --- | --- |
| **▥ Distribution** | Shows normalized timing-frequency bins on shared bounds. |
| **↗ Line** | Shows timing by measured run, useful for drift and spikes. |
| **↔ Error bars** | Shows P10, P50, and P90 for each case. |
| **↻ Reset view** | Restores the full horizontal data range. |

Hover over a graph for exact values. Use the mouse wheel over the plot to zoom horizontally and
drag horizontally to pan. A pinned baseline appears as a lighter overlay.

### Profiler view

Every benchmark case receives a profiler as its first argument. Timed scopes appear as blocks in
the profiler panel. Select a block to focus its subtree, then use the breadcrumb buttons to move
back toward the case root.

Time that is not inside a top-level profiler scope appears as `[UNTRACKED]`. This is expected for
cases that do not use profiler scopes: the case itself is still timed normally.

## Stop a run

Choose **■ Stop** to request cancellation. Benchmarkr finishes the current case invocation before
stopping. A cancelled run does not replace the previous result and is not added to history.

## Compare runs

After a successful run, choose **⚑ Pin baseline**. Future results with the same suite ID are
compared with it. Negative median deltas are faster; positive median deltas are slower.

Set `Benchmarkr.Id` in the suite when results should stay associated after the ModuleScript moves.
Without an explicit ID, Benchmarkr derives one from the place and the script path.

See [Reports and history](reports-and-history.md) for retention and export details.

## Troubleshooting

### The Run action is disabled

Select exactly one ModuleScript. A report folder can be selected for viewing, but it cannot be
run. Multi-selection and other Instance classes are not runnable.

### The suite fails before measurements begin

The selected ModuleScript must return a table with a non-empty `Functions` table. Open the error
dialog for the validation error or Luau traceback. The complete contract is in the
[Suite API](suite-api.md).

### Profiler.Begin calls were not closed

Every `Profiler.Begin(label)` needs a matching `Profiler.End()` in the same invocation. Check early
returns and error paths. Benchmarkr rejects incomplete profiles instead of reporting misleading
scope durations.

### Very small results are marked near timer floor

The median is within ten times the observed `os.clock()` resolution. Increase the amount of work
performed by each case invocation, while keeping that amount identical between cases. Treat the
relative order as inconclusive until the warning disappears.

### Results vary between runs

Close expensive Studio tools, avoid editing or play-testing during a run, increase warmups and
measured runs, and compare medians. Keep randomized order enabled unless measuring in a fixed order
is intentional. A seed reproduces case ordering, not external system load.

### A selected report will not open

The folder must be an intact Benchmarkr v1 report. Missing or renamed `Chunk_` values make an RBXM
report incomplete. Reinsert the original exported model rather than editing its contents.

## Safety

Benchmark suites execute in the open Studio place with the permissions of their ModuleScript.
Review unfamiliar code before running it. Do not put destructive operations, DataStore writes,
network calls, or yielding work in a benchmark case.
