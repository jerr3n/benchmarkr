local Loader = {}

local function traceback(message)
	return debug.traceback(tostring(message), 2)
end

local function syncSources(original, clone, scriptEditorService)
	if original:IsA("LuaSourceContainer") and clone:IsA("LuaSourceContainer") then
		local ok, source = pcall(scriptEditorService.GetEditorSource, scriptEditorService, original)
		if ok and type(source) == "string" then
			clone.Source = source
		end
	end

	local originalChildren = original:GetChildren()
	local cloneChildren = clone:GetChildren()
	for index, child in ipairs(originalChildren) do
		if cloneChildren[index] then
			syncSources(child, cloneChildren[index], scriptEditorService)
		end
	end
end

function Loader.load(moduleScript, services)
	assert(moduleScript and moduleScript:IsA("ModuleScript"), "Loader.load expects a ModuleScript")
	local wasArchivable = moduleScript.Archivable
	moduleScript.Archivable = true
	local clone = moduleScript:Clone()
	moduleScript.Archivable = wasArchivable
	if not clone then
		return nil, "The selected ModuleScript could not be cloned."
	end

	local ok, result = xpcall(function()
		syncSources(moduleScript, clone, services.ScriptEditorService)
		clone.Name = moduleScript.Name
			.. "__Benchmarkr_"
			.. services.HttpService:GenerateGUID(false)
		clone.Parent = moduleScript.Parent
		return require(clone)
	end, traceback)

	if not ok then
		clone:Destroy()
		return nil, result
	end

	local cleaned = false
	local function cleanup()
		if not cleaned then
			cleaned = true
			clone:Destroy()
		end
	end
	return result, nil, cleanup
end

return Loader
