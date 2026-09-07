local Trace = {}

function Trace.downsample(samples, maximumPoints)
	maximumPoints = maximumPoints or 300
	assert(maximumPoints >= 1 and maximumPoints % 1 == 0, "maximum points must be an integer")
	if #samples <= maximumPoints then
		local result = table.create(#samples)
		for index, value in ipairs(samples) do
			result[index] = { index = index, value = value }
		end
		return result
	end
	if maximumPoints == 1 then
		return { { index = 1, value = samples[1] } }
	elseif maximumPoints == 2 then
		return {
			{ index = 1, value = samples[1] },
			{ index = #samples, value = samples[#samples] },
		}
	end

	-- Largest-Triangle-Three-Buckets keeps the overall shape and isolated spikes while
	-- bounding the number of GUI objects needed by the interactive line graph.
	local result = table.create(maximumPoints)
	result[1] = { index = 1, value = samples[1] }
	local every = (#samples - 2) / (maximumPoints - 2)
	local selectedIndex = 1

	for bucket = 0, maximumPoints - 3 do
		local averageStart = math.floor((bucket + 1) * every) + 2
		local averageEnd = math.min(math.floor((bucket + 2) * every) + 2, #samples + 1)
		local averageX = 0
		local averageY = 0
		local averageCount = math.max(1, averageEnd - averageStart)
		for index = averageStart, averageEnd - 1 do
			averageX += index
			averageY += samples[index]
		end
		averageX /= averageCount
		averageY /= averageCount

		local rangeStart = math.floor(bucket * every) + 2
		local rangeEnd = math.min(math.floor((bucket + 1) * every) + 2, #samples)
		local selectedX = selectedIndex
		local selectedY = samples[selectedIndex]
		local largestArea = -1
		local nextIndex = rangeStart
		for index = rangeStart, rangeEnd do
			local area = math.abs(
				(selectedX - averageX) * (samples[index] - selectedY)
					- (selectedX - index) * (averageY - selectedY)
			)
			if area > largestArea then
				largestArea = area
				nextIndex = index
			end
		end

		selectedIndex = nextIndex
		result[bucket + 2] = { index = selectedIndex, value = samples[selectedIndex] }
	end
	result[maximumPoints] = { index = #samples, value = samples[#samples] }
	return result
end

return Trace
