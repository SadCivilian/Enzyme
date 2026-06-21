--!strict
--!native

-- An easy to use, lines of code counter for Roblox Studio. Inspired by "tokei".

type ScriptContextTypes = "Server" | "Client" | "Module" | "Plugin"

type ScriptStats = {
	[string] : number,
	Lines : number,
	Code : number,
	Comments : number,
	Blanks : number
}

type ScriptInformation = {
	FileName : string,
	ScriptStats : ScriptStats
}

type TotalResult = {
	[ScriptContextTypes | string] : ScriptStats,
	Server : ScriptStats,
	Client : ScriptStats,
	Module : ScriptStats,
	Plugin : ScriptStats,
	Total : ScriptStats
}

type Results = {
	[ScriptContextTypes | string] : {ScriptInformation}, -- I didn't even know this was a thing to be fair, anything to please the linter/solver
	Server : {ScriptInformation?},
	Client : {ScriptInformation?},
	Module : {ScriptInformation?},
	Plugin : {ScriptInformation?},
	Total : TotalResult,
	Files : number,
}

-- Returns an assetid from a number.
local function asset(id : number) : string
	return "rbxassetid://" .. id
end

local StudioService = game:GetService("StudioService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local Selection = game:GetService("Selection")
local EnzymeToolbar = plugin:CreateToolbar("Enzyme")
local ResultsDock = plugin:CreateDockWidgetPluginGuiAsync("ResultsDock", DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 400, 400, 400, 400))
local AnalyzeCurrentScriptButton = EnzymeToolbar:CreateButton("AnalyzeCurrentScriptButton", "Analyzes the current script.", asset(73185307343306), "Analyze Current Script")
local AnalyzeUnderInstanceButton = EnzymeToolbar:CreateButton("AnalyzeUnderInstancesButton", "Analyzes the scripts which are a descendant of the selected objects.", asset(73185307343306), "Analyze Under Instances")
local AnalyzeGameButton = EnzymeToolbar:CreateButton("AnalyzeGameButton", "Analyzes your entire DataModel.", asset(73185307343306), "Analyze DataModel")
AnalyzeCurrentScriptButton.ClickableWhenViewportHidden = true
AnalyzeUnderInstanceButton.ClickableWhenViewportHidden = true
AnalyzeGameButton.ClickableWhenViewportHidden = true
ResultsDock.Title = "[Enzyme] Results"
ResultsDock.Enabled = false
ResultsDock.Name = "Enzyme Results Dock"

const LegacyEndpoints : {any} = {workspace, game.ServerScriptService, game.ServerStorage, game.StarterPlayer.StarterPlayerScripts, game.StarterPlayer.StarterCharacterScripts, game.ReplicatedFirst, game.StarterGui}
const LegacyEndpointsMap : {[any] : ScriptContextTypes} = {[workspace] = "Server", [game.ServerScriptService] = "Server", [game.ServerStorage] = "Server", [game.StarterPlayer.StarterPlayerScripts] = "Client", [game.StarterPlayer.StarterCharacterScripts] = "Client", [game.ReplicatedFirst] = "Client", [game.StarterGui] = "Client"}
const Names = {"File", "Lines", "Code", "Comments", "Blanks"} -- Used in more than one place, so why not have it here
const ContextMap = {"Client", "Server", "Module", "Plugin", "Total"}

-- Reverse clamp.
local function reverseClamp(value : number, minValue : number, maxValue : number) : number
	if value < minValue then
		return maxValue
	elseif value > maxValue then
		return minValue
	end
	return value
end

-- Returns the length of a dictionary.
local function dictLen<K,V>(t : {[K] : V})
	local s = 0
	for _, _ in t do
		s += 1
	end
	return s
end

-- Returns an empty ScriptStats object.
local function makeEmptyScriptStats() : ScriptStats
	return {Lines = 0, Code = 0, Comments = 0, Blanks = 0} :: ScriptStats
end

-- Returns an empty TotalResult object.
local function makeEmptyTotalResult() : TotalResult
	return {Server = makeEmptyScriptStats(), Client = makeEmptyScriptStats(), Module = makeEmptyScriptStats(), Plugin = makeEmptyScriptStats(), Total = makeEmptyScriptStats()} :: TotalResult
end

-- Returns an empty ScriptInformation object.
local function makeEmptyScriptInformation() : ScriptInformation
	return {FileName = "", ScriptStats = makeEmptyScriptStats()} :: ScriptInformation
end

-- Returns an empty results object with all fields set to defaults.
local function makeEmptyResults() : Results
	return {
		["Server"] = {},
		["Client"] =  {},
		["Module"] = {},
		["Plugin"] = {},
		["Total"] = makeEmptyTotalResult(),
		["Files"] = 0,
	} :: Results
end

-- Sums up two ScriptStats objects.
local function SumScriptStats(i1 : ScriptStats, i2 : ScriptStats) : ScriptStats
	return {Lines = i1.Lines + i2.Lines, Code = i1.Code + i2.Code, Comments = i1.Comments + i2.Comments, Blanks = i1.Blanks + i2.Blanks} :: ScriptStats
end

-- Generates a Results object from a ScriptInformation object with only the given context filled out with said ScriptInformation object.
local function makeResultsFromScriptInformation(context : ScriptContextTypes, info : ScriptInformation) : Results
	local singleton : {ScriptContextTypes} = {"Server", "Client", "Module", "Plugin"}
	local res : Results = makeEmptyResults()
	for _, v in singleton do
		if v == context then
			res[context] = {info}
		else
			res[v] = {}
		end
	end

	local newTotal = makeEmptyTotalResult()

	for _, v in singleton do
		if v == context then
			newTotal[context] = info.ScriptStats
		else
			newTotal[v] = makeEmptyScriptStats()
		end
	end

	newTotal["Total"] = info.ScriptStats

	res["Total"] = newTotal
	res["Files"] = 1
	return res
end

-- Destroys the scrollbar on a scrolling frame.
local function destroyScrollbar(sFrame : ScrollingFrame) : ()
	sFrame.BottomImage = ""
	sFrame.MidImage = ""
	sFrame.TopImage = ""
end

-- Returns a frame that represents a Script and it's information to be inserted into UI.
local function makeFileFrameFromInformation(info : ScriptInformation)
	local posOffsetScale = 0.18
	local FileFrame = Instance.new("Frame")
	FileFrame.Size = UDim2.fromScale(0.97, 0.035)
	FileFrame.BackgroundTransparency = 1

	for i, name in ipairs(Names) do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.2, 1)
		label.Position = UDim2.fromScale((i - 1) * posOffsetScale, 0.058)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255,255,255)
		if name == "File" then
			label.Text = info.FileName
		else
			label.Text = tostring(info.ScriptStats[name])
		end
		label.Name = name
		label.Parent = FileFrame
	end

	return FileFrame
end

-- Removes all frame children from an instance.
local function cleanFrames(instance : Instance)
	for _, obj in instance:GetChildren() do
		if obj:IsA("Frame") then
			obj:Destroy()
		end
	end
end

-- Makes the presentation for a totalResult with a table of frames.
local function makeFileFramesFromTotal(totalResult : TotalResult) : {Frame}
	local posOffsetScale = 0.18
	local ret = table.create(5) :: {Frame}
	for i, name in ipairs(Names) do
		local FileFrame = Instance.new("Frame")
		FileFrame.Size = UDim2.fromScale(0.97, 0.035)
		FileFrame.BackgroundTransparency = 1

		for j, name in ipairs(Names) do
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(0.2, 1)
			label.Position = UDim2.fromScale((j - 1) * posOffsetScale, 0.058)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(255,255,255)
			if name == "File" then
				label.Text = ContextMap[i]
			else
				label.Text = tostring(totalResult[ContextMap[i]][name])
			end
			label.Name = name
			label.Parent = FileFrame
		end
		table.insert(ret, FileFrame)
	end
	return ret
end

-- Used for creating dynamic UI from a context.
local function parentDynamicUIToFrameFromContext(parent : Instance, context : ScriptContextTypes | "Total", results : Results)
	-- If this is the total we'll just do that and leave
	if context == "Total" then
		local Frames = makeFileFramesFromTotal(results["Total"])
		for _, obj in Frames do
			obj.Parent = parent
		end
		local BaseFrame = parent.Parent :: Frame
		(BaseFrame:FindFirstChild("Context") :: TextLabel).Text = "Total" .. " [" .. results.Files .. "]"
		return
	end

	local resultIndex = results[context]
	for _, info in ipairs(resultIndex) do
		local newFrame = makeFileFrameFromInformation(info)
		newFrame.Parent = parent
	end
end

-- Construct the results UI from the results object.
local function ConstructUIFromResults(results : Results)
	-- Convars
	local posOffsetScale = 0.18

	-- State
	local Page = 1

	-- Set up base UI
	ResultsDock:ClearAllChildren()
	local BaseFrame = Instance.new("Frame")
	BaseFrame.Size = UDim2.fromScale(1,1)
	BaseFrame.Parent = ResultsDock
	BaseFrame.Name = "Main"
	BaseFrame.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	local UICorner = Instance.new("UICorner")
	UICorner.CornerRadius = UDim.new(0.03, 0)
	UICorner.Parent = BaseFrame
	local UIStroke = Instance.new("UIStroke")
	UIStroke.Color = Color3.fromRGB(125,125,125)
	UIStroke.Thickness = 2
	UIStroke.Parent = BaseFrame
	local FileFrame = Instance.new("ScrollingFrame")
	UICorner:Clone().Parent = FileFrame
	FileFrame.Position = UDim2.fromScale(0.005, 0.173)
	FileFrame.Size = UDim2.fromScale(0.99, 0.824)
	destroyScrollbar(FileFrame)
	FileFrame.BackgroundColor3 = Color3.fromRGB(22,24,30)
	FileFrame.Parent = BaseFrame
	FileFrame.Name = "FileFrame"
	local LL = Instance.new("UIListLayout")
	LL.Padding = UDim.new(0.01, 0)
	LL.Parent = FileFrame
	local Seperator = Instance.new("Frame")
	Seperator.Position = UDim2.fromScale(0, 0.15)
	Seperator.Size = UDim2.fromScale(1, 0.006)
	Seperator.Parent = BaseFrame
	Seperator.Name = "Seperator"
	local sharedUICorner = Instance.new("UICorner")
	sharedUICorner.CornerRadius = UDim.new(0.5, 0)
	local Context = Instance.new("TextLabel")
	Context.Text = "Client" .. " [" .. #results["Client"] .. "]"
	Context.Position = UDim2.fromScale(0.392, 0)
	Context.Size = UDim2.fromScale(0.215, 0.043)
	Context.Parent = BaseFrame
	Context.Name = "Context"
	sharedUICorner:Clone().Parent = Context
	local Forward = Instance.new("TextButton")
	Forward.Text = ">"
	Forward.Position = UDim2.fromScale(0.927, 0)
	Forward.Size = UDim2.fromScale(0.073, 0.043)
	Forward.Name = "Forward"
	Forward.Parent = BaseFrame
	sharedUICorner:Clone().Parent = Forward
	local Backward = Instance.new("TextButton")
	Backward.Text = "<"
	Backward.Position = UDim2.fromScale(0, 0)
	Backward.Size = UDim2.fromScale(0.073, 0.043)
	Backward.Name = "Forward"
	Backward.Parent = BaseFrame
	sharedUICorner:Clone().Parent = Backward
	for i, name in ipairs(Names) do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.2, 0.058)
		label.Position = UDim2.fromScale((i - 1) * posOffsetScale, 0.058)
		label.Name = name
		label.Text = name
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255,255,255)
		label.Parent = BaseFrame
	end

	parentDynamicUIToFrameFromContext(FileFrame, "Client", results)

	Forward.MouseButton1Click:Connect(function()
		local newPage = reverseClamp(Page + 1, 1, 5)
		Page = newPage
		local newContext = ContextMap[newPage]
		cleanFrames(FileFrame)
		local resultIndex = results[newContext]
		Context.Text = newContext .. " [" .. #resultIndex .. "]"
		parentDynamicUIToFrameFromContext(FileFrame, newContext, results)
	end)

	Backward.MouseButton1Click:Connect(function()
		local newPage = reverseClamp(Page - 1, 1, 5)
		Page = newPage
		local newContext = ContextMap[newPage]
		cleanFrames(FileFrame)
		local resultIndex = results[newContext]
		Context.Text = newContext .. " [" .. #resultIndex .. "]"
		parentDynamicUIToFrameFromContext(FileFrame, newContext, results)
	end)

	BaseFrame.Parent = ResultsDock
end

-- Trims whitespace (tabs and spaces) from a string. Only includes the start of the string.
local function trimWhitespaceFromString(str : string) : string
	local a = str:gsub("\t", "")
	local b = a:gsub(" ", "")
	return b
end

-- Returns a boolean on whether a line of code is a PURE comment, meaning the line is purely a comment and does not include any code (similar to this current line!)
local function IsPureNonBlockComment(line : string)
	return trimWhitespaceFromString(line):sub(1,2) == "--"
end

-- Returns a ScriptInformation object from a script.
local function getScriptInformation(container : Script | LocalScript | ModuleScript | LuaSourceContainer) : ScriptInformation
	local lines = string.split(container.Source, "\n")

	local blanks = 0
	local code = 0
	local comments = 0

	local InBlockComment = false

	for index, line in ipairs(lines) do
		if line:find("--[[", 1, true) then
			InBlockComment = true
		elseif line:find("]]", 0, true) then
			comments += 1
			InBlockComment = false
			continue
		end

		if trimWhitespaceFromString(line) == "" then
			blanks += 1
			continue
		end

		if InBlockComment then
			comments += 1
			continue
		end

		if IsPureNonBlockComment(line) then
			comments += 1
		else
			code += 1
		end
	end

	-- Create the ScriptStats
	local newScriptStats = makeEmptyScriptStats()
	newScriptStats.Lines = #lines
	newScriptStats.Code = code
	newScriptStats.Blanks = blanks
	newScriptStats.Comments = comments

	return {FileName = container.Name, ScriptStats = newScriptStats} :: ScriptInformation
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

-- Merges two dictionaries, ignoring duplicates.
local function mergeDict<T, V>(t1 : {[T] : V}, t2 : {[T] : V}) : {[T] : V}
	for obj, value in t2 do
		if not t1[obj] then
			t1[obj] = value
		end
	end
	return t1
end

AnalyzeCurrentScriptButton.Click:Connect(function()
	local active = StudioService.ActiveScript :: LuaSourceContainer
	if not active then
		warn("[Enzyme]: No script is active.")
		return
	end

	local is, contexttype = getScriptTypeIfScript(active)
	local info = getScriptInformation(active)

	if not contexttype then return end -- Guard

	local Results = makeResultsFromScriptInformation(contexttype, info)
	ConstructUIFromResults(Results)
	ResultsDock.Enabled = true
end)

AnalyzeGameButton.Click:Connect(function()
	local files = gatherScriptFilesInDirectory(game)
	local Results = makeEmptyResults()
	local newTotal = makeEmptyTotalResult()

	for c, contexttype : ScriptContextTypes in files do
		local new = getScriptInformation(c)

		table.insert(Results[contexttype], new)

		local index = newTotal[contexttype]

		newTotal[contexttype] = SumScriptStats(index, new.ScriptStats)
		newTotal["Total"] = SumScriptStats(newTotal["Total"], new.ScriptStats)

		Results["Files"] += 1
	end

	Results["Total"] = newTotal

	ConstructUIFromResults(Results)
	ResultsDock.Enabled = true
end)

AnalyzeUnderInstanceButton.Click:Connect(function()
	local files = {} :: {[LuaSourceContainer] : ScriptContextTypes}
	for _, obj in Selection:Get() do
		local localFiles = gatherScriptFilesInDirectory(obj)
		local is, contexttype = getScriptTypeIfScript(obj)

		if is and contexttype then -- If the selected object is a script, include it as well
			local objectDict = {[obj :: LuaSourceContainer] = contexttype}
			localFiles = mergeDict(localFiles, objectDict)
		end

		files = mergeDict(files, localFiles) :: {[LuaSourceContainer] : ScriptContextTypes}
	end

	local Results = makeEmptyResults()
	local newTotal = makeEmptyTotalResult()

	for c, contexttype : ScriptContextTypes in files do
		local new = getScriptInformation(c)

		table.insert(Results[contexttype], new)

		local index = newTotal[contexttype]

		newTotal[contexttype] = SumScriptStats(index, new.ScriptStats)
		newTotal["Total"] = SumScriptStats(newTotal["Total"], new.ScriptStats)

		Results["Files"] += 1
	end

	Results["Total"] = newTotal

	ConstructUIFromResults(Results)
	ResultsDock.Enabled = true
end)
