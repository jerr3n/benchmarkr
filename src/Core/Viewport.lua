local Viewport = {}

local function constrain(view)
	local dataSpan = view.dataMax - view.dataMin
	local span = view.maximum - view.minimum
	if dataSpan <= 0 then
		view.minimum = view.dataMin
		view.maximum = view.dataMax
		return view
	end

	span = math.clamp(span, dataSpan / 1000, dataSpan)
	if view.minimum < view.dataMin then
		view.minimum = view.dataMin
		view.maximum = view.minimum + span
	end
	if view.maximum > view.dataMax then
		view.maximum = view.dataMax
		view.minimum = view.maximum - span
	end
	return view
end

function Viewport.reset(dataMin, dataMax)
	if dataMin == dataMax then
		local padding = math.max(math.abs(dataMin) * 0.05, 1e-12)
		dataMin -= padding
		dataMax += padding
	end
	return {
		minimum = dataMin,
		maximum = dataMax,
		dataMin = dataMin,
		dataMax = dataMax,
	}
end

function Viewport.zoom(view, pivot, factor)
	local nextView = table.clone(view)
	nextView.minimum = pivot + (view.minimum - pivot) * factor
	nextView.maximum = pivot + (view.maximum - pivot) * factor
	return constrain(nextView)
end

function Viewport.pan(view, amount)
	local nextView = table.clone(view)
	nextView.minimum += amount
	nextView.maximum += amount
	return constrain(nextView)
end

return Viewport
