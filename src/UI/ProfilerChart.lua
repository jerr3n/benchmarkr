local Elements = require(script.Parent.Elements)
local Theme = require(script.Parent.Theme)
local Stats = require(script.Parent.Parent.Core.Stats)

local ProfilerChart = {}
ProfilerChart.__index = ProfilerChart

local function findNode(node, path)
	if node.path == path then
		return node
	end
	for _, child in ipairs(node.children or {}) do
		local found = findNode(child, path)
		if found then
			return found
		end
	end
	return nil
end

local function findTrail(node, path, trail)
	table.insert(trail, node)
	if node.path == path then
		return true
	end
	for _, child in ipairs(node.children or {}) do
		if findTrail(child, path, trail) then
			return true
		end
	end
	table.remove(trail)
	return false
end

local function layoutTotal(node)
	local childrenTotal = 0
	for _, child in ipairs(node.children or {}) do
		childrenTotal += child.stats.p50
	end
	return math.max(node.stats.p50, childrenTotal, 1e-15)
end

function ProfilerChart.new(parent)
	local self = setmetatable({}, ProfilerChart)
	self.case = nil
	self.focusPath = ""
	self.palette = nil

	self.root = Elements.panel(parent, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0))
	self.title = Elements.label(
		self.root,
		"Profiler breakdown",
		UDim2.new(1, -24, 0, 30),
		UDim2.fromOffset(12, 0),
		{ medium = true, textSize = 13 }
	)
	self.breadcrumbs = Elements.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 31),
		Size = UDim2.new(1, -16, 0, 25),
	}, self.root)
	Elements.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, self.breadcrumbs)

	self.canvas = Elements.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(8, 60),
		Size = UDim2.new(1, -16, 1, -68),
	}, self.root)
	Elements.theme(self.canvas, "graph")
	Elements.corner(self.canvas, 4)

	self.empty = Elements.label(
		self.canvas,
		"Run a suite and select a case to inspect labeled sections.",
		UDim2.new(1, -24, 1, -16),
		UDim2.fromOffset(12, 8),
		{ color = "muted", wrapped = true, align = Enum.TextXAlignment.Center }
	)
	self.tooltip = Elements.new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		Position = UDim2.fromOffset(12, 12),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 11,
		Visible = false,
		ZIndex = 30,
	}, self.canvas)
	Elements.theme(self.tooltip, "elevated", "text")
	Elements.corner(self.tooltip, 4)
	Elements.stroke(self.tooltip, "border")
	Elements.new("UIPadding", {
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 7),
		PaddingRight = UDim.new(0, 7),
		PaddingTop = UDim.new(0, 6),
	}, self.tooltip)

	self.canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(function()
			self:render()
		end)
	end)
	return self
end

function ProfilerChart:setPalette(palette)
	self.palette = palette
	Elements.applyTheme(self.root, palette)
	self:render()
end

function ProfilerChart:setCase(case)
	self.case = case
	self.focusPath = ""
	self:render()
end

function ProfilerChart:setFocus(path)
	if self.case and findNode(self.case.profile, path) then
		self.focusPath = path
		self:render()
	end
end

function ProfilerChart:renderBreadcrumbs()
	Elements.clear(self.breadcrumbs)
	if not self.case then
		return
	end
	local trail = {}
	findTrail(self.case.profile, self.focusPath, trail)
	for index, node in ipairs(trail) do
		local labelText = index == 1 and self.case.name or node.name
		local button = Elements.button(
			self.breadcrumbs,
			labelText,
			UDim2.fromOffset(math.clamp(#labelText * 7 + 18, 54, 160), 22),
			UDim2.fromOffset(0, 0),
			{ textSize = 10, stroke = false }
		)
		button.LayoutOrder = index * 2
		button.Activated:Connect(function()
			self:setFocus(node.path)
		end)
		if index < #trail then
			local separator = Elements.label(
				self.breadcrumbs,
				"/",
				UDim2.fromOffset(8, 22),
				UDim2.fromOffset(0, 0),
				{ color = "muted", align = Enum.TextXAlignment.Center }
			)
			separator.LayoutOrder = index * 2 + 1
		end
	end
	if self.palette then
		Elements.applyTheme(self.breadcrumbs, self.palette)
	end
end

function ProfilerChart:drawNode(node, x, width, depth, colorIndex)
	if width < 1 or depth > 8 then
		return
	end
	local rowHeight = 27
	local y = 5 + depth * rowHeight
	if y + rowHeight > self.canvas.AbsoluteSize.Y then
		return
	end
	local color = node.name == "[UNTRACKED]" and self.palette.muted
		or Theme.series[(colorIndex - 1) % #Theme.series + 1]
	local button = Elements.new("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = color,
		BackgroundTransparency = node.name == "[UNTRACKED]" and 0.45 or 0.16,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(x + 1, y),
		Size = UDim2.fromOffset(math.max(1, width - 2), rowHeight - 3),
		Text = width >= 48 and (node.name .. "  " .. Stats.formatDuration(node.stats.p50)) or "",
		TextColor3 = self.palette.text,
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	}, self.canvas)
	Elements.corner(button, 3)
	button.Activated:Connect(function()
		if #(node.children or {}) > 0 then
			self:setFocus(node.path)
		end
	end)
	button.MouseEnter:Connect(function()
		self.tooltip.Text = string.format(
			"%s\nP50 %s  |  P10 %s  |  P90 %s\nClick to focus this subtree",
			node.name,
			Stats.formatDuration(node.stats.p50),
			Stats.formatDuration(node.stats.p10),
			Stats.formatDuration(node.stats.p90)
		)
		self.tooltip.Position = UDim2.fromOffset(
			math.clamp(x + 8, 4, math.max(4, self.canvas.AbsoluteSize.X - 290)),
			math.clamp(y + rowHeight, 4, math.max(4, self.canvas.AbsoluteSize.Y - 62))
		)
		self.tooltip.Visible = true
	end)
	button.MouseLeave:Connect(function()
		self.tooltip.Visible = false
	end)

	local total = layoutTotal(node)
	local childX = x
	for index, child in ipairs(node.children or {}) do
		local childWidth = width * math.clamp(child.stats.p50 / total, 0, 1)
		self:drawNode(child, childX, childWidth, depth + 1, colorIndex + index)
		childX += childWidth
	end
end

function ProfilerChart:render()
	if not self.palette then
		return
	end
	for _, child in ipairs(self.canvas:GetChildren()) do
		if child ~= self.empty and child ~= self.tooltip and not child:IsA("UICorner") then
			child:Destroy()
		end
	end
	self.tooltip.Visible = false
	self:renderBreadcrumbs()

	if not self.case or not self.case.profile then
		self.empty.Visible = true
		return
	end
	self.empty.Visible = false
	local focus = findNode(self.case.profile, self.focusPath) or self.case.profile
	local width = self.canvas.AbsoluteSize.X
	local total = layoutTotal(focus)
	local x = 0
	for index, child in ipairs(focus.children or {}) do
		local childWidth = width * math.clamp(child.stats.p50 / total, 0, 1)
		self:drawNode(child, x, childWidth, 0, index)
		x += childWidth
	end
end

return ProfilerChart
