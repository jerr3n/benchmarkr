local Report = if script then require(script.Parent.Report) else require("./Report")

local History = {}
History.SCHEMA_VERSION = 1
History.MAX_RECENT = 20

local function fresh()
	return {
		schemaVersion = History.SCHEMA_VERSION,
		nextId = 1,
		recent = {},
		baselines = {},
	}
end

function History.normalize(value)
	if type(value) ~= "table" or value.schemaVersion ~= History.SCHEMA_VERSION then
		return fresh(), value ~= nil
	end
	if type(value.recent) ~= "table" or type(value.baselines) ~= "table" then
		return fresh(), true
	end

	local normalized = fresh()
	local nextId = tonumber(value.nextId)
	if nextId and nextId >= 1 and nextId % 1 == 0 then
		normalized.nextId = nextId
	end
	local changed = normalized.nextId ~= value.nextId or #value.recent > History.MAX_RECENT
	local largestId = 0
	for _, entry in ipairs(value.recent) do
		if
			type(entry) == "table"
			and type(entry.id) == "number"
			and entry.id >= 1
			and entry.id % 1 == 0
			and math.abs(entry.id) ~= math.huge
			and type(entry.suiteId) == "string"
			and entry.suiteId ~= ""
			and type(entry.createdAt) == "string"
			and entry.createdAt ~= ""
			and Report.validate(entry.report)
			and entry.report.suite.id == entry.suiteId
		then
			table.insert(normalized.recent, entry)
			largestId = math.max(largestId, entry.id)
			if #normalized.recent >= History.MAX_RECENT then
				break
			end
		else
			changed = true
		end
	end
	if normalized.nextId <= largestId then
		normalized.nextId = largestId + 1
		changed = true
	end
	for suiteId, report in pairs(value.baselines) do
		if type(suiteId) == "string" and Report.validate(report) and report.suite.id == suiteId then
			normalized.baselines[suiteId] = report
		else
			changed = true
		end
	end
	return normalized, changed
end

function History.add(state, report)
	local entry = {
		id = state.nextId,
		suiteId = report.suite.id,
		createdAt = report.createdAt,
		report = Report.compact(report),
	}
	state.nextId += 1
	table.insert(state.recent, 1, entry)
	while #state.recent > History.MAX_RECENT do
		table.remove(state.recent)
	end
	return entry
end

function History.pin(state, report)
	state.baselines[report.suite.id] = Report.compact(report)
	return state.baselines[report.suite.id]
end

function History.unpin(state, suiteId)
	state.baselines[suiteId] = nil
end

function History.getBaseline(state, suiteId)
	return state.baselines[suiteId]
end

function History.compare(current, baseline)
	local comparison = { matching = {}, added = {}, removed = {} }
	if not baseline then
		return comparison
	end

	local currentByName = {}
	local baselineByName = {}
	for _, case in ipairs(current.cases) do
		currentByName[case.name] = case
	end
	for _, case in ipairs(baseline.cases) do
		baselineByName[case.name] = case
	end

	for _, case in ipairs(current.cases) do
		local old = baselineByName[case.name]
		if old then
			local difference = case.stats.p50 - old.stats.p50
			table.insert(comparison.matching, {
				name = case.name,
				current = case.stats.p50,
				baseline = old.stats.p50,
				difference = difference,
				percent = old.stats.p50 ~= 0 and difference / old.stats.p50 * 100 or nil,
			})
		else
			table.insert(comparison.added, case.name)
		end
	end
	for _, case in ipairs(baseline.cases) do
		if not currentByName[case.name] then
			table.insert(comparison.removed, case.name)
		end
	end

	return comparison
end

return History
