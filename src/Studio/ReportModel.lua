local Report = require(script.Parent.Parent.Core.Report)

local ReportModel = {}
local REPORT_ATTRIBUTE = "BenchmarkrReportVersion"
local CHUNK_PREFIX = "Chunk_"

function ReportModel.isReport(instance)
	return instance
		and instance:IsA("Folder")
		and instance:GetAttribute(REPORT_ATTRIBUTE) == Report.SCHEMA_VERSION
end

function ReportModel.create(json, csv, createdAt)
	local folder = Instance.new("Folder")
	folder.Name = "BenchmarkrReport_" .. string.gsub(createdAt or "Report", "[^%w]", "_")
	folder:SetAttribute(REPORT_ATTRIBUTE, Report.SCHEMA_VERSION)
	folder:SetAttribute("ChunkCount", 0)

	local chunks = Report.chunk(json)
	folder:SetAttribute("ChunkCount", #chunks)
	for index, chunk in ipairs(chunks) do
		local value = Instance.new("StringValue")
		value.Name = string.format("%s%05d", CHUNK_PREFIX, index)
		value.Value = chunk
		value.Parent = folder
	end

	local summary = Instance.new("StringValue")
	summary.Name = "SummaryCsv"
	summary.Value = csv
	summary.Parent = folder
	return folder
end

function ReportModel.read(folder)
	if not ReportModel.isReport(folder) then
		return nil, "The selected folder is not a Benchmarkr v1 report."
	end
	local chunks = {}
	for _, child in ipairs(folder:GetChildren()) do
		if
			child:IsA("StringValue")
			and string.sub(child.Name, 1, #CHUNK_PREFIX) == CHUNK_PREFIX
		then
			table.insert(chunks, child)
		end
	end
	table.sort(chunks, function(left, right)
		return left.Name < right.Name
	end)
	if #chunks ~= folder:GetAttribute("ChunkCount") then
		return nil, "The report is incomplete or has missing chunks."
	end
	local values = table.create(#chunks)
	for index, chunk in ipairs(chunks) do
		values[index] = chunk.Value
	end
	return Report.join(values)
end

function ReportModel.promptSave(plugin, services, json, csv, createdAt)
	local previousSelection = services.Selection:Get()
	local folder = ReportModel.create(json, csv, createdAt)
	folder.Parent = services.ServerStorage
	services.Selection:Set({ folder })

	local ok, saved = pcall(plugin.PromptSaveSelectionAsync, plugin, folder.Name)
	folder:Destroy()

	local restored = {}
	for _, instance in ipairs(previousSelection) do
		if instance.Parent then
			table.insert(restored, instance)
		end
	end
	services.Selection:Set(restored)

	if not ok then
		return false, saved
	end
	return saved == true
end

return ReportModel
