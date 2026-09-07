local Report = {}

Report.SCHEMA_VERSION = 1
Report.CHUNK_SIZE = 100000

local function csvCell(value)
	if value == nil then
		return ""
	end
	local text = tostring(value)
	if string.find(text, '[,\n\r"]') then
		return '"' .. string.gsub(text, '"', '""') .. '"'
	end
	return text
end

local function caseMap(report)
	local result = {}
	if report then
		for _, case in ipairs(report.cases or {}) do
			result[case.name] = case
		end
	end
	return result
end

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local REQUIRED_STATS = { "count", "min", "max", "total", "mean", "p10", "p50", "p90" }

local function validStats(stats)
	if type(stats) ~= "table" then
		return false
	end
	for _, key in ipairs(REQUIRED_STATS) do
		if not finite(stats[key]) then
			return false
		end
	end
	return true
end

local function validProfile(node)
	if
		type(node) ~= "table"
		or type(node.name) ~= "string"
		or type(node.path) ~= "string"
		or not validStats(node.stats)
		or type(node.children) ~= "table"
	then
		return false
	end
	for _, child in ipairs(node.children) do
		if not validProfile(child) then
			return false
		end
	end
	return true
end

function Report.validate(report)
	if type(report) ~= "table" or report.schemaVersion ~= Report.SCHEMA_VERSION then
		return false, "unsupported report schema"
	end
	if type(report.createdAt) ~= "string" then
		return false, "report timestamp is missing"
	end
	if
		type(report.suite) ~= "table"
		or type(report.suite.id) ~= "string"
		or type(report.suite.name) ~= "string"
		or report.suite.id == ""
		or report.suite.name == ""
	then
		return false, "report suite identity is invalid"
	end
	if
		type(report.config) ~= "table"
		or not finite(report.config.runs)
		or report.config.runs < 1
		or report.config.runs % 1 ~= 0
		or not finite(report.config.warmupRuns)
		or report.config.warmupRuns < 0
		or report.config.warmupRuns % 1 ~= 0
		or type(report.config.randomizeOrder) ~= "boolean"
		or not finite(report.config.seed)
		or not finite(report.timerFloor)
		or report.timerFloor < 0
	then
		return false, "report configuration is invalid"
	end
	if type(report.cases) ~= "table" or #report.cases == 0 then
		return false, "report must contain benchmark cases"
	end

	for _, case in ipairs(report.cases) do
		if type(case) ~= "table" or type(case.name) ~= "string" or case.name == "" then
			return false, "report contains an invalid case"
		end
		if not validStats(case.stats) then
			return false, "report case statistics are missing"
		end
		if
			type(case.histogram) ~= "table"
			or type(case.histogram.counts) ~= "table"
			or type(case.histogram.density) ~= "table"
			or not finite(case.histogram.minimum)
			or not finite(case.histogram.maximum)
			or not finite(case.histogram.sampleMinimum)
			or not finite(case.histogram.sampleMaximum)
			or not finite(case.histogram.binWidth)
			or not finite(case.histogram.maxDensity)
			or case.histogram.maximum <= case.histogram.minimum
			or case.histogram.binWidth <= 0
			or #case.histogram.counts == 0
			or #case.histogram.counts ~= #case.histogram.density
		then
			return false, "report contains an invalid histogram"
		end
		for index, count in ipairs(case.histogram.counts) do
			if
				not finite(count)
				or count < 0
				or not finite(case.histogram.density[index])
				or case.histogram.density[index] < 0
			then
				return false, "report contains invalid histogram bins"
			end
		end
		if type(case.trace) ~= "table" or #case.trace == 0 then
			return false, "report contains invalid graph or profiler data"
		end
		for _, point in ipairs(case.trace) do
			if type(point) ~= "table" or not finite(point.index) or not finite(point.value) then
				return false, "report contains invalid sample points"
			end
		end
		if not validProfile(case.profile) then
			return false, "report contains invalid profiler data"
		end
	end
	return true
end

function Report.create(details, result)
	return {
		schemaVersion = Report.SCHEMA_VERSION,
		createdAt = details.createdAt,
		suite = {
			id = details.suiteId,
			name = details.suiteName,
			path = details.sourcePath,
		},
		environment = {
			placeId = details.placeId,
			gameId = details.gameId,
			studioVersion = details.studioVersion,
		},
		config = result.config,
		timerFloor = result.timerFloor,
		cases = result.cases,
	}
end

function Report.compact(report)
	local compactCases = table.create(#report.cases)
	for index, case in ipairs(report.cases) do
		compactCases[index] = {
			name = case.name,
			stats = case.stats,
			histogram = case.histogram,
			trace = case.trace,
			profile = case.profile,
			nearTimerFloor = case.nearTimerFloor,
		}
	end

	return {
		schemaVersion = report.schemaVersion,
		createdAt = report.createdAt,
		suite = report.suite,
		environment = report.environment,
		config = report.config,
		timerFloor = report.timerFloor,
		cases = compactCases,
		compact = true,
	}
end

function Report.toCsv(report, baseline)
	local rows = {
		{
			"created_at",
			"suite_id",
			"suite_name",
			"case",
			"count",
			"p10_seconds",
			"p50_seconds",
			"p90_seconds",
			"min_seconds",
			"max_seconds",
			"mean_seconds",
			"total_seconds",
			"baseline_p50_seconds",
			"delta_seconds",
			"delta_percent",
			"comparison_status",
		},
	}
	local baselineCases = caseMap(baseline)
	local currentCases = caseMap(report)
	local columnCount = #rows[1]

	for _, case in ipairs(report.cases) do
		local stats = case.stats
		local baselineCase = baselineCases[case.name]
		local baselineMedian = baselineCase and baselineCase.stats.p50 or nil
		local difference = baselineMedian and stats.p50 - baselineMedian or nil
		local percent = baselineMedian and baselineMedian ~= 0 and difference / baselineMedian * 100
			or nil
		local comparisonStatus = if not baseline
			then "none"
			elseif baselineCase then "matched"
			else "added"
		local values = {
			report.createdAt,
			report.suite.id,
			report.suite.name,
			case.name,
			stats.count,
			stats.p10,
			stats.p50,
			stats.p90,
			stats.min,
			stats.max,
			stats.mean,
			stats.total,
			baselineMedian,
			difference,
			percent,
			comparisonStatus,
		}
		local row = table.create(columnCount, "")
		for index = 1, columnCount do
			row[index] = values[index]
		end
		table.insert(rows, row)
	end

	if baseline then
		for _, baselineCase in ipairs(baseline.cases) do
			if not currentCases[baselineCase.name] then
				local values = {
					report.createdAt,
					report.suite.id,
					report.suite.name,
					baselineCase.name,
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
					baselineCase.stats.p50,
					nil,
					nil,
					"removed",
				}
				local row = table.create(columnCount, "")
				for index = 1, columnCount do
					row[index] = values[index]
				end
				table.insert(rows, row)
			end
		end
	end

	local lines = table.create(#rows)
	for rowIndex, row in ipairs(rows) do
		local cells = table.create(columnCount)
		for columnIndex = 1, columnCount do
			local value = row[columnIndex]
			cells[columnIndex] = csvCell(value)
		end
		lines[rowIndex] = table.concat(cells, ",")
	end
	return table.concat(lines, "\n")
end

function Report.chunk(text, chunkSize)
	chunkSize = chunkSize or Report.CHUNK_SIZE
	local chunks = {}
	for startIndex = 1, #text, chunkSize do
		table.insert(chunks, string.sub(text, startIndex, startIndex + chunkSize - 1))
	end
	if #chunks == 0 then
		chunks[1] = ""
	end
	return chunks
end

function Report.join(chunks)
	return table.concat(chunks)
end

return Report
