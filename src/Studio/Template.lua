local Template = {}

Template.SOURCE = [=[-- Benchmarkr suites execute in the real Studio environment.
-- Keep destructive or persistent operations out of benchmark cases.

return {
	ParameterGenerator = function(runIndex, caseName, isWarmup)
		-- This runs outside the timer. Return any values your cases need.
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
			Profiler.Begin("Allocate")
			local output = {}
			Profiler.End()

			Profiler.Begin("Fill")
			for index = 1, 100 do
				output[index] = value
			end
			Profiler.End()
		end,
	},

	Benchmarkr = {
		-- Id = "my-stable-suite-id", -- Optional; keeps history attached if this script moves.
		Name = "Array allocation",
		Runs = 500,
		WarmupRuns = 25,
		RandomizeOrder = true,
	},
}
]=]

local function destinationFromSelection(selection, serverStorage)
	local selected = selection:Get()
	if #selected ~= 1 then
		return serverStorage
	end
	local instance = selected[1]
	if instance:IsA("ModuleScript") then
		return instance.Parent or serverStorage
	end
	if instance:IsA("Folder") or instance:IsA("Model") or instance:IsA("LuaSourceContainer") then
		return instance
	end
	return serverStorage
end

function Template.create(services)
	local recording
	pcall(function()
		recording = services.ChangeHistoryService:TryBeginRecording("Create Benchmarkr suite")
	end)

	local moduleScript = Instance.new("ModuleScript")
	local destination = destinationFromSelection(services.Selection, services.ServerStorage)
	local name = "Benchmark"
	local suffix = 2
	while destination:FindFirstChild(name) do
		name = "Benchmark" .. suffix
		suffix += 1
	end
	moduleScript.Name = name
	moduleScript.Parent = destination

	local sourceOk, sourceError = pcall(function()
		services.ScriptEditorService:UpdateSourceAsync(moduleScript, function()
			return Template.SOURCE
		end)
	end)
	if not sourceOk then
		moduleScript:Destroy()
		if recording then
			pcall(
				services.ChangeHistoryService.FinishRecording,
				services.ChangeHistoryService,
				recording,
				Enum.FinishRecordingOperation.Cancel
			)
		end
		return nil, sourceError
	end

	services.Selection:Set({ moduleScript })
	pcall(
		services.ScriptEditorService.OpenScriptDocumentAsync,
		services.ScriptEditorService,
		moduleScript
	)
	if recording then
		pcall(
			services.ChangeHistoryService.FinishRecording,
			services.ChangeHistoryService,
			recording,
			Enum.FinishRecordingOperation.Commit
		)
	else
		pcall(
			services.ChangeHistoryService.SetWaypoint,
			services.ChangeHistoryService,
			"Create Benchmarkr suite"
		)
	end
	return moduleScript
end

return Template
