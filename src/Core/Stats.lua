local Stats = {}

local UNITS = {
	{ name = "s", scale = 1 },
	{ name = "ms", scale = 1e3 },
	{ name = utf8.char(181) .. "s", scale = 1e6 },
	{ name = "ns", scale = 1e9 },
}

local function copyAndSort(values)
	local sorted = table.create(#values)
	for index, value in ipairs(values) do
		assert(
			type(value) == "number" and value == value and math.abs(value) ~= math.huge,
			"samples must contain finite numbers"
		)
		sorted[index] = value
	end
	table.sort(sorted)
	return sorted
end

function Stats.quantile(sorted, percentile)
	assert(#sorted > 0, "cannot calculate a quantile for an empty sample")
	assert(percentile >= 0 and percentile <= 1, "percentile must be between zero and one")

	if #sorted == 1 then
		return sorted[1]
	end

	local position = 1 + (#sorted - 1) * percentile
	local lower = math.floor(position)
	local upper = math.ceil(position)
	local weight = position - lower
	return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
end

function Stats.summarize(values)
	assert(#values > 0, "cannot summarize an empty sample")
	local sorted = copyAndSort(values)
	local total = 0
	for _, value in ipairs(sorted) do
		total += value
	end

	return {
		count = #sorted,
		min = sorted[1],
		max = sorted[#sorted],
		total = total,
		mean = total / #sorted,
		p10 = Stats.quantile(sorted, 0.1),
		p50 = Stats.quantile(sorted, 0.5),
		p90 = Stats.quantile(sorted, 0.9),
	}
end

function Stats.chooseUnit(seconds)
	local magnitude = math.abs(seconds)
	if magnitude >= 1 then
		return UNITS[1]
	elseif magnitude >= 1e-3 then
		return UNITS[2]
	elseif magnitude >= 1e-6 then
		return UNITS[3]
	else
		return UNITS[4]
	end
end

function Stats.formatDuration(seconds, unit)
	unit = unit or Stats.chooseUnit(seconds)
	local value = seconds * unit.scale
	local decimals = 3
	if math.abs(value) >= 100 then
		decimals = 1
	elseif math.abs(value) >= 10 then
		decimals = 2
	end
	return string.format("%." .. decimals .. "f %s", value, unit.name)
end

function Stats.timerFloor(clock, attempts)
	attempts = attempts or 2000
	local floor = math.huge
	local previous = clock()
	for _ = 1, attempts do
		local current = clock()
		local difference = current - previous
		if difference > 0 and difference < floor then
			floor = difference
		end
		previous = current
	end
	if floor == math.huge then
		return 0
	end
	return floor
end

return Stats
