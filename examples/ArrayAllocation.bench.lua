-- Select this ModuleScript in Explorer and run it with Benchmarkr.

return {
	ParameterGenerator = function()
		return math.random(1, 1000)
	end,

	Functions = {
		["table.create"] = function(Profiler, value)
			Profiler.Begin("Allocate")
			local output = table.create(200)
			Profiler.End()

			Profiler.Begin("Fill")
			for index = 1, 200 do
				output[index] = value
			end
			Profiler.End()
		end,

		["empty table"] = function(Profiler, value)
			Profiler.Begin("Allocate")
			local output = {}
			Profiler.End()

			Profiler.Begin("Fill")
			for index = 1, 200 do
				output[index] = value
			end
			Profiler.End()
		end,
	},

	Benchmarkr = {
		Id = "example-array-allocation",
		Name = "Array allocation",
		Runs = 500,
		WarmupRuns = 25,
		RandomizeOrder = true,
	},
}
