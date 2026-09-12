local Elements = require(script.Parent.Elements)
local ErrorBars = require(script.Parent.Parent.Core.ErrorBars)
local Icons = require(script.Parent.Icons)
local Stats = require(script.Parent.Parent.Core.Stats)
local Theme = require(script.Parent.Theme)
local Viewport = require(script.Parent.Parent.Core.Viewport)

local Graph = {}
Graph.__index = Graph

local function line(parent, from, to, color, thickness, transparency)
	local offset = to - from
	local distance = offset.Magnitude
	if distance <= 0 then
		return nil
	end
	local frame = Elements.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2),
		Rotation = math.deg(math.atan2(offset.Y, offset.X)),
		Size = UDim2.fromOffset(distance, thickness or 2),
		ZIndex = 2,
	}, parent)
	return frame
end

local function visibleCases(self, report)
	local cases = {}
	if report then
		for _, case in ipairs(report.cases or {}) do
			if self.visible[case.name] ~= false then
				table.insert(cases, case)
			end
		end
	end
	return cases
end

local function histogramBounds(self)
	local minimum = math.huge
	local maximum = -math.huge
	for _, report in ipairs({ self.report, self.baseline }) do
		for _, case in ipairs(visibleCases(self, report)) do
			if case.histogram then
				minimum = math.min(minimum, case.histogram.sampleMinimum or case.histogram.minimum)
				maximum = math.max(maximum, case.histogram.sampleMaximum or case.histogram.maximum)
			end
		end
	end
	if minimum == math.huge then
		return 0, 1
	end
	return minimum, maximum
end

local function traceBounds(self)
	local maximum = 1
	for _, report in ipairs({ self.report, self.baseline }) do
		for _, case in ipairs(visibleCases(self, report)) do
			local last = case.trace and case.trace[#case.trace]
			if last then
				maximum = math.max(maximum, last.index)
			end
		end
	end
	return 1, maximum
end

local function errorBarBounds(self)
	local categories = ErrorBars.categories(self.report, self.baseline, self.visible)
	return 0.5, math.max(1.5, #categories + 0.5)
end

local function reportCasesByName(report)
	local cases = {}
	if report then
		for _, case in ipairs(report.cases or {}) do
			cases[case.name] = case
		end
	end
	return cases
end

local function modeTitle(mode)
	if mode == "histogram" then
		return "Distribution"
	elseif mode == "line" then
		return "Per-run line"
	end
	return "P10-P90 error bars"
end

function Graph.new(parent)
	local self = setmetatable({}, Graph)
	self.palette = nil
	self.report = nil
	self.baseline = nil
	self.visible = {}
	self.colorByName = {}
	self.mode = "histogram"
	self.viewport = Viewport.reset(0, 1)
	self.dragging = false
	self.lastMouseX = 0
	self.renderScheduled = false
	self._errorCategories = {}

	self.root = Elements.panel(parent, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0))
	self.root.Name = "Graph"

	self.title = Elements.label(
		self.root,
		"Distribution",
		UDim2.new(1, -376, 0, 34),
		UDim2.fromOffset(12, 0),
		{ medium = true, textSize = 13 }
	)
	self.histogramButton = Elements.button(
		self.root,
		Icons.label(Icons.DISTRIBUTION, "Distribution"),
		UDim2.fromOffset(98, 25),
		UDim2.new(1, -361, 0, 5),
		{ textSize = 10 }
	)
	self.lineButton = Elements.button(
		self.root,
		Icons.label(Icons.LINE, "Line"),
		UDim2.fromOffset(61, 25),
		UDim2.new(1, -257, 0, 5),
		{ textSize = 10 }
	)
	self.errorBarsButton = Elements.button(
		self.root,
		Icons.label(Icons.ERROR_BARS, "Error bars"),
		UDim2.fromOffset(91, 25),
		UDim2.new(1, -190, 0, 5),
		{ textSize = 10 }
	)
	self.resetButton = Elements.button(
		self.root,
		Icons.label(Icons.RESET, "Reset view"),
		UDim2.fromOffset(87, 25),
		UDim2.new(1, -93, 0, 5),
		{ textSize = 10 }
	)

	self.plot = Elements.new("Frame", {
		Active = true,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(50, 40),
		Size = UDim2.new(1, -62, 1, -70),
	}, self.root)
	Elements.theme(self.plot, "graph")
	Elements.corner(self.plot, 4)

	self.marks = Elements.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, self.plot)
	self.axes = Elements.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, self.root)

	self.tooltip = Elements.new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		LineHeight = 1.15,
		Position = UDim2.fromOffset(60, 48),
		Size = UDim2.fromOffset(230, 0),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		ZIndex = 30,
	}, self.root)
	Elements.theme(self.tooltip, "elevated", "text")
	Elements.corner(self.tooltip, 5)
	Elements.stroke(self.tooltip, "border")
	Elements.new("UIPadding", {
		PaddingBottom = UDim.new(0, 7),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 7),
	}, self.tooltip)

	self.histogramButton.Activated:Connect(function()
		self:setMode("histogram")
	end)
	self.lineButton.Activated:Connect(function()
		self:setMode("line")
	end)
	self.errorBarsButton.Activated:Connect(function()
		self:setMode("errorbars")
	end)
	self.resetButton.Activated:Connect(function()
		self:resetView()
	end)

	self.plot.MouseEnter:Connect(function()
		if self.report then
			self.tooltip.Visible = true
		end
	end)
	self.plot.MouseLeave:Connect(function()
		self.tooltip.Visible = false
		self.dragging = false
	end)
	self.plot.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.dragging = true
			self.lastMouseX = input.Position.X
		end
	end)
	self.plot.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.dragging = false
		end
	end)
	self.plot.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local localX = input.Position.X - self.plot.AbsolutePosition.X
		self.lastMouseX = input.Position.X
		if self.dragging and self.plot.AbsoluteSize.X > 0 then
			local delta = input.Delta.X
			local span = self.viewport.maximum - self.viewport.minimum
			self.viewport = Viewport.pan(self.viewport, -delta / self.plot.AbsoluteSize.X * span)
			self:requestRender()
		end
		self:updateTooltip(localX, input.Position.Y - self.plot.AbsolutePosition.Y)
	end)
	self.plot.MouseWheelForward:Connect(function()
		self:zoomAtMouse(0.8)
	end)
	self.plot.MouseWheelBackward:Connect(function()
		self:zoomAtMouse(1.25)
	end)
	self.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:requestRender()
	end)

	return self
end

function Graph:requestRender()
	if self.renderScheduled then
		return
	end
	self.renderScheduled = true
	task.defer(function()
		self.renderScheduled = false
		self:render()
	end)
end

function Graph:updateModeButtons()
	for _, item in ipairs({
		{ mode = "histogram", button = self.histogramButton },
		{ mode = "line", button = self.lineButton },
		{ mode = "errorbars", button = self.errorBarsButton },
	}) do
		local active = self.mode == item.mode
		item.button:SetAttribute("ThemeBackground", active and "accent" or "elevated")
		item.button:SetAttribute("ThemeText", active and "accentText" or "text")
		if self.palette then
			Elements.applyTheme(item.button, self.palette)
		end
	end
end

function Graph:setPalette(palette)
	self.palette = palette
	Elements.applyTheme(self.root, palette)
	self:updateModeButtons()
	self:render()
end

function Graph:setReports(report, baseline, visible)
	self.report = report
	self.baseline = baseline
	self.visible = visible or {}
	self.colorByName = {}
	local colorIndex = 1
	for _, source in ipairs({ report, baseline }) do
		if source then
			for _, case in ipairs(source.cases or {}) do
				if not self.colorByName[case.name] then
					self.colorByName[case.name] = Theme.series[(colorIndex - 1) % #Theme.series + 1]
					colorIndex += 1
				end
			end
		end
	end
	self.title.Text = modeTitle(self.mode) .. (baseline and " | baseline overlay" or "")
	self:resetView()
end

function Graph:setVisible(visible)
	self.visible = visible
	self:resetView()
end

function Graph:setMode(mode)
	if mode ~= "histogram" and mode ~= "line" and mode ~= "errorbars" then
		return
	end
	self.mode = mode
	self.title.Text = modeTitle(mode) .. (self.baseline and " | baseline overlay" or "")
	self:updateModeButtons()
	self:resetView()
end

function Graph:resetView()
	local minimum
	local maximum
	if self.mode == "histogram" then
		minimum, maximum = histogramBounds(self)
	elseif self.mode == "line" then
		minimum, maximum = traceBounds(self)
	else
		minimum, maximum = errorBarBounds(self)
	end
	self.viewport = Viewport.reset(minimum, maximum)
	self:render()
end

function Graph:zoomAtMouse(factor)
	if not self.report or self.plot.AbsoluteSize.X <= 0 then
		return
	end
	local ratio = math.clamp(
		(self.lastMouseX - self.plot.AbsolutePosition.X) / self.plot.AbsoluteSize.X,
		0,
		1
	)
	local pivot = self.viewport.minimum + ratio * (self.viewport.maximum - self.viewport.minimum)
	self.viewport = Viewport.zoom(self.viewport, pivot, factor)
	self:render()
end

function Graph:drawAxes(yMinimum, yMaximum, yFormatter)
	Elements.clear(self.axes)
	local palette = self.palette
	if not palette then
		return
	end
	for tick = 0, 4 do
		local ratio = tick / 4
		local y = 40 + (1 - ratio) * math.max(0, self.plot.AbsoluteSize.Y)
		local grid = Elements.new("Frame", {
			BackgroundColor3 = palette.grid,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(50, y),
			Size = UDim2.new(1, -62, 0, 1),
		}, self.axes)
		grid.ZIndex = 1
		local yValue = yMinimum + (yMaximum - yMinimum) * ratio
		local yLabel = Elements.label(
			self.axes,
			yFormatter(yValue),
			UDim2.fromOffset(43, 16),
			UDim2.fromOffset(2, y - 8),
			{ textSize = 9, align = Enum.TextXAlignment.Right, color = "muted" }
		)
		yLabel.ZIndex = 2
	end

	local span = self.viewport.maximum - self.viewport.minimum
	local xUnit
	if self.mode == "histogram" then
		xUnit = Stats.chooseUnit(
			math.max(math.abs(self.viewport.minimum), math.abs(self.viewport.maximum))
		)
	end
	if self.mode == "errorbars" then
		local first = math.max(1, math.ceil(self.viewport.minimum))
		local last = math.min(#self._errorCategories, math.floor(self.viewport.maximum))
		local visibleCount = math.max(0, last - first + 1)
		local labelCapacity = math.max(1, math.floor(self.plot.AbsoluteSize.X / 85))
		local labelStep = math.max(1, math.ceil(visibleCount / labelCapacity))
		for index = first, last, labelStep do
			local ratio = (index - self.viewport.minimum) / span
			Elements.label(
				self.axes,
				self._errorCategories[index],
				UDim2.fromOffset(82, 18),
				UDim2.fromOffset(
					9 + ratio * self.plot.AbsoluteSize.X,
					self.root.AbsoluteSize.Y - 25
				),
				{ textSize = 9, align = Enum.TextXAlignment.Center, color = "muted" }
			)
		end
	else
		for tick = 0, 4 do
			local ratio = tick / 4
			local value = self.viewport.minimum + span * ratio
			local text = if self.mode == "histogram"
				then Stats.formatDuration(value, xUnit)
				else tostring(math.floor(value + 0.5))
			Elements.label(
				self.axes,
				text,
				UDim2.fromOffset(90, 18),
				UDim2.fromOffset(
					5 + ratio * self.plot.AbsoluteSize.X,
					self.root.AbsoluteSize.Y - 25
				),
				{ textSize = 9, align = Enum.TextXAlignment.Center, color = "muted" }
			)
		end
	end
	Elements.applyTheme(self.axes, palette)
end

function Graph:drawHistogramSeries(case, baseline)
	local histogram = case.histogram
	if not histogram then
		return
	end
	local width = self.plot.AbsoluteSize.X
	local height = self.plot.AbsoluteSize.Y
	local span = self.viewport.maximum - self.viewport.minimum
	local color = self.colorByName[case.name] or Theme.series[1]
	for index, density in ipairs(histogram.density) do
		local leftValue = histogram.minimum + (index - 1) * histogram.binWidth
		local rightValue = leftValue + histogram.binWidth
		if rightValue >= self.viewport.minimum and leftValue <= self.viewport.maximum then
			local left = (leftValue - self.viewport.minimum) / span * width
			local right = (rightValue - self.viewport.minimum) / span * width
			local barHeight = self._yMaximum > 0 and density / self._yMaximum * height or 0
			if baseline then
				if index % 2 == 1 then
					Elements.new("Frame", {
						BackgroundColor3 = color,
						BorderSizePixel = 0,
						Position = UDim2.fromOffset(left, math.max(0, height - barHeight)),
						Size = UDim2.fromOffset(math.max(1, right - left), 2),
						ZIndex = 4,
					}, self.marks)
				end
			else
				Elements.new("Frame", {
					BackgroundColor3 = color,
					BackgroundTransparency = 0.52,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(left, math.max(0, height - barHeight)),
					Size = UDim2.fromOffset(math.max(1, right - left - 1), barHeight),
					ZIndex = 2,
				}, self.marks)
			end
		end
	end
end

function Graph:drawTraceSeries(case, baseline, yMinimum, yMaximum)
	if not case.trace or #case.trace == 0 then
		return
	end
	local width = self.plot.AbsoluteSize.X
	local height = self.plot.AbsoluteSize.Y
	local xSpan = self.viewport.maximum - self.viewport.minimum
	local ySpan = yMaximum - yMinimum
	local color = self.colorByName[case.name] or Theme.series[1]
	local previous
	for pointIndex, point in ipairs(case.trace) do
		if point.index >= self.viewport.minimum and point.index <= self.viewport.maximum then
			local current = Vector2.new(
				(point.index - self.viewport.minimum) / xSpan * width,
				height - (point.value - yMinimum) / ySpan * height
			)
			if previous and (not baseline or pointIndex % 2 == 0) then
				local segment = line(
					self.marks,
					previous,
					current,
					color,
					baseline and 1 or 2,
					baseline and 0.2 or 0
				)
				if baseline and segment then
					segment.ZIndex = 4
				end
			end
			if not baseline then
				Elements.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = color,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(current.X, current.Y),
					Size = UDim2.fromOffset(3, 3),
					ZIndex = 3,
				}, self.marks)
			end
			previous = current
		elseif point.index > self.viewport.maximum then
			break
		end
	end
end

function Graph:drawErrorBar(case, index, baseline, paired, yMinimum, yMaximum)
	local point = ErrorBars.point(case)
	if not point then
		return
	end
	local offset = 0
	if paired then
		offset = baseline and 0.1 or -0.1
	end
	local value = index + offset
	if value < self.viewport.minimum or value > self.viewport.maximum then
		return
	end

	local width = self.plot.AbsoluteSize.X
	local height = self.plot.AbsoluteSize.Y
	local xSpan = self.viewport.maximum - self.viewport.minimum
	local ySpan = yMaximum - yMinimum
	local color = self.colorByName[case.name] or Theme.series[1]
	local x = (value - self.viewport.minimum) / xSpan * width
	local lowerY = height - (point.lower - yMinimum) / ySpan * height
	local centerY = height - (point.center - yMinimum) / ySpan * height
	local upperY = height - (point.upper - yMinimum) / ySpan * height
	local transparency = baseline and 0.18 or 0
	local thickness = baseline and 1 or 2
	local capWidth = baseline and 12 or 14

	local segments = {
		line(
			self.marks,
			Vector2.new(x, upperY),
			Vector2.new(x, lowerY),
			color,
			thickness,
			transparency
		),
		line(
			self.marks,
			Vector2.new(x - capWidth / 2, upperY),
			Vector2.new(x + capWidth / 2, upperY),
			color,
			thickness,
			transparency
		),
		line(
			self.marks,
			Vector2.new(x - capWidth / 2, lowerY),
			Vector2.new(x + capWidth / 2, lowerY),
			color,
			thickness,
			transparency
		),
	}
	for _, segment in pairs(segments) do
		if baseline and segment then
			segment.ZIndex = 4
		end
	end

	local marker = Elements.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = baseline and 1 or 0,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, centerY),
		Size = UDim2.fromOffset(baseline and 9 or 7, baseline and 9 or 7),
		ZIndex = baseline and 5 or 4,
	}, self.marks)
	Elements.corner(marker, 10)
	if baseline then
		Elements.new("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = color,
			Thickness = 2,
		}, marker)
	end
end

function Graph:render()
	if not self.palette or self.plot.AbsoluteSize.X <= 0 or self.plot.AbsoluteSize.Y <= 0 then
		return
	end
	Elements.clear(self.marks)
	if not self.report then
		self:drawAxes(0, 1, function(value)
			return string.format("%.0f%%", value * 100)
		end)
		return
	end

	if self.mode == "histogram" then
		local yMaximum = 0
		for _, report in ipairs({ self.report, self.baseline }) do
			for _, case in ipairs(visibleCases(self, report)) do
				yMaximum = math.max(yMaximum, case.histogram and case.histogram.maxDensity or 0)
			end
		end
		self._yMaximum = math.max(yMaximum, 1e-9)
		self:drawAxes(0, self._yMaximum, function(value)
			return string.format("%.0f%%", value * 100)
		end)
		for _, case in ipairs(visibleCases(self, self.baseline)) do
			self:drawHistogramSeries(case, true)
		end
		for _, case in ipairs(visibleCases(self, self.report)) do
			self:drawHistogramSeries(case, false)
		end
	elseif self.mode == "line" then
		local yMinimum = math.huge
		local yMaximum = -math.huge
		for _, report in ipairs({ self.report, self.baseline }) do
			for _, case in ipairs(visibleCases(self, report)) do
				for _, point in ipairs(case.trace or {}) do
					if
						point.index >= self.viewport.minimum
						and point.index <= self.viewport.maximum
					then
						yMinimum = math.min(yMinimum, point.value)
						yMaximum = math.max(yMaximum, point.value)
					end
				end
			end
		end
		if yMinimum == math.huge then
			yMinimum, yMaximum = 0, 1
		elseif yMinimum == yMaximum then
			local padding = math.max(yMinimum * 0.05, 1e-12)
			yMinimum -= padding
			yMaximum += padding
		end
		local yUnit = Stats.chooseUnit(math.max(math.abs(yMinimum), math.abs(yMaximum)))
		self._traceUnit = yUnit
		self:drawAxes(yMinimum, yMaximum, function(value)
			return Stats.formatDuration(value, yUnit)
		end)
		for _, case in ipairs(visibleCases(self, self.baseline)) do
			self:drawTraceSeries(case, true, yMinimum, yMaximum)
		end
		for _, case in ipairs(visibleCases(self, self.report)) do
			self:drawTraceSeries(case, false, yMinimum, yMaximum)
		end
	else
		self._errorCategories = ErrorBars.categories(self.report, self.baseline, self.visible)
		local currentCases = reportCasesByName(self.report)
		local baselineCases = reportCasesByName(self.baseline)
		local points = {}
		for index, name in ipairs(self._errorCategories) do
			if index >= self.viewport.minimum and index <= self.viewport.maximum then
				local currentPoint = ErrorBars.point(currentCases[name])
				local baselinePoint = ErrorBars.point(baselineCases[name])
				if currentPoint then
					table.insert(points, currentPoint)
				end
				if baselinePoint then
					table.insert(points, baselinePoint)
				end
			end
		end
		local yMinimum, yMaximum = ErrorBars.bounds(points)
		local yUnit = Stats.chooseUnit(math.max(math.abs(yMinimum), math.abs(yMaximum)))
		self._errorUnit = yUnit
		self:drawAxes(yMinimum, yMaximum, function(value)
			return Stats.formatDuration(value, yUnit)
		end)
		for index, name in ipairs(self._errorCategories) do
			local currentCase = currentCases[name]
			local baselineCase = baselineCases[name]
			local paired = currentCase ~= nil and baselineCase ~= nil
			if baselineCase then
				self:drawErrorBar(baselineCase, index, true, paired, yMinimum, yMaximum)
			end
			if currentCase then
				self:drawErrorBar(currentCase, index, false, paired, yMinimum, yMaximum)
			end
		end
	end
end

function Graph:updateTooltip(localX, localY)
	if not self.report or self.plot.AbsoluteSize.X <= 0 then
		return
	end
	local ratio = math.clamp(localX / self.plot.AbsoluteSize.X, 0, 1)
	local value = self.viewport.minimum + ratio * (self.viewport.maximum - self.viewport.minimum)
	local lines = {}
	if self.mode == "histogram" then
		local unit = Stats.chooseUnit(
			math.max(math.abs(self.viewport.minimum), math.abs(self.viewport.maximum))
		)
		table.insert(lines, Stats.formatDuration(value, unit))
		for _, source in ipairs({
			{ report = self.report, suffix = "" },
			{ report = self.baseline, suffix = " (baseline)" },
		}) do
			for _, case in ipairs(visibleCases(self, source.report)) do
				local histogram = case.histogram
				if value >= histogram.minimum and value <= histogram.maximum then
					local index = math.clamp(
						math.floor((value - histogram.minimum) / histogram.binWidth) + 1,
						1,
						#histogram.counts
					)
					table.insert(
						lines,
						string.format(
							"%s%s: %d (%.1f%%)",
							case.name,
							source.suffix,
							histogram.counts[index],
							histogram.density[index] * 100
						)
					)
				end
			end
		end
	elseif self.mode == "line" then
		local index = math.max(1, math.floor(value + 0.5))
		table.insert(lines, "Run " .. index)
		for _, source in ipairs({
			{ report = self.report, suffix = "" },
			{ report = self.baseline, suffix = " (baseline)" },
		}) do
			for _, case in ipairs(visibleCases(self, source.report)) do
				local nearest
				local distance = math.huge
				for _, point in ipairs(case.trace or {}) do
					local nextDistance = math.abs(point.index - index)
					if nextDistance < distance then
						nearest = point
						distance = nextDistance
					end
				end
				if nearest then
					table.insert(
						lines,
						string.format(
							"%s%s: %s",
							case.name,
							source.suffix,
							Stats.formatDuration(nearest.value, self._traceUnit)
						)
					)
				end
			end
		end
	else
		local categoryCount = #self._errorCategories
		if categoryCount == 0 then
			table.insert(lines, "No visible cases")
		else
			local index = math.clamp(math.floor(value + 0.5), 1, categoryCount)
			local name = self._errorCategories[index]
			table.insert(lines, name)
			local currentCases = reportCasesByName(self.report)
			local baselineCases = reportCasesByName(self.baseline)
			for _, source in ipairs({
				{ case = currentCases[name], label = "Current" },
				{ case = baselineCases[name], label = "Baseline" },
			}) do
				local point = ErrorBars.point(source.case)
				if point then
					table.insert(
						lines,
						string.format(
							"%s: P10 %s | P50 %s | P90 %s",
							source.label,
							Stats.formatDuration(point.lower, self._errorUnit),
							Stats.formatDuration(point.center, self._errorUnit),
							Stats.formatDuration(point.upper, self._errorUnit)
						)
					)
				end
			end
		end
	end
	self.tooltip.Text = table.concat(lines, "\n")
	local x = math.clamp(localX + 58, 4, math.max(4, self.root.AbsoluteSize.X - 246))
	local y = math.clamp(localY + 48, 4, math.max(4, self.root.AbsoluteSize.Y - 120))
	self.tooltip.Position = UDim2.fromOffset(x, y)
end

return Graph
