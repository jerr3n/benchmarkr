local State = {}

function State.initial()
	return {
		mode = "empty",
		selection = nil,
		result = nil,
		message = "Select a benchmark ModuleScript to begin.",
	}
end

function State.reduce(state, action)
	local nextState = table.clone(state)
	if action.type == "SELECT_VALID" then
		nextState.mode = "ready"
		nextState.selection = action.selection
		nextState.message = action.message or "Ready to benchmark."
	elseif action.type == "SELECT_INVALID" then
		nextState.mode = "empty"
		nextState.selection = nil
		nextState.message = action.message
	elseif action.type == "RUN_START" then
		nextState.mode = "running"
		nextState.message = "Starting benchmark..."
	elseif action.type == "RUN_PROGRESS" then
		nextState.mode = "running"
		nextState.message = action.message
	elseif action.type == "RUN_SUCCESS" then
		nextState.mode = "result"
		nextState.result = action.result
		nextState.message = "Benchmark complete."
	elseif action.type == "RUN_ERROR" then
		nextState.mode = "error"
		nextState.message = action.message
	elseif action.type == "RUN_CANCELLED" then
		nextState.mode = nextState.result and "result" or "ready"
		nextState.message = "Benchmark stopped. Previous results were preserved."
	elseif action.type == "IMPORT_REPORT" then
		nextState.mode = "imported"
		nextState.selection = nil
		nextState.result = action.result
		nextState.message = "Viewing an imported report."
	elseif action.type == "VIEW_HISTORY" then
		nextState.mode = "history"
		nextState.result = action.result
		nextState.message = "Viewing a saved result."
	elseif action.type == "CLEAR" then
		return State.initial()
	else
		error("unknown state action: " .. tostring(action.type))
	end
	return nextState
end

return State
