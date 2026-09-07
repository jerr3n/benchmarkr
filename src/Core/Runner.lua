local Histogram = if script then require(script.Parent.Histogram) else require("./Histogram")
local Profiler = if script then require(script.Parent.Profiler) else require("./Profiler")
local Random = if script then require(script.Parent.Random) else require("./Random")
local Stats = if script then require(script.Parent.Stats) else require("./Stats")
local Trace = if script then require(script.Parent.Trace) else require("./Trace")

local Runner = {}

local DEFAULT_RUNS = 500
local DEFAULT_WARMUPS = 25
local YIELD_INTERVAL = 20

local function traceback(message)
	return debug.traceback(tostring(message), 2)
end

local function failure(message)
	return { status = "error", error = message }
end

local function positiveInteger(value, name, minimum, maximum)
	if type(value) ~= "number" or value % 1 ~= 0 or value < minimum or value > maximum then
		return nil, string.format("%s must be an integer between %d and %d", name, minimum, maximum)
	end
	return value
end

function Runner.validate(suite, overrides)
	if type(suite) ~= "table" then
		return nil, "benchmark ModuleScript must return a table"
	end
	if type(suite.Functions) ~= "table" then
		return nil, "benchmark suite must contain a Functions table"
	end
	if suite.ParameterGenerator ~= nil and type(suite.ParameterGenerator) ~= "function" then
		return nil, "ParameterGenerator must be a function when provided"
	end

	local extension = suite.Benchmarkr or {}
	if type(extension) ~= "table" then
		return nil, "Benchmarkr must be a table when provided"
	end
	for _, hookName in ipairs({ "BeforeAll", "AfterAll" }) do
		if extension[hookName] ~= nil and type(extension[hookName]) ~= "function" then
			return nil, "Benchmarkr." .. hookName .. " must be a function when provided"
		end
	end
	for _, textName in ipairs({ "Id", "Name" }) do
		if
			extension[textName] ~= nil
			and (type(extension[textName]) ~= "string" or extension[textName] == "")
		then
			return nil, "Benchmarkr." .. textName .. " must be a non-empty string when provided"
		end
	end

	local caseNames = {}
	for name, callback in pairs(suite.Functions) do
		if type(name) ~= "string" or name == "" then
			return nil, "every Functions key must be a non-empty string"
		end
		if type(callback) ~= "function" then
			return nil, string.format("Functions[%q] must be a function", name)
		end
		table.insert(caseNames, name)
	end
	if #caseNames == 0 then
		return nil, "Functions must contain at least one benchmark case"
	end
	table.sort(caseNames)

	overrides = overrides or {}
	local runs, runsError =
		positiveInteger(overrides.runs or extension.Runs or DEFAULT_RUNS, "Runs", 10, 10000)
	if not runs then
		return nil, runsError
	end
	local warmups, warmupsError = positiveInteger(
		overrides.warmupRuns or extension.WarmupRuns or DEFAULT_WARMUPS,
		"WarmupRuns",
		0,
		1000
	)
	if not warmups then
		return nil, warmupsError
	end

	local randomize = extension.RandomizeOrder
	if randomize == nil then
		randomize = true
	elseif type(randomize) ~= "boolean" then
		return nil, "Benchmarkr.RandomizeOrder must be a boolean"
	end

	local seed = overrides.seed or extension.Seed
	if seed ~= nil and (type(seed) ~= "number" or seed ~= seed or math.abs(seed) == math.huge) then
		return nil, "Benchmarkr.Seed must be a finite number"
	end

	return {
		caseNames = caseNames,
		runs = runs,
		warmupRuns = warmups,
		randomizeOrder = randomize,
		seed = seed,
		name = type(extension.Name) == "string" and extension.Name or nil,
		id = type(extension.Id) == "string" and extension.Id or nil,
		beforeAll = extension.BeforeAll,
		afterAll = extension.AfterAll,
	}
end

local function protected(callback)
	local ok, value = xpcall(callback, traceback)
	if ok then
		return true, value
	end
	return false, value
end

local function invokeGenerator(generator, runIndex, caseName, isWarmup)
	local packed
	local ok, err = protected(function()
		packed = table.pack(generator(runIndex, caseName, isWarmup))
	end)
	return ok, packed, err
end

local function invokeCase(callback, arguments, clock)
	local api, finishProfile = Profiler.create(clock)
	local duration
	local ok, err = protected(function()
		local startedAt = clock()
		callback(api, table.unpack(arguments, 1, arguments.n))
		duration = math.max(0, clock() - startedAt)
	end)
	if not ok then
		return nil, err
	end

	local profile, profileError = finishProfile(duration)
	if not profile then
		return nil, profileError
	end
	return { duration = duration, profile = profile }
end

local function runAfterAll(afterAll, status)
	if not afterAll then
		return true
	end
	local ok, err = protected(function()
		afterAll(status)
	end)
	return ok, err
end

function Runner.run(suite, overrides, callbacks, dependencies)
	callbacks = callbacks or {}
	dependencies = dependencies or {}
	local clock = dependencies.clock or os.clock
	local yieldThread = dependencies.yieldThread or function()
		task.wait()
	end
	local config, validationError = Runner.validate(suite, overrides)
	if not config then
		return failure(validationError)
	end
	local generator = suite.ParameterGenerator or function() end

	if config.seed == nil then
		config.seed = (os.time() * 1000003 + math.floor(clock() * 1e9)) % 2147483647
	end
	config.seed = math.max(1, math.floor(math.abs(config.seed)) % 2147483647)

	local random = Random.new(config.seed)
	local caseResults = {}
	for _, name in ipairs(config.caseNames) do
		caseResults[name] = { samples = {}, profiles = {} }
	end

	local invocationCount = (config.warmupRuns + config.runs) * #config.caseNames
	local completed = 0
	local lifecycleStarted = false

	local function finishWith(status)
		local afterOk, afterError = runAfterAll(config.afterAll, status)
		if not afterOk then
			if status.status == "error" then
				return failure(
					status.error .. "\n\nBenchmarkr.AfterAll also failed:\n" .. afterError
				)
			end
			return failure("Benchmarkr.AfterAll failed:\n" .. afterError)
		end
		return status
	end

	if config.beforeAll then
		local ok, err = protected(config.beforeAll)
		if not ok then
			return failure("Benchmarkr.BeforeAll failed:\n" .. err)
		end
	end
	lifecycleStarted = true

	local function runOne(runIndex, caseName, isWarmup)
		if callbacks.shouldStop and callbacks.shouldStop() then
			return nil, "cancelled"
		end

		local generatedOk, arguments, generatorError =
			invokeGenerator(generator, runIndex, caseName, isWarmup)
		if not generatedOk then
			return nil,
				string.format(
					"ParameterGenerator failed for %s run %d:\n%s",
					caseName,
					runIndex,
					generatorError
				)
		end

		local sample, sampleError = invokeCase(suite.Functions[caseName], arguments, clock)
		if not sample then
			return nil,
				string.format("Benchmark %q failed on run %d:\n%s", caseName, runIndex, sampleError)
		end

		if not isWarmup then
			local result = caseResults[caseName]
			table.insert(result.samples, sample.duration)
			table.insert(result.profiles, sample.profile)
		end

		completed += 1
		if callbacks.onProgress then
			callbacks.onProgress(
				completed,
				invocationCount,
				isWarmup and "Warmup" or "Measure",
				caseName
			)
		end
		if completed % YIELD_INTERVAL == 0 then
			yieldThread()
		end
		return true
	end

	for runIndex = 1, config.warmupRuns do
		for _, caseName in ipairs(config.caseNames) do
			local ok, err = runOne(runIndex, caseName, true)
			if not ok then
				if err == "cancelled" then
					return finishWith({ status = "cancelled" })
				end
				return finishWith(failure(err))
			end
		end
	end

	for runIndex = 1, config.runs do
		local order = table.clone(config.caseNames)
		if config.randomizeOrder then
			random:shuffle(order)
		end
		for _, caseName in ipairs(order) do
			local ok, err = runOne(runIndex, caseName, false)
			if not ok then
				if err == "cancelled" then
					return finishWith({ status = "cancelled" })
				end
				return finishWith(failure(err))
			end
		end
	end

	local timerFloor = Stats.timerFloor(clock)
	local histogramInput = table.create(#config.caseNames)
	for index, name in ipairs(config.caseNames) do
		histogramInput[index] = { name = name, samples = caseResults[name].samples }
	end
	local sharedHistograms = Histogram.shared(histogramInput, 48)
	local histogramByName = {}
	for _, item in ipairs(sharedHistograms) do
		histogramByName[item.name] = item.histogram
	end
	local cases = table.create(#config.caseNames)
	for _, name in ipairs(config.caseNames) do
		local raw = caseResults[name]
		local stats = Stats.summarize(raw.samples)
		table.insert(cases, {
			name = name,
			samples = raw.samples,
			stats = stats,
			histogram = histogramByName[name],
			trace = Trace.downsample(raw.samples, 300),
			profile = Profiler.aggregate(raw.profiles),
			nearTimerFloor = timerFloor > 0 and stats.p50 <= timerFloor * 10,
		})
	end

	local result = {
		status = "success",
		config = {
			runs = config.runs,
			warmupRuns = config.warmupRuns,
			randomizeOrder = config.randomizeOrder,
			seed = config.seed,
		},
		suite = {
			id = config.id,
			name = config.name,
		},
		timerFloor = timerFloor,
		cases = cases,
	}

	if lifecycleStarted then
		return finishWith(result)
	end
	return result
end

return Runner
