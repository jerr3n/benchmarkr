local Core = script.Parent.Parent.Core
local UI = script.Parent.Parent.UI

local History = require(Core.History)
local Report = require(Core.Report)
local Runner = require(Core.Runner)
local State = require(Core.State)
local Theme = require(UI.Theme)
local Dashboard = require(UI.Dashboard)
local Loader = require(script.Parent.Loader)
local ReportModel = require(script.Parent.ReportModel)
local Template = require(script.Parent.Template)

local Controller = {}

local HISTORY_KEY = "Benchmarkr.History.v1"

local function safeStudioVersion()
	local ok, value = pcall(function()
		return settings().Diagnostics.RobloxVersion
	end)
	return ok and value or "unknown"
end

local function reportIsValid(report)
	return Report.validate(report)
end

local function traceback(message)
	return debug.traceback(tostring(message), 2)
end

local function createWidget(plugin)
	local info =
		DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 1120, 720, 760, 480)
	local ok, widget = pcall(plugin.CreateDockWidgetPluginGuiAsync, plugin, "Benchmarkr.Main", info)
	if not ok then
		widget = plugin:CreateDockWidgetPluginGui("Benchmarkr.Main", info)
	end
	widget.Title = "Benchmarkr"
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return widget
end

function Controller.start(plugin)
	local services = {
		ChangeHistoryService = game:GetService("ChangeHistoryService"),
		HttpService = game:GetService("HttpService"),
		ScriptEditorService = game:GetService("ScriptEditorService"),
		Selection = game:GetService("Selection"),
		ServerStorage = game:GetService("ServerStorage"),
	}
	local state = State.initial()
	local selectedModule
	local currentReport
	local running = false
	local stopRequested = false
	local suppressSelection = false
	local selectionPending = false
	local activeCleanup

	local storedHistory
	local historyLoadOk, historyValue = pcall(plugin.GetSetting, plugin, HISTORY_KEY)
	if historyLoadOk then
		storedHistory = historyValue
	end
	local history, historyWasReset = History.normalize(storedHistory)

	local widget = createWidget(plugin)
	local toolbar = plugin:CreateToolbar("Benchmarkr")
	local toolbarButton =
		toolbar:CreateButton("Benchmarkr.Toggle", "Open the Benchmarkr profiler", "", "Benchmarkr")
	toolbarButton.ClickableWhenViewportHidden = true

	local handlers = {}
	local dashboard = Dashboard.new(widget, handlers)
	dashboard:setPalette(Theme.resolve())
	dashboard:setHistory(history)

	local function saveHistory()
		local ok, err = pcall(plugin.SetSetting, plugin, HISTORY_KEY, history)
		if not ok then
			dashboard:setStatus("Could not save history: " .. tostring(err), "warning")
		end
		dashboard:setHistory(history)
	end

	local function baselineFor(report)
		if not report or not report.suite then
			return nil
		end
		return History.getBaseline(history, report.suite.id)
	end

	local function showReport(report, mode)
		currentReport = report
		local baseline = baselineFor(report)
		local comparison = History.compare(report, baseline)
		dashboard:setReport(report, baseline, comparison, mode ~= "result")
		if mode == "imported" then
			state = State.reduce(state, { type = "IMPORT_REPORT", result = report })
		elseif mode == "history" then
			state = State.reduce(state, { type = "VIEW_HISTORY", result = report })
		else
			state = State.reduce(state, { type = "RUN_SUCCESS", result = report })
		end
		dashboard:setStatus(state.message, "success")
	end

	local function importReport(folder)
		local json, readError = ReportModel.read(folder)
		if not json then
			dashboard:showError("Could not open report", readError)
			return
		end
		local ok, decoded = pcall(services.HttpService.JSONDecode, services.HttpService, json)
		if not ok or not reportIsValid(decoded) then
			dashboard:showError(
				"Could not open report",
				"The report JSON is invalid or unsupported."
			)
			return
		end
		selectedModule = nil
		showReport(decoded, "imported")
		dashboard:setSelection(decoded.suite.name or decoded.suite.id, state.message, false)
	end

	local function selectionChanged()
		if suppressSelection then
			return
		end
		if running then
			selectionPending = true
			return
		end
		local selection = services.Selection:Get()
		if #selection == 1 and selection[1]:IsA("ModuleScript") then
			selectedModule = selection[1]
			state = State.reduce(state, {
				type = "SELECT_VALID",
				selection = selectedModule,
				message = "Ready. Blank inputs use suite defaults.",
			})
			dashboard:setSelection(selectedModule.Name, state.message, true)
		elseif #selection == 1 and ReportModel.isReport(selection[1]) then
			importReport(selection[1])
		elseif #selection == 0 then
			selectedModule = nil
			state = State.reduce(state, {
				type = "SELECT_INVALID",
				message = "Select a benchmark ModuleScript to run it.",
			})
			dashboard:setSelection("No suite selected", state.message, false)
		else
			selectedModule = nil
			state = State.reduce(state, {
				type = "SELECT_INVALID",
				message = "Select exactly one ModuleScript or Benchmarkr report folder.",
			})
			dashboard:setSelection("Selection is not runnable", state.message, false)
		end
	end

	local function refreshPendingSelection()
		if selectionPending then
			selectionPending = false
			selectionChanged()
		end
	end

	function handlers.onRun()
		if running or not selectedModule then
			return
		end
		local overrides, inputError = dashboard:getOverrides()
		if not overrides then
			dashboard:showError("Invalid run settings", inputError)
			return
		end

		running = true
		stopRequested = false
		state = State.reduce(state, { type = "RUN_START" })
		dashboard:setRunning(true)
		dashboard:setStatus(state.message, "muted")
		local sourceModule = selectedModule
		local sourceName = sourceModule.Name
		local sourcePath = sourceModule:GetFullName()

		task.spawn(function()
			local suite, loadError, cleanup = Loader.load(sourceModule, services)
			if not cleanup then
				running = false
				dashboard:setRunning(false)
				state = State.reduce(state, {
					type = "RUN_ERROR",
					message = "The benchmark module could not be loaded.",
				})
				dashboard:setStatus(state.message, "danger")
				dashboard:showError("Module load failed", loadError)
				refreshPendingSelection()
				return
			end
			activeCleanup = cleanup

			local runOk, result = xpcall(function()
				return Runner.run(suite, overrides, {
					shouldStop = function()
						return stopRequested
					end,
					onProgress = function(completed, total, phase, caseName)
						dashboard:setProgress(completed, total, phase, caseName)
					end,
				})
			end, traceback)
			cleanup()
			activeCleanup = nil
			if not runOk then
				result = { status = "error", error = result }
			end

			running = false
			dashboard:setRunning(false)
			if result.status == "cancelled" then
				state = State.reduce(state, { type = "RUN_CANCELLED" })
				dashboard:setStatus(state.message, "warning")
				refreshPendingSelection()
				return
			elseif result.status == "error" then
				state = State.reduce(state, {
					type = "RUN_ERROR",
					message = "Benchmark failed. Previous results were preserved.",
				})
				dashboard:setStatus(state.message, "danger")
				dashboard:showError("Benchmark failed", result.error)
				refreshPendingSelection()
				return
			end

			local fallbackId = string.format(
				"%s:%s",
				tostring(game.GameId ~= 0 and game.GameId or game.PlaceId),
				sourcePath
			)
			local suiteId = result.suite.id or fallbackId
			local suiteName = result.suite.name or sourceName
			local report = Report.create({
				createdAt = DateTime.now():ToIsoDate(),
				suiteId = suiteId,
				suiteName = suiteName,
				sourcePath = sourcePath,
				placeId = game.PlaceId,
				gameId = game.GameId,
				studioVersion = safeStudioVersion(),
			}, result)
			History.add(history, report)
			saveHistory()
			showReport(report, "result")
			dashboard:setStatus(string.format("Complete | seed %d", report.config.seed), "success")
			refreshPendingSelection()
		end)
	end

	function handlers.onStop()
		if running then
			stopRequested = true
			dashboard:setStatus("Stopping after the current invocation...", "warning")
		end
	end

	function handlers.onNew()
		if running then
			return
		end
		local created, createError = Template.create(services)
		if not created then
			dashboard:showError("Could not create benchmark", tostring(createError))
		end
	end

	function handlers.onHistorySelect(report)
		if not running and reportIsValid(report) then
			showReport(report, "history")
		end
	end

	function handlers.onPinBaseline()
		if not currentReport or running then
			return
		end
		History.pin(history, currentReport)
		saveHistory()
		showReport(currentReport, state.mode == "result" and "result" or "history")
		dashboard:setStatus("Baseline pinned for this suite.", "success")
	end

	function handlers.onExport(kind)
		if not currentReport or running then
			return
		end
		local baseline = baselineFor(currentReport)
		local jsonOk, json =
			pcall(services.HttpService.JSONEncode, services.HttpService, currentReport)
		if not jsonOk then
			dashboard:showError("Export failed", tostring(json))
			return
		end
		local csv = Report.toCsv(currentReport, baseline)
		if kind == "json" then
			dashboard:showText("JSON report", json)
		elseif kind == "csv" then
			dashboard:showText("CSV summary", csv)
		elseif kind == "rbxm" then
			suppressSelection = true
			local saved, saveError =
				ReportModel.promptSave(plugin, services, json, csv, currentReport.createdAt)
			suppressSelection = false
			selectionChanged()
			if saveError then
				dashboard:showError("RBXM export failed", tostring(saveError))
			elseif saved then
				dashboard:setStatus("Portable RBXM report saved.", "success")
			else
				dashboard:setStatus("RBXM export cancelled.", "muted")
			end
		end
	end

	toolbarButton.Click:Connect(function()
		widget.Enabled = not widget.Enabled
	end)
	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		toolbarButton:SetActive(widget.Enabled)
	end)
	toolbarButton:SetActive(widget.Enabled)
	widget:BindToClose(function()
		widget.Enabled = false
	end)
	services.Selection.SelectionChanged:Connect(selectionChanged)
	settings().Studio.ThemeChanged:Connect(function()
		dashboard:setPalette(Theme.resolve())
	end)
	plugin.Unloading:Connect(function()
		stopRequested = true
		if activeCleanup then
			activeCleanup()
			activeCleanup = nil
		end
	end)

	selectionChanged()
	if historyWasReset then
		dashboard:setStatus("Stored history was invalid and has been reset.", "warning")
	end
	return {
		widget = widget,
		dashboard = dashboard,
	}
end

return Controller
