local Elements = require(script.Parent.Elements)
local Graph = require(script.Parent.Graph)
local Icons = require(script.Parent.Icons)
local ProfilerChart = require(script.Parent.ProfilerChart)
local Stats = require(script.Parent.Parent.Core.Stats)

local Dashboard = {}
Dashboard.__index = Dashboard

local function comparisonMap(comparison)
	local result = {}
	for _, item in ipairs(comparison and comparison.matching or {}) do
		result[item.name] = item
	end
	return result
end

local function nameSet(values)
	local result = {}
	for _, value in ipairs(values or {}) do
		result[value] = true
	end
	return result
end

local function deltaText(item)
	if not item then
		return nil
	end
	if item.difference == 0 then
		return "no median change"
	end
	if item.percent then
		local direction = item.percent <= 0 and "faster" or "slower"
		return string.format("%.1f%% %s", math.abs(item.percent), direction)
	end
	return string.format("%+.3g s", item.difference)
end

function Dashboard.new(widget, handlers)
	local self = setmetatable({}, Dashboard)
	self.widget = widget
	self.handlers = handlers or {}
	self.palette = nil
	self.report = nil
	self.baseline = nil
	self.comparison = nil
	self.visibleCases = {}
	self.selectedCase = nil
	self.readOnly = false

	self.root = Elements.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, widget)
	Elements.theme(self.root, "background")

	self.header = Elements.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 122),
	}, self.root)
	Elements.theme(self.header, "surface")

	self.brand = Elements.label(
		self.header,
		"BENCHMARKR",
		UDim2.fromOffset(132, 38),
		UDim2.fromOffset(12, 0),
		{ medium = true, textSize = 15 }
	)
	self.suiteLabel = Elements.label(
		self.header,
		"No suite selected",
		UDim2.new(1, -420, 0, 38),
		UDim2.fromOffset(148, 0),
		{ medium = true, textSize = 13 }
	)
	self.statusLabel = Elements.label(
		self.header,
		"Select a benchmark ModuleScript to begin.",
		UDim2.fromOffset(245, 38),
		UDim2.new(1, -257, 0, 0),
		{ color = "muted", align = Enum.TextXAlignment.Right, textSize = 11 }
	)

	Elements.label(
		self.header,
		"Runs",
		UDim2.fromOffset(34, 30),
		UDim2.fromOffset(12, 42),
		{ color = "muted", textSize = 11 }
	)
	self.runsInput =
		Elements.input(self.header, "500", UDim2.fromOffset(62, 28), UDim2.fromOffset(48, 43))
	Elements.label(
		self.header,
		"Warmup",
		UDim2.fromOffset(53, 30),
		UDim2.fromOffset(120, 42),
		{ color = "muted", textSize = 11 }
	)
	self.warmupInput =
		Elements.input(self.header, "25", UDim2.fromOffset(55, 28), UDim2.fromOffset(174, 43))

	self.runButton = Elements.button(
		self.header,
		Icons.label(Icons.PLAY, "Run"),
		UDim2.fromOffset(70, 28),
		UDim2.fromOffset(241, 43),
		{ background = "accent", color = "accentText", stroke = false }
	)
	self.stopButton = Elements.button(
		self.header,
		Icons.label(Icons.STOP, "Stop"),
		UDim2.fromOffset(70, 28),
		UDim2.fromOffset(241, 43),
		{ background = "danger", color = "accentText", stroke = false }
	)
	self.stopButton.Visible = false
	self.newButton = Elements.button(
		self.header,
		Icons.label(Icons.ADD, "New benchmark"),
		UDim2.fromOffset(118, 28),
		UDim2.fromOffset(321, 43)
	)
	self.historyButton = Elements.button(
		self.header,
		Icons.label(Icons.HISTORY, "History"),
		UDim2.fromOffset(80, 28),
		UDim2.fromOffset(449, 43)
	)
	self.pinButton = Elements.button(
		self.header,
		Icons.label(Icons.BASELINE, "Pin baseline"),
		UDim2.fromOffset(112, 28),
		UDim2.fromOffset(539, 43)
	)
	self.pinButton.Visible = false

	Elements.label(
		self.header,
		"Export",
		UDim2.fromOffset(44, 28),
		UDim2.fromOffset(12, 78),
		{ color = "muted", textSize = 11 }
	)
	self.jsonButton = Elements.button(
		self.header,
		Icons.label(Icons.EXPORT, "JSON"),
		UDim2.fromOffset(60, 26),
		UDim2.fromOffset(59, 79),
		{ textSize = 11 }
	)
	self.csvButton = Elements.button(
		self.header,
		Icons.label(Icons.EXPORT, "CSV"),
		UDim2.fromOffset(56, 26),
		UDim2.fromOffset(125, 79),
		{ textSize = 11 }
	)
	self.rbxmButton = Elements.button(
		self.header,
		Icons.label(Icons.EXPORT, "RBXM"),
		UDim2.fromOffset(66, 26),
		UDim2.fromOffset(187, 79),
		{ textSize = 11 }
	)
	for _, button in ipairs({ self.jsonButton, self.csvButton, self.rbxmButton }) do
		button.Visible = false
	end
	self.warningLabel = Elements.label(
		self.header,
		"Suites run in your real Studio environment. Review their code before running.",
		UDim2.new(1, -266, 0, 28),
		UDim2.fromOffset(258, 78),
		{ color = "warning", align = Enum.TextXAlignment.Right, textSize = 10 }
	)
	self.progressTrack = Elements.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -3),
		Size = UDim2.new(1, 0, 0, 3),
	}, self.header)
	Elements.theme(self.progressTrack, "elevated")
	self.progressBar = Elements.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(91, 124, 250),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}, self.progressTrack)

	self.body = Elements.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 130),
		Size = UDim2.new(1, -16, 1, -138),
	}, self.root)
	self.graphHost = Elements.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -294, 0.62, -5),
	}, self.body)
	self.profilerHost = Elements.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0.62, 5),
		Size = UDim2.new(1, -294, 0.38, -5),
	}, self.body)
	self.statsPanel = Elements.panel(self.body, UDim2.new(0, 284, 1, 0), UDim2.new(1, -284, 0, 0))
	self.statsTitle = Elements.label(
		self.statsPanel,
		"Cases",
		UDim2.new(1, -20, 0, 34),
		UDim2.fromOffset(10, 0),
		{ medium = true, textSize = 13 }
	)
	self.statsScroll = Elements.new("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		Position = UDim2.fromOffset(7, 35),
		ScrollBarImageTransparency = 0.35,
		ScrollBarThickness = 4,
		Size = UDim2.new(1, -14, 1, -42),
	}, self.statsPanel)
	Elements.new("UIListLayout", {
		Padding = UDim.new(0, 7),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, self.statsScroll)

	self.graph = Graph.new(self.graphHost)
	self.profiler = ProfilerChart.new(self.profilerHost)

	self.historyDrawer = Elements.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.new(1, -370, 0, 0),
		Size = UDim2.new(0, 370, 1, 0),
		Visible = false,
		ZIndex = 40,
	}, self.root)
	Elements.theme(self.historyDrawer, "surface")
	Elements.stroke(self.historyDrawer, "border")
	Elements.label(
		self.historyDrawer,
		"Recent runs",
		UDim2.new(1, -70, 0, 44),
		UDim2.fromOffset(12, 0),
		{ medium = true, textSize = 14, zIndex = 41 }
	)
	self.closeHistoryButton = Elements.button(
		self.historyDrawer,
		Icons.label(Icons.CLOSE, "Close"),
		UDim2.fromOffset(62, 26),
		UDim2.new(1, -72, 0, 9),
		{ zIndex = 41, textSize = 11 }
	)
	self.historyList = Elements.new("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		Position = UDim2.fromOffset(8, 49),
		ScrollBarThickness = 4,
		Size = UDim2.new(1, -16, 1, -57),
		ZIndex = 41,
	}, self.historyDrawer)
	Elements.new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, self.historyList)

	self.modalShade = Elements.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Visible = false,
		ZIndex = 50,
	}, self.root)
	self.modal = Elements.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.76, 0, 0.72, 0),
		Visible = false,
		ZIndex = 51,
	}, self.root)
	Elements.theme(self.modal, "surface")
	Elements.corner(self.modal, 7)
	Elements.stroke(self.modal, "border")
	self.modalTitle = Elements.label(
		self.modal,
		"Export",
		UDim2.new(1, -80, 0, 42),
		UDim2.fromOffset(12, 0),
		{ medium = true, textSize = 14, zIndex = 52 }
	)
	self.modalClose = Elements.button(
		self.modal,
		Icons.label(Icons.CLOSE, "Close"),
		UDim2.fromOffset(62, 26),
		UDim2.new(1, -74, 0, 8),
		{ zIndex = 52, textSize = 11 }
	)
	self.modalHelp = Elements.label(
		self.modal,
		"Click the text, then use Ctrl/Cmd+A and Ctrl/Cmd+C to copy it.",
		UDim2.new(1, -24, 0, 30),
		UDim2.fromOffset(12, 41),
		{ color = "muted", textSize = 11, zIndex = 52 }
	)
	self.modalText = Elements.new("TextBox", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.Code,
		MultiLine = true,
		Position = UDim2.fromOffset(12, 73),
		Size = UDim2.new(1, -24, 1, -85),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 12,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 52,
	}, self.modal)
	Elements.theme(self.modalText, "elevated", "text")
	Elements.corner(self.modalText, 4)
	Elements.stroke(self.modalText, "border")

	self.runButton.Activated:Connect(function()
		if self.handlers.onRun then
			self.handlers.onRun()
		end
	end)
	self.stopButton.Activated:Connect(function()
		if self.handlers.onStop then
			self.handlers.onStop()
		end
	end)
	self.newButton.Activated:Connect(function()
		if self.handlers.onNew then
			self.handlers.onNew()
		end
	end)
	self.historyButton.Activated:Connect(function()
		self.historyDrawer.Visible = not self.historyDrawer.Visible
	end)
	self.closeHistoryButton.Activated:Connect(function()
		self.historyDrawer.Visible = false
	end)
	self.pinButton.Activated:Connect(function()
		if self.handlers.onPinBaseline then
			self.handlers.onPinBaseline()
		end
	end)
	self.jsonButton.Activated:Connect(function()
		if self.handlers.onExport then
			self.handlers.onExport("json")
		end
	end)
	self.csvButton.Activated:Connect(function()
		if self.handlers.onExport then
			self.handlers.onExport("csv")
		end
	end)
	self.rbxmButton.Activated:Connect(function()
		if self.handlers.onExport then
			self.handlers.onExport("rbxm")
		end
	end)
	self.modalClose.Activated:Connect(function()
		self:closeModal()
	end)
	self.modalShade.Activated:Connect(function()
		self:closeModal()
	end)

	self.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:updateLayout()
	end)
	self:updateLayout()
	return self
end

function Dashboard:updateLayout()
	local statsWidth = self.root.AbsoluteSize.X < 920 and 248 or 284
	self.graphHost.Size = UDim2.new(1, -statsWidth - 10, 0.62, -5)
	self.profilerHost.Size = UDim2.new(1, -statsWidth - 10, 0.38, -5)
	self.statsPanel.Size = UDim2.new(0, statsWidth, 1, 0)
	self.statsPanel.Position = UDim2.new(1, -statsWidth, 0, 0)
	self.warningLabel.Visible = self.root.AbsoluteSize.X >= 820
end

function Dashboard:setPalette(palette)
	self.palette = palette
	Elements.applyTheme(self.root, palette)
	self.statusLabel.TextColor3 = palette[self.statusColor or "muted"]
	self.graph:setPalette(palette)
	self.profiler:setPalette(palette)
end

function Dashboard:setSelection(title, message, canRun)
	self.suiteLabel.Text = title or "No suite selected"
	self.statusLabel.Text = message or ""
	self.statusColor = "muted"
	if self.palette then
		self.statusLabel.TextColor3 = self.palette.muted
	end
	self.runButton.Active = canRun == true
	self.runButton.AutoButtonColor = canRun == true
	self.runButton.BackgroundTransparency = canRun and 0 or 0.55
end

function Dashboard:getOverrides()
	local function parse(input, label)
		if input.Text == "" then
			return nil
		end
		local value = tonumber(input.Text)
		if not value then
			return nil, label .. " must be a number or left blank."
		end
		return value
	end
	local runs, runsError = parse(self.runsInput, "Runs")
	if runsError then
		return nil, runsError
	end
	local warmups, warmupsError = parse(self.warmupInput, "Warmup")
	if warmupsError then
		return nil, warmupsError
	end
	return { runs = runs, warmupRuns = warmups }
end

function Dashboard:setRunning(running)
	self.runButton.Visible = not running
	self.stopButton.Visible = running
	self.runsInput.TextEditable = not running
	self.warmupInput.TextEditable = not running
	self.newButton.Active = not running
	self.historyButton.Active = not running
	self.pinButton.Active = not running
	if not running then
		self.progressBar.Size = UDim2.fromScale(0, 1)
	end
end

function Dashboard:setProgress(completed, total, phase, caseName)
	local ratio = total > 0 and completed / total or 0
	self.progressBar.Size = UDim2.fromScale(ratio, 1)
	self.statusLabel.Text = string.format("%s | %s | %d%%", phase, caseName, ratio * 100)
	self.statusColor = "muted"
	if self.palette then
		self.statusLabel.TextColor3 = self.palette.muted
	end
end

function Dashboard:setStatus(message, color)
	self.statusLabel.Text = message
	self.statusColor = color or "muted"
	if self.palette then
		self.statusLabel.TextColor3 = self.palette[self.statusColor]
	end
end

function Dashboard:renderStats()
	Elements.clear(self.statsScroll)
	if not self.report then
		Elements.label(
			self.statsScroll,
			"No benchmark results yet.",
			UDim2.new(1, -8, 0, 48),
			UDim2.fromOffset(0, 0),
			{ color = "muted", wrapped = true, align = Enum.TextXAlignment.Center }
		)
		if self.palette then
			Elements.applyTheme(self.statsScroll, self.palette)
		end
		return
	end

	local comparisons = comparisonMap(self.comparison)
	local added = nameSet(self.comparison and self.comparison.added)
	local fastestMedian = math.huge
	for _, case in ipairs(self.report.cases) do
		fastestMedian = math.min(fastestMedian, case.stats.p50)
	end
	for index, case in ipairs(self.report.cases) do
		local card = Elements.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1, -6, 0, 128),
		}, self.statsScroll)
		Elements.theme(card, self.selectedCase == case.name and "hover" or "elevated")
		Elements.corner(card, 5)

		local toggle = Elements.button(
			card,
			self.visibleCases[case.name] == false and "" or Icons.CHECK,
			UDim2.fromOffset(20, 20),
			UDim2.fromOffset(7, 7),
			{ textSize = 11, radius = 3 }
		)
		toggle.BackgroundColor3 = self.graph.colorByName[case.name]
		toggle.TextColor3 = Color3.new(1, 1, 1)
		toggle:SetAttribute("ThemeBackground", nil)
		toggle:SetAttribute("ThemeText", nil)
		local selectButton = Elements.new("TextButton", {
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(33, 5),
			Size = UDim2.new(1, -94, 0, 25),
			Text = case.name,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		Elements.theme(selectButton, nil, "text")
		Elements.label(
			card,
			"n=" .. tostring(case.stats.count),
			UDim2.fromOffset(52, 22),
			UDim2.new(1, -59, 0, 6),
			{ color = "muted", textSize = 9, align = Enum.TextXAlignment.Right }
		)
		selectButton.Activated:Connect(function()
			self.selectedCase = case.name
			self.profiler:setCase(case)
			self:renderStats()
		end)
		toggle.Activated:Connect(function()
			self.visibleCases[case.name] = self.visibleCases[case.name] == false
			self.graph:setVisible(self.visibleCases)
			self:renderStats()
		end)

		Elements.label(
			card,
			"P50",
			UDim2.fromOffset(34, 18),
			UDim2.fromOffset(8, 35),
			{ color = "muted", textSize = 9 }
		)
		local unit = Stats.chooseUnit(case.stats.p50)
		Elements.label(
			card,
			Stats.formatDuration(case.stats.p50, unit),
			UDim2.new(1, -138, 0, 22),
			UDim2.fromOffset(43, 32),
			{ medium = true, textSize = 15 }
		)
		local relativeText = "fastest"
		if fastestMedian > 0 and case.stats.p50 > fastestMedian then
			relativeText =
				string.format("+%.1f%% vs fastest", (case.stats.p50 / fastestMedian - 1) * 100)
		elseif fastestMedian == 0 and case.stats.p50 > 0 then
			relativeText = "+" .. Stats.formatDuration(case.stats.p50)
		end
		Elements.label(card, relativeText, UDim2.fromOffset(92, 22), UDim2.new(1, -100, 0, 32), {
			color = case.stats.p50 == fastestMedian and "success" or "muted",
			textSize = 8,
			align = Enum.TextXAlignment.Right,
		})

		local labels = {
			{ "P10", case.stats.p10 },
			{ "P90", case.stats.p90 },
			{ "Mean", case.stats.mean },
			{ "Min", case.stats.min },
			{ "Max", case.stats.max },
			{ "Total", case.stats.total },
		}
		for statIndex, pair in ipairs(labels) do
			local column = (statIndex - 1) % 3
			local row = math.floor((statIndex - 1) / 3)
			local y = 61 + row * 26
			Elements.label(
				card,
				pair[1],
				UDim2.new(1 / 3, -10, 0, 13),
				UDim2.new(column / 3, 8, 0, y),
				{ color = "muted", textSize = 8 }
			)
			Elements.label(
				card,
				Stats.formatDuration(pair[2], unit),
				UDim2.new(1 / 3, -10, 0, 14),
				UDim2.new(column / 3, 8, 0, y + 11),
				{ textSize = 9 }
			)
		end

		local delta = comparisons[case.name]
		local footer = deltaText(delta)
		if added[case.name] then
			footer = "new since baseline"
		end
		if case.nearTimerFloor then
			footer = (footer and footer .. " | " or "") .. "near timer floor"
		end
		if footer then
			Elements.label(card, footer, UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 111), {
				color = delta and delta.difference <= 0 and "success" or "warning",
				textSize = 9,
			})
		end
	end

	for _, name in ipairs(self.comparison and self.comparison.removed or {}) do
		local removed = Elements.label(
			self.statsScroll,
			name .. " | removed since baseline",
			UDim2.new(1, -6, 0, 28),
			UDim2.fromOffset(0, 0),
			{ color = "danger", textSize = 10 }
		)
		removed.LayoutOrder = 1000
	end
	if self.palette then
		Elements.applyTheme(self.statsScroll, self.palette)
	end
end

function Dashboard:setReport(report, baseline, comparison, readOnly)
	self.report = report
	self.baseline = baseline
	self.comparison = comparison
	self.readOnly = readOnly == true
	self.visibleCases = {}
	for _, case in ipairs(report.cases) do
		self.visibleCases[case.name] = true
	end
	self.selectedCase = report.cases[1] and report.cases[1].name or nil
	self.graph:setReports(report, baseline, self.visibleCases)
	self.profiler:setCase(report.cases[1])
	self:renderStats()

	self.suiteLabel.Text = report.suite.name or report.suite.id or "Benchmark report"
	self.runsInput.PlaceholderText = tostring(report.config.runs or 500)
	self.warmupInput.PlaceholderText = tostring(report.config.warmupRuns or 25)
	for _, button in ipairs({ self.jsonButton, self.csvButton, self.rbxmButton }) do
		button.Visible = true
	end
	self.pinButton.Visible = true
	self.pinButton.Text =
		Icons.label(Icons.BASELINE, baseline and "Update baseline" or "Pin baseline")
end

function Dashboard:setHistory(history)
	Elements.clear(self.historyList)
	if #history.recent == 0 then
		Elements.label(
			self.historyList,
			"Successful runs will appear here.",
			UDim2.new(1, -8, 0, 52),
			UDim2.fromOffset(0, 0),
			{ color = "muted", wrapped = true, align = Enum.TextXAlignment.Center, zIndex = 42 }
		)
	else
		for index, entry in ipairs(history.recent) do
			local report = entry.report
			local button = Elements.button(
				self.historyList,
				string.format(
					"%s\n%s | %d runs",
					report.suite.name or report.suite.id,
					report.createdAt,
					report.config.runs or 0
				),
				UDim2.new(1, -6, 0, 55),
				UDim2.fromOffset(0, 0),
				{ zIndex = 42, textSize = 10 }
			)
			button.LayoutOrder = index
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.TextWrapped = true
			button.Activated:Connect(function()
				self.historyDrawer.Visible = false
				if self.handlers.onHistorySelect then
					self.handlers.onHistorySelect(report)
				end
			end)
		end
	end
	if self.palette then
		Elements.applyTheme(self.historyList, self.palette)
	end
end

function Dashboard:showText(title, text, helpText)
	self.modalTitle.Text = title
	self.modalText.Text = text
	self.modalText.TextEditable = true
	self.modalHelp.Text = helpText
		or "Click the text, then use Ctrl/Cmd+A and Ctrl/Cmd+C to copy it."
	self.modalShade.Visible = true
	self.modal.Visible = true
	self.modalText:CaptureFocus()
	self.modalText.CursorPosition = 1
end

function Dashboard:showError(title, message)
	self:showText(
		title or "Benchmark error",
		message,
		"Review the error below, then close this dialog."
	)
	self.modalText.TextEditable = false
end

function Dashboard:closeModal()
	self.modalText:ReleaseFocus()
	self.modal.Visible = false
	self.modalShade.Visible = false
end

return Dashboard
