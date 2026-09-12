# Suite API

A Benchmarkr suite is a ModuleScript that returns a plain table. Benchmarker-style suites with
`Functions` and an optional `ParameterGenerator` work as-is. Benchmarkr-specific configuration and
lifecycle hooks live in the optional `Benchmarkr` table.

## Complete shape

```lua
return {
	ParameterGenerator = function(runIndex, caseName, isWarmup)
		return valueA, valueB
	end,

	Functions = {
		["Case name"] = function(Profiler, valueA, valueB)
			Profiler.Begin("Scope")
			-- measured work
			Profiler.End()
		end,
	},

	Benchmarkr = {
		Id = "stable-suite-id",
		Name = "Readable suite name",
		Runs = 500,
		WarmupRuns = 25,
		RandomizeOrder = true,
		Seed = 12345,
		BeforeAll = function()
			-- setup outside all measurements
		end,
		AfterAll = function(result)
			-- cleanup after success, cancellation, or run error
		end,
	},
}
```

Only `Functions` is required.

## Functions

`Functions` maps a non-empty case name to a callback. Benchmarkr sorts case names for stable display
and invokes every case once per warmup round and once per measured round.

```lua
Functions = {
	["find manually"] = function(Profiler, values, target)
		for index, value in ipairs(values) do
			if value == target then
				return index
			end
		end
		return nil
	end,
}
```

The first callback argument is always the Benchmarkr profiler. Any values returned by
`ParameterGenerator` follow it. Callback return values are ignored.

The full callback duration is the recorded case sample. Profiler scopes divide that sample into
named regions but do not change the case timing.

## ParameterGenerator

`ParameterGenerator(runIndex, caseName, isWarmup)` is optional. Benchmarkr calls it immediately
before each case invocation and outside the measured region.

- `runIndex` starts at 1 separately for warmups and measured runs.
- `caseName` is the key from `Functions` that will run next.
- `isWarmup` is `true` during warmup rounds and `false` during measured rounds.
- All returned values are passed to the case callback after the profiler.

Because generation happens per case, it can provide fresh mutable input and tailor input to a case.
To compare cases fairly, generate equivalent workloads for every case name.

Older generators that declare no parameters remain valid; Luau ignores unused arguments.

## Profiler

The profiler has two operations:

```lua
Profiler.Begin("Parse")
-- measured work
Profiler.End()
```

Scopes can be nested:

```lua
Profiler.Begin("Serialize")
	Profiler.Begin("Keys")
	-- measured work
	Profiler.End()

	Profiler.Begin("Values")
	-- measured work
	Profiler.End()
Profiler.End()
```

Profiler rules:

- Labels must be non-empty strings.
- `[UNTRACKED]` is reserved.
- Every `Begin` must be closed by one `End` before the callback finishes.
- Calling `End` without an open scope fails the run.
- Repeated labels under the same parent are aggregated into one path.
- The same label under different parents creates different paths.
- Work outside all top-level scopes is reported as `[UNTRACKED]`.

Profiler statistics are aggregated independently for each path across measured runs. Warmup profiles
are discarded.

## Benchmarkr configuration

Every field is optional.

| Field | Accepted value | Default | Purpose |
| --- | --- | --- | --- |
| `Id` | Non-empty string | Place and ModuleScript path | Stable key for history and baselines. |
| `Name` | Non-empty string | ModuleScript name | Display name in reports. |
| `Runs` | Integer from 10 to 10,000 | `500` | Measured invocations per case. |
| `WarmupRuns` | Integer from 0 to 1,000 | `25` | Unrecorded invocations per case before measurement. |
| `RandomizeOrder` | Boolean | `true` | Shuffle case order independently in every measured round. |
| `Seed` | Finite number | Generated | Reproduce measured case ordering. |
| `BeforeAll` | Function | None | Perform setup once, before warmups. |
| `AfterAll` | Function | None | Clean up after a started run. |

Values typed into the widget's Runs and Warmup inputs override `Runs` and `WarmupRuns` for that run.
Blank inputs do not override the suite.

Warmups use sorted case order. When randomization is enabled, measured rounds use the seeded shuffle.
The effective seed is stored in the report.

## Lifecycle hooks

`BeforeAll()` runs once before any generator or case callback. If it fails, the run ends and
`AfterAll` is not called because the lifecycle did not start successfully.

`AfterAll(result)` runs after a successful, cancelled, or failed run once setup has completed. Its
argument always includes one of these statuses:

```lua
{ status = "success", ... }
{ status = "cancelled" }
{ status = "error", error = "traceback..." }
```

The successful value also contains the raw runner result. Use `AfterAll` for cleanup, not for work
whose duration should be included in a case. If `AfterAll` fails, Benchmarkr reports the cleanup
failure; when the run had already failed, both errors are retained.

## Loading behavior

Roblox caches a ModuleScript after its first `require()`. To keep reruns fresh, Benchmarkr:

1. clones the selected ModuleScript next to the original;
2. copies current editor source into the clone and its descendant source containers;
3. requires the clone;
4. destroys the clone after the run or load error.

The temporary clone stays beside the original so relative sibling lookup continues to work. Modules
required from outside the cloned subtree still use Roblox's normal require cache.

## Methodology recommendations

- Benchmark one focused operation, but repeat it inside each invocation if the result is near the
  timer floor.
- Keep setup and input generation in `BeforeAll` or `ParameterGenerator`.
- Use the same input size and shape for every case.
- Avoid yielding, network access, DataStores, and frame-dependent services.
- Keep `RandomizeOrder` enabled to reduce systematic order bias.
- Compare P50 first, then inspect P10/P90 and the per-run line for instability.
- Pin a baseline produced under similar Studio and machine conditions.
- Do not subtract assumed loop or profiler overhead. Benchmarkr reports observed time directly.

## Validation errors

Benchmarkr rejects a suite before measuring when:

- the ModuleScript does not return a table;
- `Functions` is missing, empty, or contains invalid names or callbacks;
- `ParameterGenerator`, `BeforeAll`, or `AfterAll` is not a function;
- `Benchmarkr`, when present, is not a table;
- a name, ID, run count, warmup count, randomization setting, or seed is invalid.

Case errors include the case name, run index, and traceback. Generator errors identify the case and
run they were preparing.
