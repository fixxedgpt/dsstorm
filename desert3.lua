local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local DESERT_STORM_GAME_ID = 9161571268

if not LocalPlayer then
	warn("LocalPlayer is unavailable; aborting cleanly.")
	return
end

local ActiveGameId
pcall(function()
	ActiveGameId = game.GameId
end)

if ActiveGameId and ActiveGameId ~= DESERT_STORM_GAME_ID then
	warn("DesertStorm aim profile loaded outside its intended universe; settings may need adjustment.")
end

local Environment = _G
pcall(function()
	local CurrentEnvironment = getfenv()
	if type(CurrentEnvironment) == "table" then
		Environment = CurrentEnvironment
	end
end)

local ExistingRuntime = Environment.__MatchaAimRuntime
if type(ExistingRuntime) == "table" and type(ExistingRuntime.Unload) == "function" then
	pcall(ExistingRuntime.Unload)
end

local Flags = {
	Running = true,
	Aimbot = false,
	AimbotActive = false,
	AutoPrediction = true,
	SilentAim = false,
	SilentFovCheck = true,
	SilentFovRadius = 80,
	SilentMaxDistance = 1800,
	TeamCheck = false,
	StickyAim = true,
	FovCheck = true,
	TargetParts = { "Head", "Upper Torso" },
	AimProfile = "Rifles",
	AimSmoothness = 20,
	FovRadius = 120,
	MaxAcquireDistance = 1800,
	ProjectileSpeed = 2500,
	GravityCompensation = 196.2,
	PredictionScale = 0.85,
	NetworkScale = 1,
	MaxPredictionTime = 0.65,
	PredictionProfile = "Rifle",
	FovColor = Color3.fromRGB(149, 192, 33),
	FovAlpha = 1,
	EspEnabled = false,
	EspTeamCheck = false,
	EspBox = true,
	EspBoxColor = Color3.fromRGB(235, 235, 235),
	EspBoxAlpha = 1,
	EspChams = false,
	EspChamsColor = Color3.fromRGB(180, 45, 45),
	EspChamsAlpha = 0.18,
	EspHealth = true,
	EspName = true,
	EspWeapon = true,
	EspDistance = true,
	EspSnapline = false,
	EspSnaplineColor = Color3.fromRGB(149, 192, 33),
	EspSnaplineAlpha = 0.8,
	EspTextColor = Color3.fromRGB(235, 235, 235),
	EspTextAlpha = 1,
	EspMaxDistance = 2500,
	CrateEspEnabled = false,
	CrateEspTrackedNames = { "All crates" },
	CrateEspTrackedOthers = {},
	CrateEspBox = true,
	CrateEspBoxStyle = "Corners",
	CrateEspShowDistance = true,
	CrateEspColor = Color3.fromRGB(214, 176, 72),
	CrateEspAlpha = 1,
	CrateEspMaxDistance = 2000,
	LockedPlayerName = nil,
}

local Connections = {}
local Drawings = {}
local Win
local SilentAim
local SmoothedAimPosition
local SmoothedAimTargetName
local EspStatus = {
	Text = "off",
	LastError = nil,
}
local CrateEspStatus = {
	Text = "off",
}
local CrateTrackChoices = {
	"All crates",
	"Wooden Crate",
	"Civilian Airdrop",
	"Duffel Bag",
	"Ammo Box",
	"Locked Safe",
	"Specops Supply Crate",
	"Supply Crate",
	"Metal Crate",
	"Military Laptop",
	"Double Metal Crates",
}
local CrateOtherChoices = { "Hidden Stash" }
local StaticCrateTypeSet = {}
for _, Name in CrateTrackChoices do
	if Name ~= "All crates" then
		StaticCrateTypeSet[Name] = "Crates"
	end
end
for _, Name in CrateOtherChoices do
	StaticCrateTypeSet[Name] = "Others"
end
local RequestCrateEspScan
local SilentAimStatus = {
	Text = "inactive",
}

local Runtime = {}

local function TrackConnection(Connection)
	Connections[#Connections + 1] = Connection
	return Connection
end

local function TrackDrawing(DrawingObject)
	Drawings[#Drawings + 1] = DrawingObject
	return DrawingObject
end

local function ClearLock()
	Flags.LockedPlayerName = nil
	SmoothedAimPosition = nil
	SmoothedAimTargetName = nil
end

function Runtime.Unload()
	if not Flags.Running then
		return
	end

	Flags.Running = false
	ClearLock()

	for _, Connection in Connections do
		pcall(function()
			Connection:Disconnect()
		end)
	end

	for _, DrawingObject in Drawings do
		pcall(function()
			DrawingObject:Remove()
		end)
	end

	if Win then
		pcall(function()
			Win:Destroy()
		end)
	end

	if Environment.__MatchaAimRuntime == Runtime then
		Environment.__MatchaAimRuntime = nil
		Environment.SilentAim = nil
		Environment.UnloadDesertStormAim = nil
	end
end

local function Clamp(Value, Minimum, Maximum)
	if Value < Minimum then
		return Minimum
	end
	if Value > Maximum then
		return Maximum
	end
	return Value
end

local CachedPingSeconds = 0
local PingUpdatedAt = -math.huge

local function GetPingSeconds()
	local Now = tick()
	if Now - PingUpdatedAt < 0.5 then
		return CachedPingSeconds
	end
	PingUpdatedAt = Now

	if type(GetPingValue) ~= "function" then
		CachedPingSeconds = 0
		return CachedPingSeconds
	end

	local Success, Ping = pcall(GetPingValue)
	if not Success or type(Ping) ~= "number" then
		CachedPingSeconds = 0
		return CachedPingSeconds
	end

	-- GetPingValue reports round-trip milliseconds. Half of it is the useful
	-- one-way estimate for leading a server-authoritative shot.
	CachedPingSeconds = Clamp(Ping / 2000, 0, 0.35)
	return CachedPingSeconds
end

local function GetLocalRoot()
	local Character = LocalPlayer.Character
	return Character and Character:FindFirstChild("HumanoidRootPart")
end

local function IsTeammate(Player)
	if not Flags.TeamCheck then
		return false
	end

	local Success, Result = pcall(function()
		return Player.Team ~= nil and Player.Team == LocalPlayer.Team
	end)
	return Success and Result
end

local function GetPartPosition(Part)
	local Success, Position = pcall(function()
		return Part and Part.Position
	end)
	if Success then
		return Position
	end
	return nil
end

local function ProjectToScreen(Position)
	if not Position then
		return nil, false
	end

	local Success, ScreenPosition, OnScreen = pcall(WorldToScreen, Position)
	if not Success then
		return nil, false
	end
	return ScreenPosition, OnScreen
end

local function ResolveTargetPart(Character, Head, RootPart, UpperTorso)
	local Mouse = LocalPlayer:GetMouse()
	local MousePosition = Vector2.new(Mouse.X, Mouse.Y)
	local ClosestPart
	local ClosestDistance = math.huge
	local SeenParts = {}

	local function ConsiderPart(Part)
		if not Part or SeenParts[Part] then
			return
		end
		SeenParts[Part] = true

		if not ClosestPart then
			ClosestPart = Part
		end

		local ScreenPosition, OnScreen = ProjectToScreen(GetPartPosition(Part))
		if not OnScreen then
			return
		end

		local DeltaX = ScreenPosition.X - MousePosition.X
		local DeltaY = ScreenPosition.Y - MousePosition.Y
		local Distance = math.sqrt(DeltaX * DeltaX + DeltaY * DeltaY)
		if Distance < ClosestDistance then
			ClosestDistance = Distance
			ClosestPart = Part
		end
	end

	local SelectedParts = Flags.TargetParts
	if type(SelectedParts) ~= "table" or #SelectedParts == 0 then
		SelectedParts = { "Head" }
	end

	for _, PartName in SelectedParts do
		if PartName == "Head" then
			ConsiderPart(Head)
		elseif PartName == "Upper Torso" then
			ConsiderPart(UpperTorso)
		elseif PartName == "Humanoid Root Part" then
			ConsiderPart(RootPart)
		elseif PartName == "Closest" then
			for _, Part in Character:GetChildren() do
				if Part:IsA("BasePart") then
					ConsiderPart(Part)
				end
			end
		end
	end

	return ClosestPart or Head or UpperTorso or RootPart
end

local function BuildTarget(Player)
	if not Player or Player.Name == LocalPlayer.Name or IsTeammate(Player) then
		return nil
	end

	local Character = Player.Character
	if not Character then
		return nil
	end

	local Humanoid = Character:FindFirstChild("Humanoid")
	local Head = Character:FindFirstChild("Head")
	local RootPart = Character:FindFirstChild("HumanoidRootPart")
	local UpperTorso = Character:FindFirstChild("UpperTorso")
	local HealthSuccess, Health = pcall(function()
		return Humanoid and Humanoid.Health
	end)
	if not HealthSuccess or not Health or Health <= 0 or not RootPart or not (Head or UpperTorso) then
		return nil
	end

	local TargetPart = ResolveTargetPart(Character, Head, RootPart, UpperTorso)
	if not TargetPart then
		return nil
	end

	return {
		Player = Player,
		Character = Character,
		Humanoid = Humanoid,
		Head = Head,
		RootPart = RootPart,
		UpperTorso = UpperTorso,
		TargetPart = TargetPart,
	}
end

local function GetLockedTarget()
	if not Flags.LockedPlayerName then
		return nil
	end

	for _, Player in Players:GetPlayers() do
		if Player.Name == Flags.LockedPlayerName then
			return BuildTarget(Player)
		end
	end

	return nil
end

local function FindClosestTarget(Selection)
	Selection = Selection or {}
	local UseFov = Selection.FovCheck
	if UseFov == nil then
		UseFov = Flags.FovCheck
	end
	local FovRadius = Selection.FovRadius or Flags.FovRadius
	local MaxDistance = Selection.MaxDistance or Flags.MaxAcquireDistance
	local Mouse = LocalPlayer:GetMouse()
	local MousePosition = Vector2.new(Mouse.X, Mouse.Y)
	local LocalRoot = GetLocalRoot()
	local ClosestTarget
	local ClosestScreenDistance = math.huge
	local ClosestWorldDistance

	for _, Player in Players:GetPlayers() do
		local Target = BuildTarget(Player)
		if not Target then
			continue
		end

		local TargetPosition = GetPartPosition(Target.TargetPart)
		if not TargetPosition then
			continue
		end

		local LocalPosition = GetPartPosition(LocalRoot)
		local WorldDistance
		if LocalPosition then
			WorldDistance = (LocalPosition - TargetPosition).Magnitude
			if WorldDistance > MaxDistance then
				continue
			end
		end

		local ScreenPosition, OnScreen = ProjectToScreen(TargetPosition)
		if not OnScreen then
			continue
		end

		local DeltaX = ScreenPosition.X - MousePosition.X
		local DeltaY = ScreenPosition.Y - MousePosition.Y
		local ScreenDistance = math.sqrt(DeltaX * DeltaX + DeltaY * DeltaY)
		if UseFov and ScreenDistance > FovRadius then
			continue
		end

		if ScreenDistance < ClosestScreenDistance then
			ClosestScreenDistance = ScreenDistance
			ClosestTarget = Target
			ClosestWorldDistance = WorldDistance
		end
	end

	return ClosestTarget, ClosestScreenDistance, ClosestWorldDistance
end

local function PredictTargetPosition(Target, Origin)
	local TargetPart = Target and Target.TargetPart
	if not TargetPart then
		return nil
	end

	local Position = GetPartPosition(TargetPart)
	if not Position then
		return nil
	end
	if not Flags.AutoPrediction or not Origin then
		return Position
	end

	local ProjectileSpeed = math.max(Flags.ProjectileSpeed, 1)
	local Distance = (Origin - Position).Magnitude
	local TravelTime = Distance / ProjectileSpeed
	local NetworkTime = GetPingSeconds() * Flags.NetworkScale
	local PredictionTime = (TravelTime + NetworkTime) * Flags.PredictionScale
	PredictionTime = Clamp(PredictionTime, 0, Flags.MaxPredictionTime)

	local VelocitySuccess, Velocity = pcall(function()
		return Target.RootPart.AssemblyLinearVelocity
	end)
	if not VelocitySuccess or not Velocity then
		VelocitySuccess, Velocity = pcall(function()
			return TargetPart.Velocity
		end)
	end
	if not VelocitySuccess or not Velocity then
		Velocity = Vector3.new(0, 0, 0)
	end

	local PredictedPosition = Position + Velocity * PredictionTime
	local DropCompensation = 0.5 * Flags.GravityCompensation * PredictionTime * PredictionTime

	return PredictedPosition + Vector3.new(0, DropCompensation, 0)
end

local function UpdateSilentTargetStatus(Target, ScreenDistance, WorldDistance)
	if not Target then
		SilentAimStatus.Text = "no target"
		return
	end

	local HitboxName = "target"
	pcall(function()
		HitboxName = Target.TargetPart.Name
	end)
	SilentAimStatus.Text = HitboxName
		.. " | "
		.. tostring(math.floor((WorldDistance or 0) + 0.5))
		.. "u | "
		.. tostring(math.floor((ScreenDistance or 0) + 0.5))
		.. "px"
end

SilentAim = function(Origin)
	if not Flags.SilentAim then
		return nil
	end

	local Target, ScreenDistance, WorldDistance = FindClosestTarget({
		FovCheck = Flags.SilentFovCheck,
		FovRadius = Flags.SilentFovRadius,
		MaxDistance = Flags.SilentMaxDistance,
	})
	if not Target then
		UpdateSilentTargetStatus(nil)
		return nil
	end

	local ShotOrigin = Origin
	if not ShotOrigin then
		local Camera = Workspace.CurrentCamera
		ShotOrigin = Camera and Camera.Position
	end
	if not ShotOrigin then
		return nil
	end

	UpdateSilentTargetStatus(Target, ScreenDistance, WorldDistance)

	return PredictTargetPosition(Target, ShotOrigin), Target.TargetPart, Target.Player
end

local UiStatusEntriesSupported = false

local function ReplacePlainOnce(Source, Original, Replacement)
	local StartIndex, EndIndex = string.find(Source, Original, 1, true)
	if not StartIndex then
		return Source, false
	end

	return string.sub(Source, 1, StartIndex - 1) .. Replacement .. string.sub(Source, EndIndex + 1), true
end

local function AddUiStatusEntrySupport(Source)
	local OriginalSource = Source
	local Patches = {
		{
			[=[if dU.keybind then local eh=dU.keybind;local hq=eh.listening and"..."or aq(eh.value)]=],
			[=[if dU.keybind then local eh=dU.keybind;local hq=eh.statusOnly and"ON"or eh.listening and"..."or aq(eh.value)]=],
		},
		{
			[=[local jr=D(28,bM(hq,13,aA)+14)j3=j3-jr;local js=iQ and dF(j3,iN+3,jr,20)]=],
			[=[local jr=D(28,bM(hq,13,aA)+14)j3=j3-jr;local js=not eh.statusOnly and iQ and dF(j3,iN+3,jr,20)]=],
		},
		{
			[=[key=eh and eh.value and aq(eh.value)or""]=],
			[=[key=eh and eh.statusOnly and"ON"or eh and eh.value and aq(eh.value)or""]=],
		},
		{
			[=[if eh and eh.value and not eh.listening and not e1(dU)then]=],
			[=[if eh and eh.value and not eh.statusOnly and not eh.listening and not e1(dU)then]=],
		},
	}

	for PatchIndex, Patch in Patches do
		local Applied
		Source, Applied = ReplacePlainOnce(Source, Patch[1], Patch[2])
		if not Applied then
			warn("UI status-entry patch " .. tostring(PatchIndex) .. " is unavailable; using the stock UI.")
			return OriginalSource, false
		end
	end

	return Source, true
end

local function LoadUiLibrary()
	local Success, Result = pcall(function()
		local Source = game:HttpGet("https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/uilib.min.lua")
		assert(type(Source) == "string" and #Source > 0, "empty UI library response")

		Source, UiStatusEntriesSupported = AddUiStatusEntrySupport(Source)
		local Chunk = loadstring(Source)
		assert(type(Chunk) == "function", "UI library compilation failed")

		local LoadedLibrary = Chunk()
		-- A destroyed INS-ui singleton cannot create another window. Executing
		-- the source again replaces its global instance and stops its old loop.
		return LoadedLibrary or INSui
	end)

	if Success and Result then
		return Result
	end

	warn("Failed to load the UI library: " .. tostring(Result))
	return nil
end

local Lib = LoadUiLibrary()
if not Lib then
	warn("No UI library is available; aborting cleanly.")
	return
end

local WindowSuccess, WindowResult = pcall(function()
	return Lib:CreateWindow({
		title = "gamesense",
		subtitle = "DesertStorm extraction",
		size = Vector2.new(610, 450),
		menuKey = "lbracket",
		configFolder = "gamesense-desertstorm",
		configName = "default",
		opacity = 1,
		gameInput = false,
		autoSave = true,
		startOpen = true,
		rounding = 0,
		rowLines = false,
		checkboxStyle = true,
		font = "Proggy",
	})
end)

if not WindowSuccess or not WindowResult then
	warn("Failed to create the UI window: " .. tostring(WindowResult))
	return
end

Win = WindowResult

local GamesenseGreen = Color3.fromRGB(149, 192, 33)
local ThemeSuccess, ThemeError = pcall(function()
	Win:SetTheme({
		bg = Color3.fromRGB(17, 17, 17),
		sidebar = Color3.fromRGB(12, 12, 12),
		white = Color3.fromRGB(235, 235, 235),
		text = Color3.fromRGB(235, 235, 235),
		sub = Color3.fromRGB(145, 145, 145),
		accent = GamesenseGreen,
		accentA = GamesenseGreen,
		accentB = GamesenseGreen,
		surface = Color3.fromRGB(20, 20, 20),
		surface2 = Color3.fromRGB(27, 27, 27),
		surface3 = Color3.fromRGB(38, 38, 38),
		border = Color3.fromRGB(61, 65, 76),
		trackOff = Color3.fromRGB(71, 71, 71),
		trackOn = GamesenseGreen,
		knobOff = Color3.fromRGB(105, 105, 105),
		sliderTrack = Color3.fromRGB(71, 71, 71),
		good = GamesenseGreen,
		bad = Color3.fromRGB(214, 72, 72),
		unsafe = Color3.fromRGB(214, 176, 72),
	})
	Win:SetRounding(0)
	Win:SetCheckboxStyle(true)
	Win:SetRowLines(false)
	Win:SetFont("Proggy")
end)

if not ThemeSuccess then
	warn("Optional UI theming failed: " .. tostring(ThemeError))
end

local AimTab = Win:Tab("AIM", "crosshair")
local AimbotSection = AimTab:Section("aimbot", "Left")
local TargetSection = AimTab:Section("target selection", "Left")
local PredictionSection = AimTab:Section("prediction", "Right")
local SilentSection = AimTab:Section("silent aim", "Right")

AimbotSection:Label("profile: DesertStorm [EXTRACTION]")

local AimbotToggle = AimbotSection:Toggle("enabled", false, function(Value)
	Flags.Aimbot = Value
	if not Value then
		ClearLock()
	end
end)

AimbotToggle:AddKeybind("MouseButton2", "Hold", function(Value)
	Flags.AimbotActive = Value
	if AimbotToggle:Get() ~= Value then
		AimbotToggle:Set(Value)
	end
	if not Value then
		ClearLock()
	end
end)

AimbotSection:Toggle("Roblox team check", false, function(Value)
	Flags.TeamCheck = Value
	if Value then
		ClearLock()
	end
end):Tooltip("Roblox teams only; DesertStorm squad membership may use separate game data.")

AimbotSection:Toggle("sticky aim", true, function(Value)
	Flags.StickyAim = Value
	ClearLock()
end):Tooltip("Keeps the current target after it leaves the FOV. Releasing the aim key still clears it.")

local FovToggle = TargetSection:Toggle("field of view", true, function(Value)
	Flags.FovCheck = Value
end)

FovToggle:AddColorpicker("fov color", Flags.FovColor, function(Color, Alpha)
	Flags.FovColor = Color
	Flags.FovAlpha = Alpha
end)

local FovRadiusSlider = TargetSection:Slider("fov radius", Flags.FovRadius, 1, 10, 400, "px", function(Value)
	Flags.FovRadius = Value
end)

local AcquireRangeSlider = TargetSection:Slider(
	"acquire range",
	Flags.MaxAcquireDistance,
	25,
	100,
	5000,
	"u",
	function(Value)
		Flags.MaxAcquireDistance = Value
	end
):Tooltip("Maximum target acquisition distance in Roblox studs.")

local SmoothnessSlider = TargetSection:Slider(
	"smoothness",
	Flags.AimSmoothness,
	1,
	0,
	100,
	"%",
	function(Value)
		Flags.AimSmoothness = Value
	end
):Tooltip("0% snaps instantly; higher values follow the target more gradually.")

local TargetHitboxDropdown = TargetSection:Dropdown(
	"target hitboxes",
	Flags.TargetParts,
	{ "Head", "Upper Torso", "Humanoid Root Part", "Closest" },
	true,
	function(Value)
		local SelectedParts = {}
		for _, PartName in Value do
			SelectedParts[#SelectedParts + 1] = PartName
		end
		if #SelectedParts == 0 then
			SelectedParts[1] = "Head"
		end
		Flags.TargetParts = SelectedParts
	end
):Tooltip("Enable several hitboxes; the closest enabled point is selected each frame.")

local AimProfiles = {
	Rifles = {
		FovRadius = 120,
		MaxDistance = 1800,
		Hitboxes = { "Head", "Upper Torso" },
		Smoothness = 20,
	},
	Sniper = {
		FovRadius = 70,
		MaxDistance = 3500,
		Hitboxes = { "Head" },
		Smoothness = 35,
	},
	Hybrid = {
		FovRadius = 100,
		MaxDistance = 2500,
		Hitboxes = { "Head", "Upper Torso", "Humanoid Root Part" },
		Smoothness = 25,
	},
}

local UpdatingAimProfile = false
local AimProfileDropdown

local function SetAimProfile(Value)
	if UpdatingAimProfile then
		return
	end

	if type(Value) ~= "table" or #Value == 0 then
		Flags.AimProfile = nil
		return
	end

	-- Multi-select mode gives the dropdown its checkable appearance and permits
	-- clearing it. If another preset is clicked, keep only that newest choice.
	local ProfileName = Value[#Value]
	if #Value > 1 and AimProfileDropdown then
		UpdatingAimProfile = true
		AimProfileDropdown:Set({ ProfileName })
		UpdatingAimProfile = false
	end

	local Profile = AimProfiles[ProfileName]
	if not Profile then
		return
	end

	Flags.AimProfile = ProfileName
	FovRadiusSlider:Set(Profile.FovRadius)
	AcquireRangeSlider:Set(Profile.MaxDistance)
	SmoothnessSlider:Set(Profile.Smoothness)
	TargetHitboxDropdown:Set(Profile.Hitboxes)
	ClearLock()
end

AimProfileDropdown = TargetSection:Dropdown(
	"profiles",
	{ Flags.AimProfile },
	{ "Rifles", "Sniper", "Hybrid" },
	true,
	SetAimProfile
):Tooltip("Select one preset, switch directly to another, or click the active preset again to clear it.")

local AutoPredictionToggle = PredictionSection:Toggle("auto prediction", true, function(Value)
	Flags.AutoPrediction = Value
end)

if UiStatusEntriesSupported then
	AutoPredictionToggle:AddKeybind("on", "Always")
	AutoPredictionToggle.item.keybind.statusOnly = true
end

local ProjectileSpeedSlider = PredictionSection:Slider(
	"projectile speed",
	Flags.ProjectileSpeed,
	25,
	50,
	5000,
	"u/s",
	function(Value)
		Flags.ProjectileSpeed = Value
	end
)

local GravitySlider = PredictionSection:Slider(
	"bullet gravity",
	Flags.GravityCompensation,
	0.1,
	0,
	250,
	"u/s2",
	function(Value)
		Flags.GravityCompensation = Value
	end
)
GravitySlider:Tooltip("Vertical compensation in studs per second squared.")

local PredictionScaleSlider = PredictionSection:Slider(
	"prediction scale",
	Flags.PredictionScale,
	0.05,
	0.1,
	2,
	"x",
	function(Value)
		Flags.PredictionScale = Value
	end
)

local MaxLeadSlider = PredictionSection:Slider(
	"max lead time",
	Flags.MaxPredictionTime,
	0.05,
	0.1,
	1.5,
	"s",
	function(Value)
		Flags.MaxPredictionTime = Value
	end
)

PredictionSection:Slider(
	"network compensation",
	Flags.NetworkScale,
	0.05,
	0,
	2,
	"x",
	function(Value)
		Flags.NetworkScale = Value
	end
):Tooltip("Uses half of measured round-trip ping; lower this if the aim leads too far.")

local PredictionProfiles = {
	["Rifle"] = { Speed = 2500, Gravity = 196.2, Scale = 0.85, MaxLead = 0.65 },
	["SMG / subsonic"] = { Speed = 1800, Gravity = 196.2, Scale = 0.9, MaxLead = 0.75 },
	["DMR / sniper"] = { Speed = 3200, Gravity = 196.2, Scale = 0.8, MaxLead = 0.55 },
	["Fast / hitscan-like"] = { Speed = 5000, Gravity = 0, Scale = 0.55, MaxLead = 0.35 },
}

PredictionSection:Dropdown(
	"weapon profile",
	{ Flags.PredictionProfile },
	{ "Rifle", "SMG / subsonic", "DMR / sniper", "Fast / hitscan-like" },
	false,
	function(Value)
		local ProfileName = Value[1]
		local Profile = PredictionProfiles[ProfileName]
		if not Profile then
			return
		end

		Flags.PredictionProfile = ProfileName
		ProjectileSpeedSlider:Set(Profile.Speed)
		GravitySlider:Set(Profile.Gravity)
		PredictionScaleSlider:Set(Profile.Scale)
		MaxLeadSlider:Set(Profile.MaxLead)
	end
):Tooltip("Baseline presets; DesertStorm does not publish exact per-weapon projectile values.")

local SilentAimToggle = SilentSection:Toggle("silent aim", false, function(Value)
	Flags.SilentAim = Value
	if not Value then
		SilentAimStatus.Text = "inactive"
	end
end):Tooltip("Exports SilentAim(origin); the new game's shot function must call it.")

SilentAimToggle:AddKeybind("V", "Hold", function(Value)
	if SilentAimToggle:Get() ~= Value then
		SilentAimToggle:Set(Value)
	end
end)

SilentSection:Toggle("target fov", true, function(Value)
	Flags.SilentFovCheck = Value
end)

SilentSection:Slider("head proximity", Flags.SilentFovRadius, 1, 5, 400, "px", function(Value)
	Flags.SilentFovRadius = Value
end):Tooltip("Maximum cursor distance from the selected hitbox.")

SilentSection:Slider("max range", Flags.SilentMaxDistance, 25, 100, 5000, "u", function(Value)
	Flags.SilentMaxDistance = Value
end):Tooltip("Maximum world distance for Silent Aim target selection.")

SilentSection:Label(function()
	return "target: " .. SilentAimStatus.Text
end)

local EspTab = Win:Tab("ESP", "eye")
local EspPlayerSection = EspTab:Section("player esp", "Left")
local EspInfoSection = EspTab:Section("information", "Right")
local EspRangeSection = EspTab:Section("filtering", "Right")
local CrateEspSection = EspTab:Section("crate esp", "Left")

EspPlayerSection:Toggle("enabled", false, function(Value)
	Flags.EspEnabled = Value
	EspStatus.LastError = nil
	EspStatus.Text = Value and "starting..." or "off"
end)

EspPlayerSection:Toggle("Roblox team check", false, function(Value)
	Flags.EspTeamCheck = Value
end):Tooltip("Roblox teams only; this may not match DesertStorm squads.")

local BoxToggle = EspPlayerSection:Toggle("bounding box", true, function(Value)
	Flags.EspBox = Value
end)

BoxToggle:AddColorpicker("box color", Flags.EspBoxColor, function(Color, Alpha)
	Flags.EspBoxColor = Color
	Flags.EspBoxAlpha = Alpha
end)

local ChamsToggle = EspPlayerSection:Toggle("2D chams", false, function(Value)
	Flags.EspChams = Value
end)

ChamsToggle:AddColorpicker("chams color", Flags.EspChamsColor, function(Color, Alpha)
	Flags.EspChamsColor = Color
	Flags.EspChamsAlpha = Alpha
end)

ChamsToggle:Tooltip("Through-wall translucent body fill using Matcha's external Drawing renderer.")

EspPlayerSection:Toggle("health bar", true, function(Value)
	Flags.EspHealth = Value
end)

local SnaplineToggle = EspPlayerSection:Toggle("snapline", false, function(Value)
	Flags.EspSnapline = Value
end)

SnaplineToggle:AddColorpicker("snapline color", Flags.EspSnaplineColor, function(Color, Alpha)
	Flags.EspSnaplineColor = Color
	Flags.EspSnaplineAlpha = Alpha
end)

local NameToggle = EspInfoSection:Toggle("name", true, function(Value)
	Flags.EspName = Value
end)

NameToggle:AddColorpicker("text color", Flags.EspTextColor, function(Color, Alpha)
	Flags.EspTextColor = Color
	Flags.EspTextAlpha = Alpha
end)

EspInfoSection:Toggle("weapon", true, function(Value)
	Flags.EspWeapon = Value
end)

EspInfoSection:Toggle("distance", true, function(Value)
	Flags.EspDistance = Value
end)

EspRangeSection:Slider("max distance", Flags.EspMaxDistance, 25, 100, 5000, "u", function(Value)
	Flags.EspMaxDistance = Value
end):Tooltip("Player ESP range in Roblox studs.")

EspRangeSection:Label(function()
	return "status: " .. EspStatus.Text
end)

local CrateEspToggle = CrateEspSection:Toggle("enabled", false, function(Value)
	Flags.CrateEspEnabled = Value
	CrateEspStatus.Text = Value and "scanning..." or "off"
	if Value and RequestCrateEspScan then
		RequestCrateEspScan(false)
	end
end)

CrateEspToggle:AddColorpicker("crate color", Flags.CrateEspColor, function(Color, Alpha)
	Flags.CrateEspColor = Color
	Flags.CrateEspAlpha = Alpha
end)

local CrateTrackDropdown
local UpdatingCrateTrackSelection = false
CrateTrackDropdown = CrateEspSection:Dropdown(
	"track crates",
	Flags.CrateEspTrackedNames,
	CrateTrackChoices,
	true,
	function(Value)
		if UpdatingCrateTrackSelection then
			return
		end

		local SelectedNames = {}
		local NewestName = Value[#Value]
		if NewestName == "All crates" then
			SelectedNames[1] = "All crates"
		else
			for _, Name in Value do
				if Name ~= "All crates" then
					SelectedNames[#SelectedNames + 1] = Name
				end
			end
		end

		if #SelectedNames ~= #Value then
			UpdatingCrateTrackSelection = true
			CrateTrackDropdown:Set(SelectedNames)
			UpdatingCrateTrackSelection = false
		end
		Flags.CrateEspTrackedNames = SelectedNames
	end
):Tooltip("Filters the one-time static loot-crate cache; changing this list never rescans the map.")

CrateEspSection:Dropdown(
	"others",
	Flags.CrateEspTrackedOthers,
	CrateOtherChoices,
	true,
	function(Value)
		local SelectedNames = {}
		for _, Name in Value do
			SelectedNames[#SelectedNames + 1] = Name
		end
		Flags.CrateEspTrackedOthers = SelectedNames
	end
):Tooltip("Other fixed loot locations. T1Stash2/TIStash2 is shown as Hidden Stash.")

local CrateBoxToggle = CrateEspSection:Toggle("bounding box", true, function(Value)
	Flags.CrateEspBox = Value
end)

CrateEspSection:Dropdown(
	"box style",
	{ Flags.CrateEspBoxStyle },
	{ "Corners", "Full" },
	false,
	function(Value)
		Flags.CrateEspBoxStyle = Value[1] or "Corners"
	end
):DependsOn(CrateBoxToggle)

CrateEspSection:Toggle("distance", true, function(Value)
	Flags.CrateEspShowDistance = Value
end)

CrateEspSection:Slider("max distance", Flags.CrateEspMaxDistance, 25, 100, 5000, "u", function(Value)
	Flags.CrateEspMaxDistance = Value
end)

CrateEspSection:Label(function()
	return "status [static loot]: " .. CrateEspStatus.Text
end)

local SettingsTab = Win:AddSettingsTab("cog")
local ScriptSettingsSection = SettingsTab:Section("script", "Right")
ScriptSettingsSection:Button("unload script", function()
	Runtime.Unload()
end):Tooltip("Disconnect every loop, remove every drawing, and close this menu.")

pcall(function()
	local Sections = SettingsTab._tab.sections
	local ScriptSection = ScriptSettingsSection._section
	local ConfigIndex
	local ScriptIndex

	for Index, Section in Sections do
		if Section.name == "Configs" then
			ConfigIndex = Index
		elseif Section == ScriptSection then
			ScriptIndex = Index
		end
	end

	if ConfigIndex and ScriptIndex then
		table.remove(Sections, ScriptIndex)
		if ScriptIndex < ConfigIndex then
			ConfigIndex = ConfigIndex - 1
		end
		table.insert(Sections, ConfigIndex + 1, ScriptSection)
	end
end)

local EspBundles = {}
local EspTargetCache = {}
local EspWeaponCache = {}
local EspErrorReported = false
local EspRendererFailed = false
local EspSkippedProperties = {}

local function GetInstanceIdentity(Instance)
	local Address
	pcall(function()
		Address = Instance and Instance.Address
	end)
	if type(Address) == "number" and Address > 0 then
		return tostring(Address)
	end

	local FullName
	pcall(function()
		FullName = Instance and Instance:GetFullName()
	end)
	if FullName and FullName ~= "" then
		return FullName
	end
	return tostring(Instance)
end

local function GetPlayerIdentity(Player)
	local PlayerName
	pcall(function()
		PlayerName = Player and Player.Name
	end)
	if PlayerName and PlayerName ~= "" then
		return PlayerName
	end
	return GetInstanceIdentity(Player)
end

local function ReportEspError(Prefix, ErrorMessage)
	local FullMessage = Prefix .. ": " .. tostring(ErrorMessage)
	EspStatus.LastError = FullMessage
	EspStatus.Text = "error: " .. string.sub(tostring(ErrorMessage), 1, 38)
	if not EspErrorReported then
		EspErrorReported = true
		warn(FullMessage)
		pcall(function()
			if type(notify) == "function" then
				notify(FullMessage, "gamesense ESP", 8)
			end
		end)
	end
end

local function SetDrawingProperty(DrawingObject, Property, Value)
	if not DrawingObject then
		return false
	end

	local Success = pcall(function()
		DrawingObject[Property] = Value
	end)
	if not Success then
		EspSkippedProperties[Property] = true
	end
	return Success
end

local function CreateDrawingObject(DrawingType)
	local Success, DrawingObject = pcall(function()
		return Drawing.new(DrawingType)
	end)
	if not Success or not DrawingObject then
		return nil
	end
	return TrackDrawing(DrawingObject)
end

local function SetTextDefaults(TextObject, Centered)
	SetDrawingProperty(TextObject, "Color", Flags.EspTextColor)
	SetDrawingProperty(TextObject, "FontSize", 13)
	SetDrawingProperty(TextObject, "Center", Centered)
	SetDrawingProperty(TextObject, "Outline", true)
	SetDrawingProperty(TextObject, "Visible", false)
	SetDrawingProperty(TextObject, "ZIndex", 14)
	local Font
	pcall(function()
		Font = Drawing.Fonts.UI
	end)
	if Font then
		SetDrawingProperty(TextObject, "Font", Font)
	end
end

local function CreateEspBundle()
	local Bundle = {
		BoxOutline = {},
		Box = {},
	}

	for Index = 1, 4 do
		local BoxLine = CreateDrawingObject("Line")
		if BoxLine then
			SetDrawingProperty(BoxLine, "Thickness", 1)
			SetDrawingProperty(BoxLine, "Visible", false)
			SetDrawingProperty(BoxLine, "ZIndex", 11)
			Bundle.Box[#Bundle.Box + 1] = BoxLine
		end
	end

	Bundle.Name = CreateDrawingObject("Text")
	SetTextDefaults(Bundle.Name, true)

	for Index = 1, 4 do
		local OutlineLine = CreateDrawingObject("Line")
		if OutlineLine then
			SetDrawingProperty(OutlineLine, "Thickness", 3)
			SetDrawingProperty(OutlineLine, "Color", Color3.fromRGB(0, 0, 0))
			SetDrawingProperty(OutlineLine, "Visible", false)
			SetDrawingProperty(OutlineLine, "ZIndex", 10)
			Bundle.BoxOutline[#Bundle.BoxOutline + 1] = OutlineLine
		end
	end

	Bundle.Info = CreateDrawingObject("Text")
	Bundle.Flag = CreateDrawingObject("Text")
	SetTextDefaults(Bundle.Info, true)
	SetTextDefaults(Bundle.Flag, false)

	Bundle.HealthBackground = CreateDrawingObject("Square")
	Bundle.HealthBar = CreateDrawingObject("Square")
	SetDrawingProperty(Bundle.HealthBackground, "Filled", true)
	SetDrawingProperty(Bundle.HealthBackground, "Color", Color3.fromRGB(0, 0, 0))
	SetDrawingProperty(Bundle.HealthBackground, "Visible", false)
	SetDrawingProperty(Bundle.HealthBackground, "ZIndex", 10)

	SetDrawingProperty(Bundle.HealthBar, "Filled", true)
	SetDrawingProperty(Bundle.HealthBar, "Visible", false)
	SetDrawingProperty(Bundle.HealthBar, "ZIndex", 11)

	Bundle.Chams = CreateDrawingObject("Square")
	SetDrawingProperty(Bundle.Chams, "Filled", true)
	SetDrawingProperty(Bundle.Chams, "Visible", false)
	SetDrawingProperty(Bundle.Chams, "ZIndex", 5)

	Bundle.SnaplineOutline = CreateDrawingObject("Line")
	Bundle.Snapline = CreateDrawingObject("Line")
	SetDrawingProperty(Bundle.SnaplineOutline, "Thickness", 3)
	SetDrawingProperty(Bundle.SnaplineOutline, "Color", Color3.fromRGB(0, 0, 0))
	SetDrawingProperty(Bundle.SnaplineOutline, "Visible", false)
	SetDrawingProperty(Bundle.SnaplineOutline, "ZIndex", 9)

	SetDrawingProperty(Bundle.Snapline, "Thickness", 1)
	SetDrawingProperty(Bundle.Snapline, "Visible", false)
	SetDrawingProperty(Bundle.Snapline, "ZIndex", 10)

	if #Bundle.Box == 0 and not Bundle.Name and not Bundle.Chams then
		assert(false, "Matcha rejected Line, Text, and Square drawings")
	end

	return Bundle
end

local function HideEspBundle(Bundle)
	if not Bundle then
		return
	end

	if Bundle.Chams then
		Bundle.Chams.Visible = false
	end
	for _, Line in Bundle.BoxOutline do
		Line.Visible = false
	end
	for _, Line in Bundle.Box do
		Line.Visible = false
	end
	if Bundle.HealthBackground then
		Bundle.HealthBackground.Visible = false
	end
	if Bundle.HealthBar then
		Bundle.HealthBar.Visible = false
	end
	if Bundle.Name then
		Bundle.Name.Visible = false
	end
	if Bundle.Info then
		Bundle.Info.Visible = false
	end
	if Bundle.Flag then
		Bundle.Flag.Visible = false
	end
	if Bundle.SnaplineOutline then
		Bundle.SnaplineOutline.Visible = false
	end
	if Bundle.Snapline then
		Bundle.Snapline.Visible = false
	end
end

local function HideAllEspBundles()
	for _, Bundle in EspBundles do
		HideEspBundle(Bundle)
	end
end

local function SetEspBoxLines(Lines, X, Y, Width, Height, Color, Alpha)
	if not Lines or #Lines < 4 then
		return false
	end

	local TopLeft = Vector2.new(X, Y)
	local TopRight = Vector2.new(X + Width, Y)
	local BottomRight = Vector2.new(X + Width, Y + Height)
	local BottomLeft = Vector2.new(X, Y + Height)

	Lines[1].From = TopLeft
	Lines[1].To = TopRight
	Lines[2].From = TopRight
	Lines[2].To = BottomRight
	Lines[3].From = BottomRight
	Lines[3].To = BottomLeft
	Lines[4].From = BottomLeft
	Lines[4].To = TopLeft

	for _, Line in Lines do
		Line.Color = Color
		Line.Transparency = Alpha
		Line.Visible = true
	end
	return true
end

local function GetEspBundle(Player)
	local PlayerIdentity = GetPlayerIdentity(Player)
	local Bundle = EspBundles[PlayerIdentity]
	if not Bundle then
		if EspRendererFailed then
			return nil
		end

		local Success, Result = pcall(CreateEspBundle)
		if not Success then
			EspRendererFailed = true
			ReportEspError("drawing creation failed", Result)
			return nil
		end

		Bundle = Result
		Bundle.PlayerIdentity = PlayerIdentity
		EspBundles[PlayerIdentity] = Bundle
	end
	return Bundle
end

local function IsEspTeammate(Player)
	if not Flags.EspTeamCheck then
		return false
	end

	local Success, Result = pcall(function()
		return Player.Team ~= nil and Player.Team == LocalPlayer.Team
	end)
	return Success and Result
end

local function GetHeldWeaponName(Character)
	local ChildrenSuccess, Children = pcall(function()
		return Character:GetChildren()
	end)
	if not ChildrenSuccess or not Children then
		return nil
	end

	for _, Child in Children do
		local ClassName
		pcall(function()
			ClassName = Child.ClassName
		end)
		if ClassName == "Tool" then
			return Child.Name
		end
	end
	return nil
end

local function GetCachedWeaponName(Character)
	local Now = tick()
	local CharacterIdentity = GetInstanceIdentity(Character)
	local Cached = EspWeaponCache[CharacterIdentity]
	if Cached and Now < Cached.ExpiresAt then
		return Cached.Name
	end

	local WeaponName = GetHeldWeaponName(Character)
	EspWeaponCache[CharacterIdentity] = {
		Name = WeaponName,
		ExpiresAt = Now + 0.25,
	}
	return WeaponName
end

local function SafeFindFirstChild(Parent, Name)
	local Success, Child = pcall(function()
		return Parent and Parent:FindFirstChild(Name)
	end)
	if Success then
		return Child
	end
	return nil
end

local function GetPlayerCharacter(Player)
	local Character
	pcall(function()
		Character = Player.Character
	end)
	if Character then
		return Character
	end

	local PlayerName
	pcall(function()
		PlayerName = Player.Name
	end)
	if PlayerName then
		return SafeFindFirstChild(Workspace, PlayerName)
	end
	return nil
end

local function ResolveEspCharacter(Character)
	local Humanoid = SafeFindFirstChild(Character, "Humanoid")
	local Head = SafeFindFirstChild(Character, "Head")
	local RootPart = SafeFindFirstChild(Character, "HumanoidRootPart")
		or SafeFindFirstChild(Character, "UpperTorso")
		or SafeFindFirstChild(Character, "Torso")
	local FirstPart
	local HighestPart = Head
	local HighestY = -math.huge

	if not Humanoid then
		pcall(function()
			Humanoid = Character:FindFirstChildOfClass("Humanoid")
		end)
	end
	if Head and RootPart then
		return Humanoid, Head, RootPart
	end

	local Descendants
	local DescendantsSuccess = pcall(function()
		Descendants = Character:GetDescendants()
	end)
	if not DescendantsSuccess or not Descendants then
		pcall(function()
			Descendants = Character:GetChildren()
		end)
	end

	for _, Descendant in Descendants or {} do
		local IsBasePart = false
		pcall(function()
			IsBasePart = Descendant:IsA("BasePart")
		end)

		if IsBasePart then
			FirstPart = FirstPart or Descendant
			if Descendant.Name == "Head" then
				Head = Descendant
			elseif Descendant.Name == "HumanoidRootPart" then
				RootPart = Descendant
			elseif not RootPart and (Descendant.Name == "UpperTorso" or Descendant.Name == "Torso") then
				RootPart = Descendant
			end

			local Position = GetPartPosition(Descendant)
			if Position and Position.Y > HighestY then
				HighestY = Position.Y
				HighestPart = Descendant
			end
		elseif not Humanoid then
			pcall(function()
				if Descendant:IsA("Humanoid") then
					Humanoid = Descendant
				end
			end)
		end
	end

	if not RootPart then
		pcall(function()
			RootPart = Character.PrimaryPart
		end)
	end
	RootPart = RootPart or FirstPart
	Head = Head or HighestPart or RootPart

	return Humanoid, Head, RootPart
end

local function GetEspTarget(Player)
	if not Player then
		return nil
	end

	local PlayerIdentity = GetPlayerIdentity(Player)
	if PlayerIdentity == GetPlayerIdentity(LocalPlayer) or IsEspTeammate(Player) then
		return nil
	end

	local Character = GetPlayerCharacter(Player)
	if not Character then
		EspTargetCache[PlayerIdentity] = nil
		return nil
	end

	local Now = tick()
	local CharacterIdentity = GetInstanceIdentity(Character)
	local Cached = EspTargetCache[PlayerIdentity]
	local Humanoid
	local Head
	local RootPart

	if Cached and Cached.CharacterIdentity == CharacterIdentity and Now < Cached.ExpiresAt then
		Humanoid = Cached.Humanoid
		Head = Cached.Head
		RootPart = Cached.RootPart
	else
		Humanoid, Head, RootPart = ResolveEspCharacter(Character)
		local DisplayName = Player.Name
		pcall(function()
			if Player.DisplayName and Player.DisplayName ~= "" then
				DisplayName = Player.DisplayName
			end
		end)
		Cached = {
			Character = Character,
			CharacterIdentity = CharacterIdentity,
			Humanoid = Humanoid,
			Head = Head,
			RootPart = RootPart,
			DisplayName = DisplayName,
			ExpiresAt = Now + 0.75,
		}
		EspTargetCache[PlayerIdentity] = Cached
	end

	if not RootPart or not Head then
		return nil
	end
	if not GetPartPosition(Head) or not GetPartPosition(RootPart) then
		EspTargetCache[PlayerIdentity] = nil
		return nil
	end

	local Health = 100
	local MaxHealth = 100
	if Humanoid then
		local HealthSuccess = pcall(function()
			Health = Humanoid.Health
			MaxHealth = Humanoid.MaxHealth or MaxHealth
		end)
		if HealthSuccess and Health <= 0 then
			return nil
		end
	end

	return {
		Player = Player,
		Character = Character,
		Head = Head,
		RootPart = RootPart,
		Health = Health,
		MaxHealth = math.max(MaxHealth or 100, 1),
		WeaponName = Flags.EspWeapon and GetCachedWeaponName(Character) or nil,
		DisplayName = Cached and Cached.DisplayName or Player.Name,
	}
end

local function GetEspBox(Target)
	local HeadPosition = GetPartPosition(Target.Head)
	local RootPosition = GetPartPosition(Target.RootPart)
	if not HeadPosition or not RootPosition then
		return nil
	end

	local HeadScreen, HeadVisible = ProjectToScreen(HeadPosition)
	local RootScreen, RootVisible = ProjectToScreen(RootPosition)
	if not RootVisible then
		return nil
	end
	if not HeadVisible then
		HeadScreen = RootScreen
	end

	local BodySpan = math.abs(RootScreen.Y - HeadScreen.Y)
	local Height = math.max(BodySpan * 3.15, 18)
	local Width = Height * 0.52
	local CenterX = (HeadScreen.X + RootScreen.X) * 0.5
	local TopY
	if BodySpan >= 2 then
		TopY = math.min(HeadScreen.Y, RootScreen.Y) - BodySpan * 0.55
	else
		TopY = RootScreen.Y - Height * 0.55
	end

	return CenterX - Width * 0.5, TopY, Width, Height
end

local function UpdateEspBundle(Bundle, Target, Camera, Origin)
	local TargetPosition = GetPartPosition(Target.RootPart)
	if not TargetPosition then
		return false
	end

	if not Origin then
		return false
	end

	local Distance = (Origin - TargetPosition).Magnitude
	if Distance > Flags.EspMaxDistance then
		return false
	end

	local X, Y, Width, Height = GetEspBox(Target)
	if not X then
		return false
	end

	if Flags.EspChams and Bundle.Chams then
		Bundle.Chams.Position = Vector2.new(X + 2, Y + 2)
		Bundle.Chams.Size = Vector2.new(math.max(Width - 4, 1), math.max(Height - 4, 1))
		Bundle.Chams.Color = Flags.EspChamsColor
		Bundle.Chams.Transparency = Flags.EspChamsAlpha
		Bundle.Chams.Visible = true
	elseif Bundle.Chams then
		Bundle.Chams.Visible = false
	end

	if Flags.EspBox then
		SetEspBoxLines(
			Bundle.BoxOutline,
			X,
			Y,
			Width,
			Height,
			Color3.fromRGB(0, 0, 0),
			Flags.EspBoxAlpha
		)
		SetEspBoxLines(Bundle.Box, X, Y, Width, Height, Flags.EspBoxColor, Flags.EspBoxAlpha)
	else
		for _, Line in Bundle.BoxOutline do
			Line.Visible = false
		end
		for _, Line in Bundle.Box do
			Line.Visible = false
		end
	end

	if Flags.EspHealth and Bundle.HealthBackground and Bundle.HealthBar then
		local HealthRatio = Clamp(Target.Health / Target.MaxHealth, 0, 1)
		local BarHeight = math.max(math.floor((Height - 2) * HealthRatio), 1)
		Bundle.HealthBackground.Position = Vector2.new(X - 6, Y - 1)
		Bundle.HealthBackground.Size = Vector2.new(4, Height + 2)
		Bundle.HealthBackground.Transparency = 0.9
		Bundle.HealthBackground.Visible = true

		Bundle.HealthBar.Position = Vector2.new(X - 5, Y + Height - 1 - BarHeight)
		Bundle.HealthBar.Size = Vector2.new(2, BarHeight)
		Bundle.HealthBar.Color = Color3.new(1 - HealthRatio, HealthRatio, 0)
		Bundle.HealthBar.Transparency = 1
		Bundle.HealthBar.Visible = true
	else
		if Bundle.HealthBackground then
			Bundle.HealthBackground.Visible = false
		end
		if Bundle.HealthBar then
			Bundle.HealthBar.Visible = false
		end
	end

	if Flags.EspName and Bundle.Name then
		Bundle.Name.Text = Target.DisplayName
		Bundle.Name.Position = Vector2.new(X + Width * 0.5, Y - 15)
		Bundle.Name.Color = Flags.EspTextColor
		Bundle.Name.Transparency = Flags.EspTextAlpha
		Bundle.Name.Visible = true
	elseif Bundle.Name then
		Bundle.Name.Visible = false
	end

	local InfoParts = {}
	if Flags.EspDistance then
		InfoParts[#InfoParts + 1] = "[" .. tostring(math.floor(Distance + 0.5)) .. "u]"
	end
	if Flags.EspWeapon then
		local WeaponName = Target.WeaponName
		if WeaponName then
			InfoParts[#InfoParts + 1] = WeaponName
		end
	end
	if #InfoParts > 0 and Bundle.Info then
		Bundle.Info.Text = table.concat(InfoParts, "  ")
		Bundle.Info.Position = Vector2.new(X + Width * 0.5, Y + Height + 2)
		Bundle.Info.Color = Flags.EspTextColor
		Bundle.Info.Transparency = Flags.EspTextAlpha
		Bundle.Info.Visible = true
	elseif Bundle.Info then
		Bundle.Info.Visible = false
	end

	if Bundle.Flag and Flags.LockedPlayerName == Target.Player.Name then
		Bundle.Flag.Text = "TARGET"
		Bundle.Flag.Position = Vector2.new(X + Width + 4, Y)
		Bundle.Flag.Color = Color3.fromRGB(149, 192, 33)
		Bundle.Flag.Transparency = 1
		Bundle.Flag.Visible = true
	elseif Bundle.Flag then
		Bundle.Flag.Visible = false
	end

	if Flags.EspSnapline and Bundle.SnaplineOutline and Bundle.Snapline then
		local ViewportSize
		pcall(function()
			ViewportSize = Camera.ViewportSize
		end)
		if ViewportSize then
			local From = Vector2.new(ViewportSize.X * 0.5, ViewportSize.Y)
			local To = Vector2.new(X + Width * 0.5, Y + Height)
			Bundle.SnaplineOutline.From = From
			Bundle.SnaplineOutline.To = To
			Bundle.SnaplineOutline.Transparency = Flags.EspSnaplineAlpha
			Bundle.SnaplineOutline.Visible = true

			Bundle.Snapline.From = From
			Bundle.Snapline.To = To
			Bundle.Snapline.Color = Flags.EspSnaplineColor
			Bundle.Snapline.Transparency = Flags.EspSnaplineAlpha
			Bundle.Snapline.Visible = true
		else
			Bundle.SnaplineOutline.Visible = false
			Bundle.Snapline.Visible = false
		end
	else
		if Bundle.SnaplineOutline then
			Bundle.SnaplineOutline.Visible = false
		end
		if Bundle.Snapline then
			Bundle.Snapline.Visible = false
		end
	end

	Bundle.LastDrawnAt = tick()
	return true
end

local function UpdateEspFrame()
	if not Flags.Running or not Flags.EspEnabled then
		HideAllEspBundles()
		EspStatus.Text = "off"
		return
	end
	if EspRendererFailed then
		HideAllEspBundles()
		if not EspStatus.LastError then
			EspStatus.Text = "renderer unavailable"
		end
		return
	end

	local Camera = Workspace.CurrentCamera
	if not Camera then
		HideAllEspBundles()
		EspStatus.Text = "waiting for camera"
		return
	end

	local Origin = GetPartPosition(GetLocalRoot())
	if not Origin then
		pcall(function()
			Origin = Camera.Position
		end)
	end
	if not Origin then
		HideAllEspBundles()
		EspStatus.Text = "waiting for position"
		return
	end

	local PlayerCount = 0
	local ValidCount = 0
	local DrawnCount = 0
	local ActiveBundles = {}
	local LocalPlayerIdentity = GetPlayerIdentity(LocalPlayer)
	for _, Player in Players:GetPlayers() do
		if GetPlayerIdentity(Player) ~= LocalPlayerIdentity then
			PlayerCount = PlayerCount + 1
		end

		local Bundle
		local Success, WasDrawn = pcall(function()
			local Target = GetEspTarget(Player)
			if Target then
				ValidCount = ValidCount + 1
				Bundle = GetEspBundle(Player)
				if Bundle then
					return UpdateEspBundle(Bundle, Target, Camera, Origin)
				end
			end
			return false
		end)
		if not Success and not EspErrorReported then
			ReportEspError("player update failed", WasDrawn)
		elseif Success and WasDrawn then
			DrawnCount = DrawnCount + 1
			ActiveBundles[Bundle] = true
		end
	end

	local Now = tick()
	for _, Bundle in EspBundles do
		if
			not ActiveBundles[Bundle]
			and (not Bundle.LastDrawnAt or Now - Bundle.LastDrawnAt > 0.08)
		then
			HideEspBundle(Bundle)
		end
	end

	if not EspStatus.LastError then
		EspStatus.Text = tostring(DrawnCount)
			.. "/"
			.. tostring(ValidCount)
			.. " drawn | "
			.. tostring(PlayerCount)
			.. " players"
		if next(EspSkippedProperties) then
			EspStatus.Text = EspStatus.Text .. " | compat"
		end
	end
end

local CrateEspBundles = {}
local CrateEspTargets = {}
local CrateEspRendererFailed = false
local CrateEspErrorReported = false
local CrateEspScanRunning = false
local CrateEspScanRequested = false
local CrateEspScanComplete = false
local CRATE_SCAN_YIELD_EVERY = 250
local CRATE_TARGET_LIMIT = 512

local CrateNameTokens = {
	"crate",
	"stash",
	"container",
	"lootbox",
	"lootcrate",
	"lootable",
	"supplybox",
	"supplydrop",
	"weaponcase",
	"ammocase",
	"medicalcase",
	"medcase",
	"lootcase",
	"itemcase",
	"cache",
	"chest",
	"airdrop",
	"duffelbag",
	"dufflebag",
	"ammobox",
	"lockedsafe",
	"militarylaptop",
}

local ExplicitLootNameTokens = {
	"lootbox",
	"lootcrate",
	"lootable",
	"stash",
	"supplydrop",
	"weaponcase",
	"ammocase",
	"medicalcase",
	"medcase",
	"lootcase",
	"itemcase",
	"cache",
	"airdrop",
	"duffelbag",
	"dufflebag",
	"ammobox",
	"lockedsafe",
	"militarylaptop",
}

local LootInteractionTokens = {
	"interact",
	"proximityprompt",
	"clickdetector",
	"loot",
	"inventory",
	"contents",
	"search",
	"openprompt",
	"containerdata",
	"storage",
}

local LootPromptTokens = {
	"open",
	"loot",
	"search",
	"container",
	"crate",
	"stash",
	"cache",
}

local function IsInstanceA(Instance, ClassName)
	local Result = false
	pcall(function()
		Result = Instance and Instance:IsA(ClassName)
	end)
	return Result
end

local function GetInstanceName(Instance)
	local Name
	pcall(function()
		Name = Instance and Instance.Name
	end)
	return type(Name) == "string" and Name or nil
end

local function GetInstanceParent(Instance)
	local Parent
	pcall(function()
		Parent = Instance and Instance.Parent
	end)
	return Parent
end

local function IsCrateName(Name)
	if type(Name) ~= "string" or Name == "" then
		return false
	end

	local CompactName = string.lower(Name):gsub("[%s_%-%.]", "")
	if string.find(CompactName, "template", 1, true) or string.find(CompactName, "spawner", 1, true) then
		return false
	end

	for _, Token in CrateNameTokens do
		if string.find(CompactName, Token, 1, true) then
			return true
		end
	end
	return false
end

local function CompactCrateText(Text)
	return string.lower(tostring(Text or "")):gsub("[%s_%-%.]", "")
end

local function ContainsAnyToken(Text, Tokens)
	local CompactText = CompactCrateText(Text)
	for _, Token in Tokens do
		if string.find(CompactText, Token, 1, true) then
			return true
		end
	end
	return false
end

local function IsExplicitLootName(Name)
	return ContainsAnyToken(Name, ExplicitLootNameTokens)
end

local function HasLootAttributes(Instance)
	local Attributes
	local Success = pcall(function()
		Attributes = Instance:GetAttributes()
	end)
	if not Success or type(Attributes) ~= "table" then
		return false
	end

	for Name in Attributes do
		if ContainsAnyToken(Name, LootInteractionTokens) then
			return true
		end
	end
	return false
end

local function IsLootInteractionMarker(Instance)
	if IsInstanceA(Instance, "ProximityPrompt") or IsInstanceA(Instance, "ClickDetector") then
		return true
	end
	if ContainsAnyToken(GetInstanceName(Instance), LootInteractionTokens) then
		return true
	end
	return HasLootAttributes(Instance)
end

local function GetLootPromptLabel(Instance)
	if not IsInstanceA(Instance, "ProximityPrompt") then
		return nil
	end

	local ActionText
	local ObjectText
	pcall(function()
		ActionText = Instance.ActionText
		ObjectText = Instance.ObjectText
	end)
	if
		not ContainsAnyToken(ActionText, LootPromptTokens)
		and not ContainsAnyToken(ObjectText, CrateNameTokens)
	then
		return nil
	end
	if type(ObjectText) == "string" and ObjectText ~= "" then
		return ObjectText
	end
	return "Loot Container"
end

local function HasDirectLootSignal(Instance)
	if not Instance then
		return false
	end
	if IsLootInteractionMarker(Instance) then
		return true
	end

	local Children
	pcall(function()
		Children = Instance:GetChildren()
	end)
	for _, Child in Children or {} do
		if IsLootInteractionMarker(Child) then
			return true
		end
	end
	return false
end

local function HasNestedLootSignal(Instance)
	if HasDirectLootSignal(Instance) then
		return true
	end

	local Descendants
	pcall(function()
		Descendants = Instance:GetDescendants()
	end)
	for Index, Descendant in Descendants or {} do
		if Index > 160 then
			break
		end
		if IsLootInteractionMarker(Descendant) then
			return true
		end
	end
	return false
end

local function FindLootableCrateRoot(Candidate, TrustedTag)
	if not Candidate then
		return nil
	end

	if IsExplicitLootName(GetInstanceName(Candidate)) or HasNestedLootSignal(Candidate) then
		return Candidate
	end

	local Current = GetInstanceParent(Candidate)
	for _ = 1, 5 do
		if not Current or Current == Workspace then
			break
		end
		if HasDirectLootSignal(Current) then
			if IsInstanceA(Current, "Model") or IsInstanceA(Current, "BasePart") then
				return Current
			end
			return Candidate
		end
		if IsExplicitLootName(GetInstanceName(Current)) then
			if IsInstanceA(Current, "Model") or IsInstanceA(Current, "BasePart") then
				return Current
			end
			return Candidate
		end
		Current = GetInstanceParent(Current)
	end

	return TrustedTag and Candidate or nil
end

local function CleanCrateName(Name)
	Name = tostring(Name or "Crate")
	Name = Name:gsub("[_%-]+", " "):gsub("%s+", " ")
	local LowerName = string.lower(Name)
	local AssetSuffix = string.find(LowerName, " palette", 1, true)
		or string.find(LowerName, " lod", 1, true)
	if AssetSuffix then
		Name = string.sub(Name, 1, AssetSuffix - 1)
	end
	Name = Name:gsub("%.0%d+$", "")
	Name = Name:gsub("(%l)(%u)", "%1 %2")
	Name = Name:gsub("(%d)(%u)", "%1 %2")
	Name = Name:gsub("(%a)(%d)", "%1 %2")
	Name = Name:gsub("%s+", " "):gsub("%s+$", "")
	local CompactName = CompactCrateText(Name)
	if
		string.find(CompactName, "t1stash2", 1, true)
		or string.find(CompactName, "tistash2", 1, true)
	then
		return "Hidden Stash"
	end
	if string.find(CompactName, "civilianairdrop", 1, true) then
		return "Civilian Airdrop"
	end
	if
		string.find(CompactName, "duffelbag", 1, true)
		or string.find(CompactName, "dufflebag", 1, true)
	then
		return "Duffel Bag"
	end
	if
		string.find(CompactName, "ammocratelarge", 1, true)
		or string.find(CompactName, "ammobox", 1, true)
	then
		return "Ammo Box"
	end
	if string.find(CompactName, "lockedsafe", 1, true) then
		return "Locked Safe"
	end
	if string.find(CompactName, "specopssupplycrate", 1, true) then
		return "Specops Supply Crate"
	end
	if string.find(CompactName, "doublemetalcrate", 1, true) then
		return "Double Metal Crates"
	end
	if string.find(CompactName, "militarylaptop", 1, true) then
		return "Military Laptop"
	end
	if string.find(CompactName, "woodencrate", 1, true) then
		return "Wooden Crate"
	end
	if string.find(CompactName, "supplycrate", 1, true) then
		return "Supply Crate"
	end
	if string.find(CompactName, "metalcrate", 1, true) then
		return "Metal Crate"
	end
	if string.lower(Name) == "crates" then
		return "Crate"
	end
	if string.lower(Name) == "containers" then
		return "Container"
	end
	return Name
end

local function HasHumanoidAncestor(Instance)
	local Current = Instance
	for _ = 1, 6 do
		if not Current then
			break
		end
		if SafeFindFirstChild(Current, "Humanoid") then
			return true
		end
		Current = GetInstanceParent(Current)
	end
	return false
end

local function ResolveCrateCandidate(Instance)
	if not Instance then
		return nil
	end

	local Candidate = Instance
	if not IsInstanceA(Candidate, "Model") and not IsInstanceA(Candidate, "BasePart") then
		for _ = 1, 6 do
			Candidate = GetInstanceParent(Candidate)
			if not Candidate then
				return nil
			end
			if IsInstanceA(Candidate, "Model") or IsInstanceA(Candidate, "BasePart") then
				break
			end
		end
	end

	if IsInstanceA(Candidate, "BasePart") then
		local Parent = GetInstanceParent(Candidate)
		if Parent and IsInstanceA(Parent, "Model") then
			Candidate = Parent
		end
	end

	local CandidateName = GetInstanceName(Candidate)
	local LowerCandidateName = string.lower(CandidateName or "")
	if
		string.find(LowerCandidateName, "lod", 1, true)
		or string.find(LowerCandidateName, "palette", 1, true)
		or string.find(LowerCandidateName, ".00", 1, true)
	then
		local Parent = GetInstanceParent(Candidate)
		if Parent and IsInstanceA(Parent, "Model") and IsCrateName(GetInstanceName(Parent)) then
			Candidate = Parent
		end
	end

	if HasHumanoidAncestor(Candidate) then
		return nil
	end
	return Candidate
end

local function FindCratePart(Instance)
	if not Instance then
		return nil
	end
	if IsInstanceA(Instance, "BasePart") then
		return Instance
	end

	local Part
	pcall(function()
		Part = Instance.PrimaryPart
	end)
	if Part then
		return Part
	end

	for _, PartName in { "Main", "Root", "Handle", "Primary", "Base" } do
		Part = SafeFindFirstChild(Instance, PartName)
		if Part and IsInstanceA(Part, "BasePart") then
			return Part
		end
	end

	pcall(function()
		Part = Instance:FindFirstChildWhichIsA("BasePart", true)
	end)
	if Part then
		return Part
	end

	local Descendants
	pcall(function()
		Descendants = Instance:GetDescendants()
	end)
	for _, Descendant in Descendants or {} do
		if IsInstanceA(Descendant, "BasePart") then
			return Descendant
		end
	end
	return nil
end

local function RefreshCrateTargets()
	local FoundTargets = {}
	local FoundCount = 0
	local SeenCandidateIdentities = {}
	local CandidateChecks = 0

	local function AddCandidate(Instance, LabelHint, TrustedTag, PreferLabelHint)
		if FoundCount >= CRATE_TARGET_LIMIT then
			return
		end
		CandidateChecks = CandidateChecks + 1
		if CandidateChecks % 50 == 0 then
			task.wait()
		end

		local Candidate = ResolveCrateCandidate(Instance)
		local LootableRoot = FindLootableCrateRoot(Candidate, TrustedTag)
		if not Candidate or not LootableRoot then
			return
		end

		local Identity = GetInstanceIdentity(LootableRoot)
		local CandidateName = GetInstanceName(Candidate)
		local DisplaySource = PreferLabelHint and LabelHint
			or (IsCrateName(CandidateName) and CandidateName or LabelHint)
		local DisplayName = CleanCrateName(DisplaySource)
		local Category = StaticCrateTypeSet[DisplayName]
		if not Category then
			return
		end

		local SeenTarget = SeenCandidateIdentities[Identity]
		if SeenTarget then
			if PreferLabelHint then
				SeenTarget.DisplayName = DisplayName
				SeenTarget.Category = Category
			end
			return
		end

		local Part = FindCratePart(LootableRoot) or FindCratePart(Candidate)
		if not Part then
			return
		end

		local CandidatePosition = GetPartPosition(Part)
		if not CandidatePosition then
			return
		end
		for _, ExistingTarget in FoundTargets do
			local ExistingPosition = ExistingTarget.AnchorPosition
			if
				ExistingTarget.DisplayName == DisplayName
				and ExistingTarget.Category == Category
				and ExistingPosition
				and (ExistingPosition - CandidatePosition).Magnitude <= 4
			then
				local MemberCount = ExistingTarget.MemberCount or 1
				ExistingTarget.AnchorPosition = (
					ExistingPosition * MemberCount + CandidatePosition
				) / (MemberCount + 1)
				ExistingTarget.MemberCount = MemberCount + 1
				SeenCandidateIdentities[Identity] = ExistingTarget
				return
			end
		end

		local Target = {
			Instance = LootableRoot,
			SourceInstance = Candidate,
			Part = Part,
			DisplayName = DisplayName,
			Category = Category,
			AnchorPosition = CandidatePosition,
			MemberCount = 1,
		}
		FoundTargets[Identity] = Target
		SeenCandidateIdentities[Identity] = Target
		FoundCount = FoundCount + 1
	end

	local Descendants
	local DescendantsSuccess = pcall(function()
		Descendants = Workspace:GetDescendants()
	end)
	if DescendantsSuccess then
		for Index, Descendant in Descendants or {} do
			if not Flags.Running or FoundCount >= CRATE_TARGET_LIMIT then
				break
			end

			local PromptLabel = GetLootPromptLabel(Descendant)
			local Name = GetInstanceName(Descendant)
			if PromptLabel then
				AddCandidate(GetInstanceParent(Descendant), PromptLabel, true, true)
			elseif IsCrateName(Name) then
				if IsInstanceA(Descendant, "Folder") then
					local Children
					pcall(function()
						Children = Descendant:GetChildren()
					end)
					for _, Child in Children or {} do
						AddCandidate(Child, Name, false, false)
					end
				else
					AddCandidate(Descendant, Name, false, false)
				end
			end

			if Index % CRATE_SCAN_YIELD_EVERY == 0 then
				task.wait()
			end
		end
	end

	local CollectionService
	pcall(function()
		CollectionService = game:GetService("CollectionService")
	end)
	if CollectionService and FoundCount < CRATE_TARGET_LIMIT then
		local Tags
		pcall(function()
			Tags = CollectionService:GetTags()
		end)
		for _, Tag in Tags or {} do
			if IsCrateName(Tag) then
				local Tagged
				pcall(function()
					Tagged = CollectionService:GetTagged(Tag)
				end)
				for _, Instance in Tagged or {} do
					local TrustedTag = IsExplicitLootName(Tag)
						or ContainsAnyToken(Tag, LootInteractionTokens)
					AddCandidate(Instance, Tag, TrustedTag, false)
				end
			end
		end
	end

	if not Flags.Running then
		return
	end
	for Identity, Target in CrateEspTargets do
		if not FoundTargets[Identity] then
			FoundTargets[Identity] = Target
		end
	end
	CrateEspTargets = FoundTargets
end

RequestCrateEspScan = function(Force)
	if not Flags.Running then
		return
	end
	if CrateEspScanComplete and not Force then
		return
	end
	CrateEspScanRequested = true
end

local function StartCrateEspScan()
	if CrateEspScanRunning or not Flags.Running or not Flags.CrateEspEnabled then
		return
	end

	CrateEspScanRunning = true
	CrateEspScanRequested = false
	CrateEspStatus.Text = "scanning loot..."
	task.spawn(function()
		local ScanSuccess, ScanError = pcall(RefreshCrateTargets)
		CrateEspScanRunning = false
		if not Flags.Running then
			return
		end
		if not ScanSuccess then
			CrateEspStatus.Text = "scan unavailable"
			if not CrateEspErrorReported then
				CrateEspErrorReported = true
				warn("crate ESP scan failed: " .. tostring(ScanError))
			end
		else
			CrateEspErrorReported = false
			CrateEspScanComplete = true
		end
	end)
end

local function CacheStaticCrateInstance(Instance, LabelHint, Trusted, PreferLabelHint)
	local Candidate = ResolveCrateCandidate(Instance)
	local LootableRoot = FindLootableCrateRoot(Candidate, Trusted)
	if not Candidate or not LootableRoot then
		return
	end

	local CandidateName = GetInstanceName(Candidate)
	local DisplaySource = PreferLabelHint and LabelHint
		or (IsCrateName(CandidateName) and CandidateName or LabelHint)
	local DisplayName = CleanCrateName(DisplaySource)
	local Category = StaticCrateTypeSet[DisplayName]
	if not Category then
		return
	end

	local Part = FindCratePart(LootableRoot) or FindCratePart(Candidate)
	local Position = GetPartPosition(Part)
	if not Part or not Position then
		return
	end

	local Identity = GetInstanceIdentity(LootableRoot)
	local ExistingTarget = CrateEspTargets[Identity]
	if ExistingTarget then
		if PreferLabelHint then
			ExistingTarget.DisplayName = DisplayName
			ExistingTarget.Category = Category
		end
		return
	end

	CrateEspTargets[Identity] = {
		Instance = LootableRoot,
		SourceInstance = Candidate,
		Part = Part,
		DisplayName = DisplayName,
		Category = Category,
		AnchorPosition = Position,
		MemberCount = 1,
	}
end

-- DesertStorm streams map regions. Cache a prompted container once when it
-- becomes visible to the client; its saved world position remains static.
pcall(function()
	local ProximityPromptService = game:GetService("ProximityPromptService")
	TrackConnection(ProximityPromptService.PromptShown:Connect(function(Prompt)
		if not Flags.Running or not Flags.CrateEspEnabled then
			return
		end
		local Label = GetLootPromptLabel(Prompt)
		if Label then
			pcall(CacheStaticCrateInstance, GetInstanceParent(Prompt), Label, true, true)
		end
	end))
end)

-- Hidden stashes do not always expose an on-screen prompt. This guarded hook
-- only recognizes their exact internal model alias and never rescans Workspace.
pcall(function()
	TrackConnection(Workspace.DescendantAdded:Connect(function(Instance)
		if not Flags.Running or not Flags.CrateEspEnabled then
			return
		end
		local CompactName = CompactCrateText(GetInstanceName(Instance))
		if
			not string.find(CompactName, "t1stash2", 1, true)
			and not string.find(CompactName, "tistash2", 1, true)
		then
			return
		end
		task.defer(function()
			pcall(CacheStaticCrateInstance, Instance, "Hidden Stash", true, true)
		end)
	end))
end)

local function CreateCrateEspBundle()
	local Bundle = {
		Label = CreateDrawingObject("Text"),
		Box = {},
		BoxOutline = {},
	}

	for _ = 1, 8 do
		local OutlineLine = CreateDrawingObject("Line")
		if OutlineLine then
			SetDrawingProperty(OutlineLine, "Thickness", 3)
			SetDrawingProperty(OutlineLine, "Color", Color3.fromRGB(0, 0, 0))
			SetDrawingProperty(OutlineLine, "Visible", false)
			SetDrawingProperty(OutlineLine, "ZIndex", 13)
			Bundle.BoxOutline[#Bundle.BoxOutline + 1] = OutlineLine
		end

		local BoxLine = CreateDrawingObject("Line")
		if BoxLine then
			SetDrawingProperty(BoxLine, "Thickness", 1)
			SetDrawingProperty(BoxLine, "Visible", false)
			SetDrawingProperty(BoxLine, "ZIndex", 14)
			Bundle.Box[#Bundle.Box + 1] = BoxLine
		end
	end

	if not Bundle.Label then
		assert(false, "Matcha rejected crate Text drawings")
	end

	SetTextDefaults(Bundle.Label, true)
	SetDrawingProperty(Bundle.Label, "FontSize", 13)
	SetDrawingProperty(Bundle.Label, "ZIndex", 15)
	return Bundle
end

local function HideCrateEspBundle(Bundle)
	if not Bundle then
		return
	end
	if Bundle.Label then
		Bundle.Label.Visible = false
	end
	for _, Line in Bundle.BoxOutline do
		Line.Visible = false
	end
	for _, Line in Bundle.Box do
		Line.Visible = false
	end
end

local function HideAllCrateEspBundles()
	for _, Bundle in CrateEspBundles do
		HideCrateEspBundle(Bundle)
	end
end

local function GetCrateEspBundle(Identity)
	local Bundle = CrateEspBundles[Identity]
	if Bundle then
		return Bundle
	end
	if CrateEspRendererFailed then
		return nil
	end

	local Success, Result = pcall(CreateCrateEspBundle)
	if not Success then
		CrateEspRendererFailed = true
		CrateEspStatus.Text = "renderer unavailable"
		if not CrateEspErrorReported then
			CrateEspErrorReported = true
			warn("crate ESP drawing creation failed: " .. tostring(Result))
		end
		return nil
	end

	CrateEspBundles[Identity] = Result
	return Result
end

local function ShouldTrackCrate(Target)
	local IsOther = Target.Category == "Others"
	local SelectedNames = IsOther and Flags.CrateEspTrackedOthers or Flags.CrateEspTrackedNames
	if type(SelectedNames) ~= "table" or #SelectedNames == 0 then
		return false
	end

	for _, SelectedName in SelectedNames do
		if (not IsOther and SelectedName == "All crates") or SelectedName == Target.DisplayName then
			return true
		end
	end
	return false
end

local function GetCrateScreenBox(Target, Distance, AnchorScreen)
	if not AnchorScreen then
		local AnchorPosition = Target.AnchorPosition
		if not AnchorPosition then
			return nil
		end
		local OnScreen
		AnchorScreen, OnScreen = ProjectToScreen(AnchorPosition + Vector3.new(0, 1.25, 0))
		if not AnchorScreen or not OnScreen then
			return nil
		end
	end

	local Height = Clamp(1100 / math.max(Distance, 1), 12, 70)
	local Width = Height * 1.25
	return AnchorScreen.X - Width * 0.5, AnchorScreen.Y - Height * 0.5, Width, Height
end

local function BuildFullBoxSegments(X, Y, Width, Height)
	return {
		{ Vector2.new(X, Y), Vector2.new(X + Width, Y) },
		{ Vector2.new(X + Width, Y), Vector2.new(X + Width, Y + Height) },
		{ Vector2.new(X + Width, Y + Height), Vector2.new(X, Y + Height) },
		{ Vector2.new(X, Y + Height), Vector2.new(X, Y) },
	}
end

local function BuildCornerBoxSegments(X, Y, Width, Height)
	local CornerLength = math.max(math.min(Width, Height) * 0.28, 4)
	CornerLength = math.min(CornerLength, Width * 0.5, Height * 0.5)
	return {
		{ Vector2.new(X, Y), Vector2.new(X + CornerLength, Y) },
		{ Vector2.new(X, Y), Vector2.new(X, Y + CornerLength) },
		{ Vector2.new(X + Width - CornerLength, Y), Vector2.new(X + Width, Y) },
		{ Vector2.new(X + Width, Y), Vector2.new(X + Width, Y + CornerLength) },
		{ Vector2.new(X, Y + Height), Vector2.new(X + CornerLength, Y + Height) },
		{ Vector2.new(X, Y + Height - CornerLength), Vector2.new(X, Y + Height) },
		{ Vector2.new(X + Width - CornerLength, Y + Height), Vector2.new(X + Width, Y + Height) },
		{ Vector2.new(X + Width, Y + Height - CornerLength), Vector2.new(X + Width, Y + Height) },
	}
end

local function SetCrateBoxSegments(Lines, Segments, Color, Alpha)
	for Index, Line in Lines do
		local Segment = Segments[Index]
		if Segment then
			Line.From = Segment[1]
			Line.To = Segment[2]
			Line.Color = Color
			Line.Transparency = Alpha
			Line.Visible = true
		else
			Line.Visible = false
		end
	end
end

local function UpdateCrateEspFrame()
	if not Flags.Running or not Flags.CrateEspEnabled then
		HideAllCrateEspBundles()
		CrateEspStatus.Text = "off"
		return
	end
	if CrateEspRendererFailed then
		HideAllCrateEspBundles()
		CrateEspStatus.Text = "renderer unavailable"
		return
	end

	if CrateEspScanRequested and not CrateEspScanRunning then
		StartCrateEspScan()
	end

	local Camera = Workspace.CurrentCamera
	if not Camera then
		HideAllCrateEspBundles()
		CrateEspStatus.Text = "waiting for camera"
		return
	end

	local Origin = GetPartPosition(GetLocalRoot())
	if not Origin then
		pcall(function()
			Origin = Camera.Position
		end)
	end
	if not Origin then
		HideAllCrateEspBundles()
		CrateEspStatus.Text = "waiting for position"
		return
	end

	local FoundCount = 0
	local DrawnCount = 0
	local ActiveBundles = {}
	for Identity, Target in CrateEspTargets do
		FoundCount = FoundCount + 1
		if ShouldTrackCrate(Target) then
			local Position = Target.AnchorPosition
			if Position then
				local Distance = (Origin - Position).Magnitude
				if Distance <= Flags.CrateEspMaxDistance then
					local ScreenPosition, OnScreen = ProjectToScreen(Position + Vector3.new(0, 1.25, 0))
					if OnScreen and ScreenPosition then
						local Bundle = GetCrateEspBundle(Identity)
						if Bundle and Bundle.Label then
							local BoxX
							local BoxY
							local BoxWidth
							local BoxHeight
							if Flags.CrateEspBox then
								BoxX, BoxY, BoxWidth, BoxHeight =
									GetCrateScreenBox(Target, Distance, ScreenPosition)
							end

							if BoxX then
								local Segments
								if Flags.CrateEspBoxStyle == "Full" then
									Segments = BuildFullBoxSegments(BoxX, BoxY, BoxWidth, BoxHeight)
								else
									Segments = BuildCornerBoxSegments(BoxX, BoxY, BoxWidth, BoxHeight)
								end
								SetCrateBoxSegments(
									Bundle.BoxOutline,
									Segments,
									Color3.fromRGB(0, 0, 0),
									Flags.CrateEspAlpha
								)
								SetCrateBoxSegments(
									Bundle.Box,
									Segments,
									Flags.CrateEspColor,
									Flags.CrateEspAlpha
								)
							else
								for _, Line in Bundle.BoxOutline do
									Line.Visible = false
								end
								for _, Line in Bundle.Box do
									Line.Visible = false
								end
							end

							local Text = Target.DisplayName or "Crate"
							if Flags.CrateEspShowDistance then
								Text = Text .. "  [" .. tostring(math.floor(Distance + 0.5)) .. "u]"
							end
							Bundle.Label.Text = Text
							Bundle.Label.Position = BoxX
									and Vector2.new(BoxX + BoxWidth * 0.5, BoxY - 15)
								or ScreenPosition
							Bundle.Label.Color = Flags.CrateEspColor
							Bundle.Label.Transparency = Flags.CrateEspAlpha
							Bundle.Label.Visible = true
							ActiveBundles[Bundle] = true
							DrawnCount = DrawnCount + 1
						end
					end
				end
			end
		end
	end

	for _, Bundle in CrateEspBundles do
		if not ActiveBundles[Bundle] then
			HideCrateEspBundle(Bundle)
		end
	end

	CrateEspStatus.Text = tostring(DrawnCount)
		.. "/"
		.. tostring(FoundCount)
		.. " lootable"
		.. (CrateEspScanRunning and " | scanning" or "")
end

TrackConnection(RunService.RenderStepped:Connect(function()
	if not Flags.Running then
		return
	end

	local Success, ErrorMessage = pcall(UpdateEspFrame)
	if not Success then
		ReportEspError("ESP frame failed", ErrorMessage)
	end

	local CrateSuccess, CrateError = pcall(UpdateCrateEspFrame)
	if not CrateSuccess then
		HideAllCrateEspBundles()
		CrateEspStatus.Text = "update unavailable"
		if not CrateEspErrorReported then
			CrateEspErrorReported = true
			warn("crate ESP update failed: " .. tostring(CrateError))
		end
	end
end))

local FovCircleOutline = TrackDrawing(Drawing.new("Circle"))
FovCircleOutline.Thickness = 3
FovCircleOutline.NumSides = 96
FovCircleOutline.Color = Color3.fromRGB(0, 0, 0)
FovCircleOutline.Visible = false

local FovCircle = TrackDrawing(Drawing.new("Circle"))
FovCircle.Thickness = 1
FovCircle.NumSides = 96
FovCircle.Visible = false
FovCircle.ZIndex = 5

local SilentStatusUpdatedAt = -math.huge

TrackConnection(RunService.RenderStepped:Connect(function()
	if not Flags.Running then
		return
	end

	local Mouse = LocalPlayer:GetMouse()
	local MousePosition = Vector2.new(Mouse.X, Mouse.Y)
	local ShowAimFov = Flags.Aimbot and Flags.FovCheck
	local ShowSilentFov = Flags.SilentAim and Flags.SilentFovCheck
	local ShowFov = ShowAimFov or ShowSilentFov
	local DisplayFovRadius = 0
	if ShowAimFov then
		DisplayFovRadius = math.max(DisplayFovRadius, Flags.FovRadius)
	end
	if ShowSilentFov then
		DisplayFovRadius = math.max(DisplayFovRadius, Flags.SilentFovRadius)
	end

	FovCircleOutline.Position = MousePosition
	FovCircleOutline.Radius = DisplayFovRadius + 1
	FovCircleOutline.Transparency = Flags.FovAlpha
	FovCircleOutline.Visible = ShowFov

	FovCircle.Position = MousePosition
	FovCircle.Radius = DisplayFovRadius
	FovCircle.Color = Flags.FovColor
	FovCircle.Transparency = Flags.FovAlpha
	FovCircle.Visible = ShowFov

	local Now = tick()
	if Flags.SilentAim and Now - SilentStatusUpdatedAt >= 0.1 then
		SilentStatusUpdatedAt = Now
		local Target, ScreenDistance, WorldDistance = FindClosestTarget({
			FovCheck = Flags.SilentFovCheck,
			FovRadius = Flags.SilentFovRadius,
			MaxDistance = Flags.SilentMaxDistance,
		})
		UpdateSilentTargetStatus(Target, ScreenDistance, WorldDistance)
	elseif not Flags.SilentAim then
		SilentAimStatus.Text = "inactive"
	end
end))

TrackConnection(RunService.Heartbeat:Connect(function(DeltaTime)
	if not Flags.Running then
		return
	end

	if not Flags.Aimbot or not Flags.AimbotActive then
		ClearLock()
		return
	end

	local Camera = Workspace.CurrentCamera
	if not Camera then
		return
	end

	local Target
	if Flags.StickyAim then
		Target = GetLockedTarget()
	end

	if not Target then
		Flags.LockedPlayerName = nil
		Target = FindClosestTarget()
		if Target and Flags.StickyAim then
			Flags.LockedPlayerName = Target.Player.Name
		end
	end

	if not Target then
		SmoothedAimPosition = nil
		SmoothedAimTargetName = nil
		return
	end

	local CameraPosition = Camera.Position
	local AimPosition = PredictTargetPosition(Target, CameraPosition)
	if not AimPosition then
		ClearLock()
		return
	end

	local TargetName = Target.Player.Name
	local Smoothness = math.clamp(Flags.AimSmoothness or 0, 0, 100)
	local LookPosition = AimPosition
	if Smoothness > 0 then
		if SmoothedAimPosition and SmoothedAimTargetName == TargetName then
			local ResponseSpeed = 28 - ((Smoothness / 100) * 26)
			local FrameTime = math.max(DeltaTime or (1 / 60), 0)
			local Alpha = math.clamp(1 - math.exp(-ResponseSpeed * FrameTime), 0.01, 1)
			SmoothedAimPosition = SmoothedAimPosition:Lerp(AimPosition, Alpha)
		else
			local CurrentLookPosition
			pcall(function()
				local AimDistance = math.max((AimPosition - CameraPosition).Magnitude, 1)
				CurrentLookPosition = CameraPosition + (Camera.CFrame.LookVector * AimDistance)
			end)
			SmoothedAimPosition = CurrentLookPosition or AimPosition
		end
		SmoothedAimTargetName = TargetName
		LookPosition = SmoothedAimPosition
	else
		SmoothedAimPosition = AimPosition
		SmoothedAimTargetName = TargetName
	end

	local AimSuccess = pcall(function()
		Camera.lookAt(CameraPosition, LookPosition)
	end)
	if not AimSuccess then
		ClearLock()
	end
end))

Environment.SilentAim = SilentAim
Environment.UnloadDesertStormAim = Runtime.Unload
Environment.__MatchaAimRuntime = Runtime
