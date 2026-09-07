local Stats = if script then require(script.Parent.Stats) else require("./Stats")

local Profiler = {}
local SEPARATOR = string.char(31)

local function traceback(message)
	return debug.traceback(tostring(message), 2)
end

function Profiler.create(clock)
	clock = clock or os.clock
	local stack = {}
	local nodes = {}
	local topLevelTime = 0
	local finished = false

	local api = {}

	function api.Begin(label)
		if finished then
			error("Profiler.Begin cannot be called after the sample finished", 2)
		end
		if type(label) ~= "string" or label == "" then
			error("Profiler.Begin expects a non-empty label", 2)
		end
		if label == "[UNTRACKED]" or string.find(label, SEPARATOR, 1, true) then
			error(
				"Profiler.Begin label is reserved or contains an unsupported control character",
				2
			)
		end

		local parentPath = #stack > 0 and stack[#stack].path or ""
		local path = parentPath .. SEPARATOR .. label
		table.insert(stack, {
			label = label,
			path = path,
			parentPath = parentPath,
			startedAt = clock(),
		})
	end

	function api.End()
		if finished then
			error("Profiler.End cannot be called after the sample finished", 2)
		end
		local frame = table.remove(stack)
		if not frame then
			error("Profiler.End was called without a matching Profiler.Begin", 2)
		end

		local duration = math.max(0, clock() - frame.startedAt)
		local node = nodes[frame.path]
		if not node then
			node = {
				name = frame.label,
				path = frame.path,
				parentPath = frame.parentPath,
				duration = 0,
			}
			nodes[frame.path] = node
		end
		node.duration += duration
		if frame.parentPath == "" then
			topLevelTime += duration
		end
	end

	local function finish(totalDuration)
		finished = true
		if #stack > 0 then
			local labels = table.create(#stack)
			for index, frame in ipairs(stack) do
				labels[index] = frame.label
			end
			return nil,
				string.format(
					"Profiler.Begin calls were not closed with Profiler.End: %s",
					table.concat(labels, " > ")
				)
		end

		local untrackedPath = SEPARATOR .. "[UNTRACKED]"
		nodes[untrackedPath] = {
			name = "[UNTRACKED]",
			path = untrackedPath,
			parentPath = "",
			duration = math.max(0, totalDuration - topLevelTime),
		}

		return {
			total = totalDuration,
			nodes = nodes,
		}
	end

	return api, finish
end

function Profiler.aggregate(records)
	assert(#records > 0, "cannot aggregate empty profiler records")
	local definitions = {}
	local totals = table.create(#records)

	for recordIndex, record in ipairs(records) do
		totals[recordIndex] = record.total
		for path, node in pairs(record.nodes) do
			definitions[path] = definitions[path]
				or {
					name = node.name,
					path = path,
					parentPath = node.parentPath,
				}
		end
	end

	local nodes = {
		[""] = {
			name = "Total",
			path = "",
			parentPath = nil,
			stats = Stats.summarize(totals),
			children = {},
		},
	}

	for path, definition in pairs(definitions) do
		local values = table.create(#records, 0)
		for recordIndex, record in ipairs(records) do
			local recordNode = record.nodes[path]
			values[recordIndex] = recordNode and recordNode.duration or 0
		end
		nodes[path] = {
			name = definition.name,
			path = path,
			parentPath = definition.parentPath,
			stats = Stats.summarize(values),
			children = {},
		}
	end

	for path, node in pairs(nodes) do
		if path ~= "" then
			local parent = nodes[node.parentPath] or nodes[""]
			table.insert(parent.children, node)
		end
	end

	local function sortChildren(node)
		table.sort(node.children, function(left, right)
			if left.name == "[UNTRACKED]" then
				return false
			elseif right.name == "[UNTRACKED]" then
				return true
			end
			if left.stats.p50 == right.stats.p50 then
				return left.name < right.name
			end
			return left.stats.p50 > right.stats.p50
		end)
		for _, child in ipairs(node.children) do
			sortChildren(child)
		end
	end
	sortChildren(nodes[""])

	return nodes[""]
end

function Profiler.tryCall(callback)
	return xpcall(callback, traceback)
end

return Profiler
