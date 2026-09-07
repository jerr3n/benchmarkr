local Theme = {}

local function studioColor(studioTheme, colorName, fallback)
	local found, enumValue = pcall(function()
		return Enum.StudioStyleGuideColor[colorName]
	end)
	if not found or not enumValue then
		return fallback
	end
	local ok, value = pcall(studioTheme.GetColor, studioTheme, enumValue)
	if ok then
		return value
	end
	return fallback
end

function Theme.resolve()
	local studioTheme = settings().Studio.Theme
	local nameOk, themeName = pcall(function()
		return studioTheme.Name
	end)
	local isDark = not nameOk or string.find(string.lower(tostring(themeName)), "dark") ~= nil
	local fallback = if isDark
		then {
			background = Color3.fromRGB(21, 24, 31),
			surface = Color3.fromRGB(29, 33, 42),
			elevated = Color3.fromRGB(38, 43, 54),
			text = Color3.fromRGB(240, 243, 249),
			muted = Color3.fromRGB(158, 166, 181),
			border = Color3.fromRGB(57, 64, 78),
			hover = Color3.fromRGB(48, 55, 68),
		}
		else {
			background = Color3.fromRGB(243, 245, 248),
			surface = Color3.fromRGB(255, 255, 255),
			elevated = Color3.fromRGB(232, 235, 240),
			text = Color3.fromRGB(28, 32, 40),
			muted = Color3.fromRGB(93, 101, 116),
			border = Color3.fromRGB(202, 207, 216),
			hover = Color3.fromRGB(220, 224, 232),
		}

	return {
		isDark = isDark,
		background = studioColor(studioTheme, "MainBackground", fallback.background),
		surface = studioColor(studioTheme, "ScriptEditor", fallback.surface),
		elevated = studioColor(studioTheme, "InputFieldBackground", fallback.elevated),
		text = studioColor(studioTheme, "MainText", fallback.text),
		muted = studioColor(studioTheme, "DimmedText", fallback.muted),
		border = studioColor(studioTheme, "Border", fallback.border),
		hover = studioColor(studioTheme, "Button", fallback.hover),
		accent = Color3.fromRGB(91, 124, 250),
		accentHover = Color3.fromRGB(111, 142, 255),
		accentText = Color3.fromRGB(255, 255, 255),
		success = Color3.fromRGB(63, 185, 130),
		warning = Color3.fromRGB(235, 174, 68),
		danger = Color3.fromRGB(239, 100, 107),
		graph = if isDark then Color3.fromRGB(24, 28, 36) else Color3.fromRGB(249, 250, 252),
		grid = if isDark then Color3.fromRGB(49, 55, 68) else Color3.fromRGB(218, 222, 230),
	}
end

Theme.series = {
	Color3.fromRGB(91, 124, 250),
	Color3.fromRGB(42, 190, 160),
	Color3.fromRGB(238, 129, 76),
	Color3.fromRGB(194, 108, 230),
	Color3.fromRGB(235, 190, 72),
	Color3.fromRGB(66, 160, 224),
	Color3.fromRGB(233, 99, 142),
	Color3.fromRGB(134, 196, 83),
}

return Theme
