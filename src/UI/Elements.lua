local Elements = {}

local FONT = Enum.Font.Gotham
local FONT_MEDIUM = Enum.Font.GothamMedium

function Elements.new(className, properties, parent)
	local instance = Instance.new(className)
	for property, value in pairs(properties or {}) do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

function Elements.theme(instance, background, text, stroke)
	if background then
		instance:SetAttribute("ThemeBackground", background)
	end
	if text then
		instance:SetAttribute("ThemeText", text)
	end
	if stroke then
		instance:SetAttribute("ThemeStroke", stroke)
	end
	return instance
end

function Elements.applyTheme(root, palette)
	local objects = { root }
	for _, descendant in ipairs(root:GetDescendants()) do
		table.insert(objects, descendant)
	end
	for _, object in ipairs(objects) do
		local background = object:GetAttribute("ThemeBackground")
		local text = object:GetAttribute("ThemeText")
		local stroke = object:GetAttribute("ThemeStroke")
		if background then
			object.BackgroundColor3 = palette[background]
		end
		if text then
			object.TextColor3 = palette[text]
		end
		if stroke and object:IsA("UIStroke") then
			object.Color = palette[stroke]
		end
	end
end

function Elements.corner(parent, radius)
	return Elements.new("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, parent)
end

function Elements.stroke(parent, key, thickness)
	local stroke = Elements.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = thickness or 1,
		Transparency = 0,
	}, parent)
	Elements.theme(stroke, nil, nil, key or "border")
	return stroke
end

function Elements.label(parent, text, size, position, options)
	options = options or {}
	local label = Elements.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = options.medium and FONT_MEDIUM or FONT,
		Text = text or "",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = options.textSize or 13,
		TextXAlignment = options.align or Enum.TextXAlignment.Left,
		TextYAlignment = options.verticalAlign or Enum.TextYAlignment.Center,
		TextTruncate = options.truncate or Enum.TextTruncate.AtEnd,
		TextWrapped = options.wrapped or false,
		Size = size or UDim2.fromScale(1, 1),
		Position = position or UDim2.fromOffset(0, 0),
		ZIndex = options.zIndex or 1,
	}, parent)
	Elements.theme(label, nil, options.color or "text")
	return label
end

function Elements.button(parent, text, size, position, options)
	options = options or {}
	local button = Elements.new("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Font = FONT_MEDIUM,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = options.textSize or 12,
		Size = size or UDim2.fromOffset(80, 30),
		Position = position or UDim2.fromOffset(0, 0),
		ZIndex = options.zIndex or 2,
	}, parent)
	Elements.theme(button, options.background or "elevated", options.color or "text")
	Elements.corner(button, options.radius or 5)
	if options.stroke ~= false then
		Elements.stroke(button, options.strokeKey or "border")
	end
	return button
end

function Elements.input(parent, placeholder, size, position)
	local input = Elements.new("TextBox", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = FONT,
		PlaceholderText = placeholder or "",
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		PlaceholderColor3 = Color3.fromRGB(130, 135, 148),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = size or UDim2.fromOffset(64, 30),
		Position = position or UDim2.fromOffset(0, 0),
	}, parent)
	Elements.theme(input, "elevated", "text")
	Elements.corner(input, 5)
	Elements.stroke(input, "border")
	return input
end

function Elements.panel(parent, size, position)
	local panel = Elements.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = size,
		Position = position,
	}, parent)
	Elements.theme(panel, "surface")
	Elements.corner(panel, 7)
	Elements.stroke(panel, "border")
	return panel
end

function Elements.clear(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

return Elements
