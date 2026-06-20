--!strict

-- An easy to use, lines of code counter for Roblox Studio. Inspired by "tokei".

type ScriptContextTypes = "Server" | "Client" | "Module" | "Plugin"

type Results = {
	Server : number,
	Client : number,
	Module : number,
	Plugin : number,
	Total : number
}

local StudioService = game:GetService("StudioService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local Selection = game:GetService("Selection")
local EnzymeToolbar = plugin:CreateToolbar("Enzyme")
local ResultsDock = plugin:CreateDockWidgetPluginGuiAsync("ResultsDock", DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 400, 400, 400, 400))
local AnalyzeCurrentScriptButton = EnzymeToolbar:CreateButton("AnalyzeCurrentScriptButton", "Analyzes the current script.", "tbm", "Analyze Current Script")
local AnalyzeUnderInstanceButton = EnzymeToolbar:CreateButton("AnalyzeUnderInstancesButton", "Analyzes the scripts which are a descendant of the selected objects.", "tbm", "Analyze Under Instances")
local AnalyzeGameButton = EnzymeToolbar:CreateButton("AnalyzeGameButton", "Analyzes your entire DataModel.", "tbm", "Analyze DataModel")
AnalyzeUnderInstanceButton.ClickableWhenViewportHidden = true
AnalyzeGameButton.ClickableWhenViewportHidden = true
ResultsDock.Title = "[Enzyme] Results"
ResultsDock.Enabled = false

const LegacyEndpoints : {any} = {workspace, game.ServerScriptService, game.ServerStorage, game.StarterPlayer.StarterPlayerScripts, game.StarterPlayer.StarterCharacterScripts, game.ReplicatedFirst}
const LegacyEndpointsMap : {[any] : ScriptContextTypes} = {[workspace] = "Server", [game.ServerScriptService] = "Server", [game.ServerStorage] = "Server", [game.StarterPlayer.StarterPlayerScripts] = "Client", [game.StarterPlayer.StarterCharacterScripts] = "Client", [game.ReplicatedFirst] = "Client", [game.StarterGui] = "Client"}

-- Returns an empty results object with all fields set to 0.
local function makeEmptyResults() : Results
	return {
		["Server"] = 0,
		["Client"] = 0,
		["Module"] = 0,
		["Plugin"] = 0,
		["Total"] = 0
	} :: Results
end

local function ConstructUIFromResults(results : Results)
	ResultsDock:ClearAllChildren()
	local BaseFrame = Instance.new("Frame")
	BaseFrame.Size = UDim2.fromScale(1,1)
	BaseFrame.Parent = ResultsDock
end

-- Get the line count from a LuaSourceContainer.
local function getLineCount(container : LuaSourceContainer) : number
	if container:IsA("LocalScript") or container:IsA("Script") or container:IsA("ModuleScript") then
		return #string.split(container.Source, "\n")
	end
	return 0
end

-- Gets the actual RunContext of a script which has a Legacy RunContext. If it is not narrowable, a warning is thrown and the file defaults to "Server".
local function GetLegacyScriptRunContext(container : BaseScript) : ScriptContextTypes
	local current : any = container
	while current.Parent ~= game do
		current = current.Parent
		if table.find(LegacyEndpoints, current) then
			return LegacyEndpointsMap[current]
		end
	end
	return "Server"
end

-- Returns whether the given object is a script, and if it is, returns its RunContext (or Module, as modules can be either).
local function getScriptTypeIfScript(obj : Instance) : (boolean, ScriptContextTypes?)
	if obj:IsA("LuaSourceContainer") then
		if obj:IsA("BaseScript") then -- Like what even
			if obj.RunContext == Enum.RunContext.Legacy then
				return true, GetLegacyScriptRunContext(obj)
			end
			return true, obj.RunContext.Name :: ScriptContextTypes
		else
			return true, "Module"
		end
	else
		return false, nil
	end
end

-- Gathers every script file under the given instance, if any.
local function gatherScriptFilesInDirectory(dir : Instance) : {[LuaSourceContainer] : ScriptContextTypes}
	local files : {[LuaSourceContainer] : ScriptContextTypes} = {}
	for _, obj in dir:GetDescendants() do
		local is, scriptType = getScriptTypeIfScript(obj)
		if is and scriptType then
			files[obj :: LuaSourceContainer] = scriptType :: ScriptContextTypes
		end
	end
	return files
end

-- Merges two tables, ignoring duplicates.
local function mergeDict<T, V>(t1 : {[T] : V}, t2 : {[T] : V}) : {[T] : V}
	for obj, value in t2 do
		if not t1[obj] then
			t1[obj] = value
		end
	end
	return t1
end

AnalyzeCurrentScriptButton.Click:Connect(function()
	local active = StudioService.ActiveScript
	if not active then
		warn("[Enzyme]: No script is active.")
	end
	local lines = getLineCount(StudioService.ActiveScript)
	print(string.format("[Enzyme]: The current script has %s lines.", tostring(lines)))
end)

AnalyzeGameButton.Click:Connect(function()
	local files = gatherScriptFilesInDirectory(game)
	local Results = makeEmptyResults()

	for c, contexttype : ScriptContextTypes in files do
		local lines = getLineCount(c)

		Results[contexttype] += lines
		Results["Total"] += lines
	end
	ConstructUIFromResults(Results)

	print(Results)
end)

AnalyzeUnderInstanceButton.Click:Connect(function()
	local files = {} :: {[LuaSourceContainer] : ScriptContextTypes}
	for _, obj in Selection:Get() do
		local localFiles = gatherScriptFilesInDirectory(obj)
		files = mergeDict(files, localFiles) :: {[LuaSourceContainer] : ScriptContextTypes}
	end

	local Results = makeEmptyResults()

	for c, contexttype : ScriptContextTypes in files do
		local lines = getLineCount(c)
		Results[contexttype] += lines
		Results["Total"] += lines
	end
	print(Results)
end)
