local Histogram = require("../src/Core/Histogram")
local ErrorBars = require("../src/Core/ErrorBars")
local History = require("../src/Core/History")
local Profiler = require("../src/Core/Profiler")
local Random = require("../src/Core/Random")
local Report = require("../src/Core/Report")
local Runner = require("../src/Core/Runner")
local State = require("../src/Core/State")
local Stats = require("../src/Core/Stats")
local Trace = require("../src/Core/Trace")
local Viewport = require("../src/Core/Viewport")

local passed = 0
local failed = 0

local function equal(actual, expected, message)
	if actual ~= expected then
		error(
			message or string.format("expected %s, got %s", tostring(expected), tostring(actual)),
			2
		)
	end
end

local function near(actual, expected, epsilon, message)
	if math.abs(actual - expected) > epsilon then
		error(message or string.format("expected %.12g, got %.12g", expected, actual), 2)
	end
end

local function truthy(value, message)
	if not value then
		error(message or "expected a truthy value", 2)
	end
end

local function test(name, callback)
	local ok, message = xpcall(callback, function(problem)
		return debug.traceback(tostring(problem), 2)
	end)
	if ok then
		passed += 1
		print("PASS", name)
	else
		failed += 1
		warn("FAIL " .. name .. "\n" .. message)
	end
end

local function fakeClock(step)
	local current = 0
	return function()
		current += step
		return current
	end
end

local function sampleReport(id, median)
	local values = { median * 0.8, median, median * 1.2 }
	return {
		schemaVersion = 1,
		createdAt = "2026-09-07T12:00:00Z",
		suite = { id = id, name = 'Suite, "quoted"', path = "ServerStorage.Benchmark" },
		environment = { placeId = 1, gameId = 2, studioVersion = "test" },
		config = { runs = 3, warmupRuns = 0, randomizeOrder = true, seed = 1 },
		timerFloor = 1e-9,
		cases = {
			{
				name = "Case A",
				samples = values,
				stats = Stats.summarize(values),
				histogram = Histogram.build(values, 4),
				trace = Trace.downsample(values, 3),
				profile = {
					name = "Total",
					path = "",
					stats = Stats.summarize(values),
					children = {},
				},
			},
		},
	}
end

test("statistics use interpolated percentiles", function()
	local summary = Stats.summarize({ 4, 1, 3, 2 })
	near(summary.p10, 1.3, 1e-12)
	near(summary.p50, 2.5, 1e-12)
	near(summary.p90, 3.7, 1e-12)
	equal(summary.min, 1)
	equal(summary.max, 4)
	equal(summary.mean, 2.5)
	equal(summary.total, 10)
end)

test("statistics handle a single zero sample", function()
	local summary = Stats.summarize({ 0 })
	equal(summary.p10, 0)
	equal(summary.p50, 0)
	equal(summary.p90, 0)
	equal(summary.count, 1)
end)

test("duration formatting selects readable units", function()
	truthy(string.find(Stats.formatDuration(2), "s", 1, true))
	truthy(string.find(Stats.formatDuration(0.002), "ms", 1, true))
	truthy(string.find(Stats.formatDuration(0.000002), "s", 1, true))
	truthy(string.find(Stats.formatDuration(0.000000002), "ns", 1, true))
end)

test("histograms preserve counts for constant data", function()
	local histogram = Histogram.build({ 2, 2, 2, 2 }, 8)
	local total = 0
	for _, count in ipairs(histogram.counts) do
		total += count
	end
	equal(total, 4)
	truthy(histogram.maximum > histogram.minimum)
end)

test("shared histograms use identical bounds", function()
	local series = Histogram.shared({
		{ name = "A", samples = { 1, 2 } },
		{ name = "B", samples = { 10, 12 } },
	}, 4)
	equal(series[1].histogram.minimum, series[2].histogram.minimum)
	equal(series[1].histogram.maximum, series[2].histogram.maximum)
	equal(series[1].histogram.sampleMaximum, 2)
	equal(series[2].histogram.sampleMinimum, 10)
end)

test("trace downsampling keeps endpoints", function()
	local values = {}
	for index = 1, 1000 do
		values[index] = index
	end
	values[500] = 10000
	local trace = Trace.downsample(values, 300)
	equal(#trace, 300)
	equal(trace[1].index, 1)
	equal(trace[#trace].index, 1000)
	local foundSpike = false
	for _, point in ipairs(trace) do
		if point.index == 500 then
			foundSpike = true
			break
		end
	end
	truthy(foundSpike, "downsampling should retain an isolated timing spike")
end)

test("viewport zoom and pan remain inside data bounds", function()
	local view = Viewport.reset(0, 100)
	view = Viewport.zoom(view, 50, 0.5)
	near(view.minimum, 25, 1e-12)
	near(view.maximum, 75, 1e-12)
	view = Viewport.pan(view, 100)
	near(view.maximum, 100, 1e-12)
	near(view.minimum, 50, 1e-12)
end)

test("error bars use P10, P50, P90 and stable visible categories", function()
	local current = sampleReport("suite", 1)
	local baseline = sampleReport("suite", 2)
	baseline.cases[1].name = "Baseline only"
	local categories = ErrorBars.categories(current, baseline, {})
	equal(categories[1], "Case A")
	equal(categories[2], "Baseline only")

	local point = ErrorBars.point(current.cases[1])
	near(point.lower, 0.84, 1e-12)
	near(point.center, 1, 1e-12)
	near(point.upper, 1.16, 1e-12)
	local minimum, maximum = ErrorBars.bounds({ point })
	near(minimum, 0.84, 1e-12)
	near(maximum, 1.16, 1e-12)

	local hidden = ErrorBars.categories(current, baseline, { ["Case A"] = false })
	equal(#hidden, 1)
	equal(hidden[1], "Baseline only")
end)

test("constant error bars receive nonzero vertical bounds", function()
	local minimum, maximum = ErrorBars.bounds({
		{ lower = 2, center = 2, upper = 2 },
	})
	near(minimum, 1.9, 1e-12)
	near(maximum, 2.1, 1e-12)
end)

test("profiler aggregates nested, repeated, and untracked work", function()
	local clock = fakeClock(1)
	local api, finish = Profiler.create(clock)
	api.Begin("Outer")
	api.Begin("Inner")
	api.End()
	api.End()
	local record = finish(5)
	local tree = Profiler.aggregate({ record, record })
	equal(tree.stats.count, 2)
	equal(tree.children[1].name, "Outer")
	truthy(tree.children[1].children[1].name == "Inner")
	local untracked = tree.children[#tree.children]
	equal(untracked.name, "[UNTRACKED]")
	near(untracked.stats.p50, 2, 1e-12)
end)

test("profiler rejects mismatched scopes", function()
	local api = Profiler.create(fakeClock(1))
	local ok = pcall(api.End)
	equal(ok, false)
	local reservedOk = pcall(api.Begin, "[UNTRACKED]")
	equal(reservedOk, false)

	local secondApi, finish = Profiler.create(fakeClock(1))
	secondApi.Begin("Open")
	local record, message = finish(2)
	equal(record, nil)
	truthy(string.find(message, "Open", 1, true))
end)

test("random shuffle is reproducible", function()
	local first = { 1, 2, 3, 4, 5, 6 }
	local second = { 1, 2, 3, 4, 5, 6 }
	Random.new(99):shuffle(first)
	Random.new(99):shuffle(second)
	equal(table.concat(first, ","), table.concat(second, ","))
end)

test("runner executes lifecycle, warmups, parameters, and profiles", function()
	local events = {}
	local afterStatus
	local suite = {
		ParameterGenerator = function(runIndex, caseName, isWarmup)
			table.insert(
				events,
				string.format("gen:%s:%d:%s", caseName, runIndex, tostring(isWarmup))
			)
			return runIndex
		end,
		Functions = {
			A = function(profiler, value)
				truthy(value >= 1)
				profiler.Begin("work")
				profiler.End()
			end,
			B = function(_, value)
				truthy(value >= 1)
			end,
		},
		Benchmarkr = {
			Runs = 10,
			WarmupRuns = 2,
			Seed = 42,
			BeforeAll = function()
				table.insert(events, "before")
			end,
			AfterAll = function(status)
				afterStatus = status.status
			end,
		},
	}
	local progress = 0
	local result = Runner.run(suite, nil, {
		onProgress = function()
			progress += 1
		end,
	}, {
		clock = fakeClock(1e-6),
		yieldThread = function() end,
	})
	equal(result.status, "success")
	equal(afterStatus, "success")
	equal(events[1], "before")
	equal(progress, 24)
	equal(#result.cases, 2)
	equal(result.cases[1].stats.count, 10)
	equal(result.config.seed, 42)
	equal(result.cases[1].histogram.minimum, result.cases[2].histogram.minimum)
	equal(result.cases[1].histogram.maximum, result.cases[2].histogram.maximum)
end)

test("runner seed reproduces measured case order", function()
	local function runOrder(seed)
		local order = {}
		local suite = {
			Functions = {
				Alpha = function()
					table.insert(order, "Alpha")
				end,
				Beta = function()
					table.insert(order, "Beta")
				end,
				Gamma = function()
					table.insert(order, "Gamma")
				end,
			},
			Benchmarkr = { Runs = 10, WarmupRuns = 0, Seed = seed },
		}
		local result = Runner.run(suite, nil, nil, {
			clock = fakeClock(1e-6),
			yieldThread = function() end,
		})
		equal(result.status, "success")
		return table.concat(order, ",")
	end

	equal(runOrder(123), runOrder(123))
	truthy(runOrder(123) ~= runOrder(456))
end)

test("parameter generation remains outside measured time", function()
	local clock = fakeClock(1e-6)
	local result = Runner.run({
		ParameterGenerator = function()
			for _ = 1, 100 do
				clock()
			end
		end,
		Functions = { Empty = function() end },
		Benchmarkr = { Runs = 10, WarmupRuns = 0 },
	}, nil, nil, { clock = clock, yieldThread = function() end })
	equal(result.status, "success")
	near(result.cases[1].stats.p50, 1e-6, 1e-12)
end)

test("runner cancellation is atomic", function()
	local progress = 0
	local afterStatus
	local result = Runner.run(
		{
			Functions = { A = function() end },
			Benchmarkr = {
				Runs = 10,
				WarmupRuns = 0,
				AfterAll = function(status)
					afterStatus = status.status
				end,
			},
		},
		nil,
		{
			shouldStop = function()
				return progress >= 3
			end,
			onProgress = function()
				progress += 1
			end,
		},
		{
			clock = fakeClock(1e-6),
			yieldThread = function() end,
		}
	)
	equal(result.status, "cancelled")
	equal(afterStatus, "cancelled")
	equal(progress, 3)
	equal(result.cases, nil)
end)

test("runner reports generator and profiling errors", function()
	local invalidSuite = Runner.run("not a suite", nil, nil, {
		clock = fakeClock(1e-6),
		yieldThread = function() end,
	})
	equal(invalidSuite.status, "error")
	truthy(string.find(invalidSuite.error, "return a table", 1, true))

	local afterStatus
	local generatorFailure = Runner.run({
		ParameterGenerator = function()
			error("generator exploded")
		end,
		Functions = { A = function() end },
		Benchmarkr = {
			Runs = 10,
			WarmupRuns = 0,
			AfterAll = function(status)
				afterStatus = status.status
			end,
		},
	}, nil, nil, { clock = fakeClock(1e-6), yieldThread = function() end })
	equal(generatorFailure.status, "error")
	equal(afterStatus, "error")
	truthy(string.find(generatorFailure.error, "generator exploded", 1, true))

	local profileFailure = Runner.run({
		Functions = {
			A = function(profiler)
				profiler.Begin("never closed")
			end,
		},
		Benchmarkr = { Runs = 10, WarmupRuns = 0 },
	}, nil, nil, { clock = fakeClock(1e-6), yieldThread = function() end })
	equal(profileFailure.status, "error")
	truthy(string.find(profileFailure.error, "never closed", 1, true))
end)

test("reports compact, escape CSV, and round-trip chunks", function()
	local report = sampleReport("suite", 0.001)
	truthy(Report.validate(report))
	local compact = Report.compact(report)
	equal(compact.compact, true)
	equal(compact.cases[1].samples, nil)
	local csv = Report.toCsv(report)
	truthy(string.find(csv, '"Suite, ""quoted"""', 1, true))
	local header = string.match(csv, "[^\n]+")
	local _, commas = string.gsub(header, ",", "")
	equal(commas, 15)
	local baseline = sampleReport("suite", 0.002)
	baseline.cases[1].name = "Removed case"
	local comparisonCsv = Report.toCsv(report, baseline)
	truthy(string.find(comparisonCsv, ",added", 1, true))
	truthy(string.find(comparisonCsv, ",removed", 1, true))
	local content = string.rep("abcdef", 500)
	local chunks = Report.chunk(content, 127)
	equal(Report.join(chunks), content)
	local valid, validationError = Report.validate({ schemaVersion = 1 })
	equal(valid, false)
	truthy(type(validationError) == "string")
end)

test("history evicts recent entries and keeps a separate baseline", function()
	local history = History.normalize(nil)
	for index = 1, 21 do
		local report = sampleReport("suite", index)
		report.createdAt = tostring(index)
		History.add(history, report)
	end
	equal(#history.recent, 20)
	equal(history.recent[1].createdAt, "21")
	equal(history.recent[#history.recent].createdAt, "2")
	local baseline = sampleReport("suite", 10)
	History.pin(history, baseline)
	equal(History.getBaseline(history, "suite").cases[1].stats.p50, 10)
	local comparison = History.compare(sampleReport("suite", 8), baseline)
	near(comparison.matching[1].percent, -20, 1e-9)
end)

test("history comparison marks added, removed, and zero baselines", function()
	local baseline = sampleReport("suite", 0)
	baseline.cases[1].name = "Shared"
	local removed = sampleReport("suite", 1).cases[1]
	removed.name = "Removed"
	table.insert(baseline.cases, removed)

	local current = sampleReport("suite", 2)
	current.cases[1].name = "Shared"
	local added = sampleReport("suite", 3).cases[1]
	added.name = "Added"
	table.insert(current.cases, added)

	local comparison = History.compare(current, baseline)
	equal(comparison.matching[1].percent, nil)
	near(comparison.matching[1].difference, 2, 1e-12)
	equal(comparison.added[1], "Added")
	equal(comparison.removed[1], "Removed")
end)

test("history resets unsupported schemas safely", function()
	local history, reset = History.normalize({ schemaVersion = 99 })
	truthy(reset)
	equal(history.schemaVersion, 1)
	equal(#history.recent, 0)
end)

test("state reducer preserves results on errors and cancellation", function()
	local report = sampleReport("suite", 1)
	local state = State.reduce(State.initial(), { type = "RUN_SUCCESS", result = report })
	state = State.reduce(state, { type = "RUN_ERROR", message = "problem" })
	equal(state.result, report)
	state = State.reduce(state, { type = "RUN_CANCELLED" })
	equal(state.result, report)
	equal(state.mode, "result")
end)

test("state reducer covers selection, progress, history, import, and clear states", function()
	local report = sampleReport("suite", 1)
	local state = State.initial()
	equal(state.mode, "empty")
	state = State.reduce(state, { type = "SELECT_VALID", selection = "module" })
	equal(state.mode, "ready")
	state = State.reduce(state, { type = "RUN_START" })
	equal(state.mode, "running")
	state = State.reduce(state, { type = "RUN_PROGRESS", message = "half" })
	equal(state.message, "half")
	state = State.reduce(state, { type = "VIEW_HISTORY", result = report })
	equal(state.mode, "history")
	state = State.reduce(state, { type = "IMPORT_REPORT", result = report })
	equal(state.mode, "imported")
	state = State.reduce(state, { type = "CLEAR" })
	equal(state.mode, "empty")
	equal(state.result, nil)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("%d test(s) failed", failed), 0)
end
