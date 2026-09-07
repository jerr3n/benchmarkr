local Histogram = {}

local DEFAULT_BINS = 48

local function bounds(values)
	local minimum = math.huge
	local maximum = -math.huge
	for _, value in ipairs(values) do
		minimum = math.min(minimum, value)
		maximum = math.max(maximum, value)
	end
	return minimum, maximum
end

local function expandedBounds(minimum, maximum)
	if minimum ~= maximum then
		return minimum, maximum
	end
	local padding = math.max(math.abs(minimum) * 0.05, 1e-12)
	return minimum - padding, maximum + padding
end

function Histogram.build(values, binCount, minimum, maximum)
	assert(#values > 0, "cannot build a histogram for an empty sample")
	binCount = binCount or DEFAULT_BINS
	assert(binCount >= 1 and binCount % 1 == 0, "bin count must be a positive integer")

	local sampleMin, sampleMax = bounds(values)
	minimum = minimum or sampleMin
	maximum = maximum or sampleMax
	minimum, maximum = expandedBounds(minimum, maximum)
	local width = (maximum - minimum) / binCount
	local counts = table.create(binCount, 0)
	local density = table.create(binCount, 0)

	for _, value in ipairs(values) do
		local index = math.floor((value - minimum) / width) + 1
		index = math.clamp(index, 1, binCount)
		counts[index] += 1
	end

	local maxDensity = 0
	for index, count in ipairs(counts) do
		density[index] = count / #values
		maxDensity = math.max(maxDensity, density[index])
	end

	return {
		minimum = minimum,
		maximum = maximum,
		sampleMinimum = sampleMin,
		sampleMaximum = sampleMax,
		binWidth = width,
		counts = counts,
		density = density,
		maxDensity = maxDensity,
		sampleCount = #values,
	}
end

function Histogram.shared(series, binCount)
	local minimum = math.huge
	local maximum = -math.huge
	for _, item in ipairs(series) do
		local itemMin, itemMax = bounds(item.samples)
		minimum = math.min(minimum, itemMin)
		maximum = math.max(maximum, itemMax)
	end
	assert(minimum ~= math.huge, "cannot build a shared histogram without series")
	minimum, maximum = expandedBounds(minimum, maximum)

	local result = {}
	for _, item in ipairs(series) do
		table.insert(result, {
			name = item.name,
			histogram = Histogram.build(item.samples, binCount, minimum, maximum),
		})
	end
	return result, minimum, maximum
end

return Histogram
