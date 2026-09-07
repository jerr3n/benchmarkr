local ErrorBars = {}

function ErrorBars.point(case)
	local stats = case and case.stats
	if not stats then
		return nil
	end
	return {
		name = case.name,
		lower = stats.p10,
		center = stats.p50,
		upper = stats.p90,
	}
end

function ErrorBars.categories(report, baseline, visible)
	visible = visible or {}
	local names = {}
	local included = {}
	for _, source in ipairs({ report, baseline }) do
		if source then
			for _, case in ipairs(source.cases or {}) do
				if visible[case.name] ~= false and not included[case.name] then
					included[case.name] = true
					table.insert(names, case.name)
				end
			end
		end
	end
	return names
end

function ErrorBars.bounds(points)
	local minimum = math.huge
	local maximum = -math.huge
	for _, point in ipairs(points) do
		minimum = math.min(minimum, point.lower)
		maximum = math.max(maximum, point.upper)
	end
	if minimum == math.huge then
		return 0, 1
	end
	if minimum == maximum then
		local padding = math.max(math.abs(minimum) * 0.05, 1e-12)
		minimum -= padding
		maximum += padding
	end
	return minimum, maximum
end

return ErrorBars
