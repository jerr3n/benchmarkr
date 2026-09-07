local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local contents = fs.readFile("build/Benchmarkr.rbxm")
local instances = roblox.deserializeModel(contents)

assert(#instances == 1, "plugin artifact must contain exactly one root instance")
local root = instances[1]
assert(root:IsA("Model"), "plugin artifact root must be a Model")
assert(root.Name == "Benchmarkr", "plugin artifact root must be named Benchmarkr")

local main = root:FindFirstChild("Main")
assert(main and main:IsA("Script"), "plugin artifact must contain its Main plugin script")
assert(
	string.find(main.Source, "Controller.start(plugin)", 1, true),
	"Main must start the controller"
)

for _, folderName in ipairs({ "Core", "Studio", "UI" }) do
	local folder = root:FindFirstChild(folderName)
	assert(
		folder and folder:IsA("Folder"),
		"plugin artifact is missing the " .. folderName .. " folder"
	)
	assert(#folder:GetChildren() > 0, folderName .. " must not be empty")
end

local errorBars = root.Core:FindFirstChild("ErrorBars")
assert(errorBars and errorBars:IsA("ModuleScript"), "artifact must include error-bar data helpers")

local graph = root.UI:FindFirstChild("Graph")
assert(graph and graph:IsA("ModuleScript"), "artifact must include the graph UI")
assert(string.find(graph.Source, 'self:setMode("line")', 1, true), "graph must expose line mode")
assert(
	string.find(graph.Source, 'self:setMode("errorbars")', 1, true),
	"graph must expose error-bar mode"
)

print("PASS plugin artifact structure")
