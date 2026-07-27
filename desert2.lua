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
	SilentAimActive = false,
	TeamCheck = false,
	FovCheck = true,
	TargetParts = { "Head" },
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
	LockedPlayerName = nil,
}

local Connections = {}
local Drawings = {}
local Win
local SilentAim

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

local function FindClosestTarget()
	local Mouse = LocalPlayer:GetMouse()
	local MousePosition = Vector2.new(Mouse.X, Mouse.Y)
	local LocalRoot = GetLocalRoot()
	local ClosestTarget
	local ClosestScreenDistance = math.huge

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
		if LocalPosition and (LocalPosition - TargetPosition).Magnitude > Flags.MaxAcquireDistance then
			continue
		end

		local ScreenPosition, OnScreen = ProjectToScreen(TargetPosition)
		if not OnScreen then
			continue
		end

		local DeltaX = ScreenPosition.X - MousePosition.X
		local DeltaY = ScreenPosition.Y - MousePosition.Y
		local ScreenDistance = math.sqrt(DeltaX * DeltaX + DeltaY * DeltaY)
		if Flags.FovCheck and ScreenDistance > Flags.FovRadius then
			continue
		end

		if ScreenDistance < ClosestScreenDistance then
			ClosestScreenDistance = ScreenDistance
			ClosestTarget = Target
		end
	end

	return ClosestTarget
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

SilentAim = function(Origin)
	if not Flags.SilentAim or not Flags.SilentAimActive then
		return nil
	end

	local Target = GetLockedTarget()
	if not Target then
		Target = FindClosestTarget()
	end
	if not Target then
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

	return PredictTargetPosition(Target, ShotOrigin), Target.TargetPart, Target.Player
end

local function LoadUiLibrary()
	if INSui then
		return INSui
	end

	local Success, Result = pcall(function()
		local Source = game:HttpGet("https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/uilib.min.lua")
		assert(type(Source) == "string" and #Source > 0, "empty UI library response")

		local Chunk = loadstring(Source)
		assert(type(Chunk) == "function", "UI library compilation failed")

		local LoadedLibrary = Chunk()
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
		menuKey = "insert",
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

local FovToggle = TargetSection:Toggle("field of view", true, function(Value)
	Flags.FovCheck = Value
end)

FovToggle:AddColorpicker("fov color", Flags.FovColor, function(Color, Alpha)
	Flags.FovColor = Color
	Flags.FovAlpha = Alpha
end)

TargetSection:Slider("fov radius", Flags.FovRadius, 1, 10, 400, "px", function(Value)
	Flags.FovRadius = Value
end)

TargetSection:Slider(
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

TargetSection:Dropdown(
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

PredictionSection:Toggle("auto prediction", true, function(Value)
	Flags.AutoPrediction = Value
end)

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
		Flags.SilentAimActive = false
	end
end):Tooltip("Exports SilentAim(origin); the new game's shot function must call it.")

SilentAimToggle:AddKeybind("V", "Hold", function(Value)
	Flags.SilentAimActive = Value
end)

SilentSection:Label("resolver: SilentAim(origin)")

local EspTab = Win:Tab("ESP", "eye")
local EspPlayerSection = EspTab:Section("player esp", "Left")
local EspStyleSection = EspTab:Section("skeet style", "Left")
local EspInfoSection = EspTab:Section("information", "Right")
local EspRangeSection = EspTab:Section("filtering", "Right")

EspPlayerSection:Toggle("enabled", false, function(Value)
	Flags.EspEnabled = Value
end)

EspPlayerSection:Toggle("Roblox team check", false, function(Value)
	Flags.EspTeamCheck = Value
end):Tooltip("Roblox teams only; this may not match DesertStorm squads.")

local BoxToggle = EspStyleSection:Toggle("bounding box", true, function(Value)
	Flags.EspBox = Value
end)

BoxToggle:AddColorpicker("box color", Flags.EspBoxColor, function(Color, Alpha)
	Flags.EspBoxColor = Color
	Flags.EspBoxAlpha = Alpha
end)

local ChamsToggle = EspStyleSection:Toggle("2D chams", false, function(Value)
	Flags.EspChams = Value
end)

ChamsToggle:AddColorpicker("chams color", Flags.EspChamsColor, function(Color, Alpha)
	Flags.EspChamsColor = Color
	Flags.EspChamsAlpha = Alpha
end)

ChamsToggle:Tooltip("Through-wall translucent body fill using Matcha's external Drawing renderer.")

EspStyleSection:Toggle("health bar", true, function(Value)
	Flags.EspHealth = Value
end)

local SnaplineToggle = EspStyleSection:Toggle("snapline", false, function(Value)
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

Win:AddSettingsTab("cog")

local EspBundles = {}

local function SetTextDefaults(TextObject, Centered)
	TextObject.Color = Flags.EspTextColor
	TextObject.FontSize = 13
	TextObject.Center = Centered
	TextObject.Outline = true
	TextObject.Visible = false
	TextObject.ZIndex = 14
	pcall(function()
		TextObject.Font = Drawing.Fonts.UI
	end)
end

local function CreateEspBundle()
	local Bundle = {
		Chams = TrackDrawing(Drawing.new("Square")),
		BoxOutline = TrackDrawing(Drawing.new("Square")),
		Box = TrackDrawing(Drawing.new("Square")),
		HealthBackground = TrackDrawing(Drawing.new("Square")),
		HealthBar = TrackDrawing(Drawing.new("Square")),
		Name = TrackDrawing(Drawing.new("Text")),
		Info = TrackDrawing(Drawing.new("Text")),
		Flag = TrackDrawing(Drawing.new("Text")),
		SnaplineOutline = TrackDrawing(Drawing.new("Line")),
		Snapline = TrackDrawing(Drawing.new("Line")),
	}

	Bundle.Chams.Filled = true
	Bundle.Chams.Visible = false
	Bundle.Chams.ZIndex = 5

	Bundle.BoxOutline.Filled = false
	Bundle.BoxOutline.Thickness = 3
	Bundle.BoxOutline.Color = Color3.fromRGB(0, 0, 0)
	Bundle.BoxOutline.Visible = false
	Bundle.BoxOutline.ZIndex = 10

	Bundle.Box.Filled = false
	Bundle.Box.Thickness = 1
	Bundle.Box.Visible = false
	Bundle.Box.ZIndex = 11

	Bundle.HealthBackground.Filled = true
	Bundle.HealthBackground.Color = Color3.fromRGB(0, 0, 0)
	Bundle.HealthBackground.Visible = false
	Bundle.HealthBackground.ZIndex = 10

	Bundle.HealthBar.Filled = true
	Bundle.HealthBar.Visible = false
	Bundle.HealthBar.ZIndex = 11

	SetTextDefaults(Bundle.Name, true)
	SetTextDefaults(Bundle.Info, true)
	SetTextDefaults(Bundle.Flag, false)

	Bundle.SnaplineOutline.Thickness = 3
	Bundle.SnaplineOutline.Color = Color3.fromRGB(0, 0, 0)
	Bundle.SnaplineOutline.Visible = false
	Bundle.SnaplineOutline.ZIndex = 9

	Bundle.Snapline.Thickness = 1
	Bundle.Snapline.Visible = false
	Bundle.Snapline.ZIndex = 10

	return Bundle
end

local function HideEspBundle(Bundle)
	if not Bundle then
		return
	end

	Bundle.Chams.Visible = false
	Bundle.BoxOutline.Visible = false
	Bundle.Box.Visible = false
	Bundle.HealthBackground.Visible = false
	Bundle.HealthBar.Visible = false
	Bundle.Name.Visible = false
	Bundle.Info.Visible = false
	Bundle.Flag.Visible = false
	Bundle.SnaplineOutline.Visible = false
	Bundle.Snapline.Visible = false
end

local function GetEspBundle(Player)
	local Bundle = EspBundles[Player]
	if not Bundle then
		Bundle = CreateEspBundle()
		EspBundles[Player] = Bundle
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
	for _, Child in Character:GetChildren() do
		local Success, IsTool = pcall(function()
			return Child:IsA("Tool")
		end)
		if Success and IsTool then
			return Child.Name
		end
	end
	return nil
end

local function GetEspTarget(Player)
	if not Player or Player.Name == LocalPlayer.Name or IsEspTeammate(Player) then
		return nil
	end

	local Character = Player.Character
	if not Character then
		return nil
	end

	local Humanoid = Character:FindFirstChild("Humanoid")
	local Head = Character:FindFirstChild("Head")
	local UpperTorso = Character:FindFirstChild("UpperTorso")
	local RootPart = Character:FindFirstChild("HumanoidRootPart")
	if not Humanoid or not RootPart or not (Head or UpperTorso) then
		return nil
	end

	local HealthSuccess, Health = pcall(function()
		return Humanoid.Health
	end)
	if not HealthSuccess or not Health or Health <= 0 then
		return nil
	end

	local MaxHealth = 100
	pcall(function()
		MaxHealth = Humanoid.MaxHealth or MaxHealth
	end)

	return {
		Player = Player,
		Character = Character,
		Head = Head or UpperTorso,
		RootPart = RootPart,
		Health = Health,
		MaxHealth = math.max(MaxHealth or 100, 1),
	}
end

local function GetEspBox(Target)
	local HeadPosition = GetPartPosition(Target.Head)
	local RootPosition = GetPartPosition(Target.RootPart)
	if not HeadPosition or not RootPosition then
		return nil
	end

	local TopScreen, TopVisible = ProjectToScreen(HeadPosition + Vector3.new(0, 1.25, 0))
	local BottomScreen, BottomVisible = ProjectToScreen(RootPosition - Vector3.new(0, 3.25, 0))
	if not TopVisible or not BottomVisible then
		return nil
	end

	local Height = math.abs(BottomScreen.Y - TopScreen.Y)
	if Height < 8 then
		return nil
	end

	local Width = Height * 0.52
	local CenterX = (TopScreen.X + BottomScreen.X) * 0.5
	local TopY = math.min(TopScreen.Y, BottomScreen.Y)
	return CenterX - Width * 0.5, TopY, Width, Height
end

local function UpdateEspBundle(Bundle, Target, Camera)
	HideEspBundle(Bundle)

	local LocalPosition = GetPartPosition(GetLocalRoot())
	local TargetPosition = GetPartPosition(Target.RootPart)
	if not TargetPosition then
		return
	end

	local CameraPosition
	pcall(function()
		CameraPosition = Camera.Position
	end)
	local Origin = LocalPosition or CameraPosition
	if not Origin then
		return
	end

	local Distance = (Origin - TargetPosition).Magnitude
	if Distance > Flags.EspMaxDistance then
		return
	end

	local X, Y, Width, Height = GetEspBox(Target)
	if not X then
		return
	end

	local BoxPosition = Vector2.new(X, Y)
	local BoxSize = Vector2.new(Width, Height)

	if Flags.EspChams then
		Bundle.Chams.Position = Vector2.new(X + 2, Y + 2)
		Bundle.Chams.Size = Vector2.new(math.max(Width - 4, 1), math.max(Height - 4, 1))
		Bundle.Chams.Color = Flags.EspChamsColor
		Bundle.Chams.Transparency = Flags.EspChamsAlpha
		Bundle.Chams.Visible = true
	end

	if Flags.EspBox then
		Bundle.BoxOutline.Position = BoxPosition
		Bundle.BoxOutline.Size = BoxSize
		Bundle.BoxOutline.Transparency = Flags.EspBoxAlpha
		Bundle.BoxOutline.Visible = true

		Bundle.Box.Position = BoxPosition
		Bundle.Box.Size = BoxSize
		Bundle.Box.Color = Flags.EspBoxColor
		Bundle.Box.Transparency = Flags.EspBoxAlpha
		Bundle.Box.Visible = true
	end

	if Flags.EspHealth then
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
	end

	if Flags.EspName then
		local DisplayName = Target.Player.Name
		pcall(function()
			if Target.Player.DisplayName and Target.Player.DisplayName ~= "" then
				DisplayName = Target.Player.DisplayName
			end
		end)
		Bundle.Name.Text = DisplayName
		Bundle.Name.Position = Vector2.new(X + Width * 0.5, Y - 15)
		Bundle.Name.Color = Flags.EspTextColor
		Bundle.Name.Transparency = Flags.EspTextAlpha
		Bundle.Name.Visible = true
	end

	local InfoParts = {}
	if Flags.EspDistance then
		InfoParts[#InfoParts + 1] = "[" .. tostring(math.floor(Distance + 0.5)) .. "u]"
	end
	if Flags.EspWeapon then
		local WeaponName = GetHeldWeaponName(Target.Character)
		if WeaponName then
			InfoParts[#InfoParts + 1] = WeaponName
		end
	end
	if #InfoParts > 0 then
		Bundle.Info.Text = table.concat(InfoParts, "  ")
		Bundle.Info.Position = Vector2.new(X + Width * 0.5, Y + Height + 2)
		Bundle.Info.Color = Flags.EspTextColor
		Bundle.Info.Transparency = Flags.EspTextAlpha
		Bundle.Info.Visible = true
	end

	if Flags.LockedPlayerName == Target.Player.Name then
		Bundle.Flag.Text = "TARGET"
		Bundle.Flag.Position = Vector2.new(X + Width + 4, Y)
		Bundle.Flag.Color = Color3.fromRGB(149, 192, 33)
		Bundle.Flag.Transparency = 1
		Bundle.Flag.Visible = true
	end

	if Flags.EspSnapline then
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
		end
	end
end

TrackConnection(RunService.RenderStepped:Connect(function()
	for _, Bundle in EspBundles do
		HideEspBundle(Bundle)
	end

	if not Flags.Running or not Flags.EspEnabled then
		return
	end

	local Camera = Workspace.CurrentCamera
	if not Camera then
		return
	end

	for _, Player in Players:GetPlayers() do
		local Target = GetEspTarget(Player)
		if Target then
			pcall(function()
				UpdateEspBundle(GetEspBundle(Player), Target, Camera)
			end)
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

TrackConnection(RunService.RenderStepped:Connect(function()
	if not Flags.Running then
		return
	end

	local Mouse = LocalPlayer:GetMouse()
	local MousePosition = Vector2.new(Mouse.X, Mouse.Y)
	local ShowFov = (Flags.Aimbot or Flags.SilentAim) and Flags.FovCheck

	FovCircleOutline.Position = MousePosition
	FovCircleOutline.Radius = Flags.FovRadius + 1
	FovCircleOutline.Transparency = Flags.FovAlpha
	FovCircleOutline.Visible = ShowFov

	FovCircle.Position = MousePosition
	FovCircle.Radius = Flags.FovRadius
	FovCircle.Color = Flags.FovColor
	FovCircle.Transparency = Flags.FovAlpha
	FovCircle.Visible = ShowFov
end))

TrackConnection(RunService.Heartbeat:Connect(function()
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

	local Target = GetLockedTarget()
	if not Target then
		Flags.LockedPlayerName = nil
		Target = FindClosestTarget()
		if Target then
			Flags.LockedPlayerName = Target.Player.Name
		end
	end

	if not Target then
		return
	end

	local CameraPosition = Camera.Position
	local AimPosition = PredictTargetPosition(Target, CameraPosition)
	if not AimPosition then
		ClearLock()
		return
	end

	local AimSuccess = pcall(function()
		Camera.lookAt(CameraPosition, AimPosition)
	end)
	if not AimSuccess then
		ClearLock()
	end
end))

Environment.SilentAim = SilentAim
Environment.__MatchaAimRuntime = Runtime
