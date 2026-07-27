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
	TeamCheck = false,
	FovCheck = true,
	TargetPart = "Head",
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
	if Flags.TargetPart == "Humanoid Root Part" then
		return RootPart or UpperTorso or Head
	end

	if Flags.TargetPart == "Upper Torso" then
		return UpperTorso or RootPart or Head
	end

	if Flags.TargetPart ~= "Closest" then
		return Head or UpperTorso or RootPart
	end

	local Mouse = LocalPlayer:GetMouse()
	local MousePosition = Vector2.new(Mouse.X, Mouse.Y)
	local ClosestPart = Head or UpperTorso or RootPart
	local ClosestDistance = math.huge

	for _, Part in Character:GetChildren() do
		if not Part:IsA("BasePart") then
			continue
		end

		local ScreenPosition, OnScreen = ProjectToScreen(GetPartPosition(Part))
		if not OnScreen then
			continue
		end

		local DeltaX = ScreenPosition.X - MousePosition.X
		local DeltaY = ScreenPosition.Y - MousePosition.Y
		local Distance = math.sqrt(DeltaX * DeltaX + DeltaY * DeltaY)
		if Distance < ClosestDistance then
			ClosestDistance = Distance
			ClosestPart = Part
		end
	end

	return ClosestPart
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
	if not Flags.SilentAim then
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
	"acquire distance",
	Flags.MaxAcquireDistance,
	25,
	100,
	5000,
	"studs",
	function(Value)
		Flags.MaxAcquireDistance = Value
	end
)

TargetSection:Dropdown(
	"target hitbox",
	{ Flags.TargetPart },
	{ "Head", "Upper Torso", "Humanoid Root Part", "Closest" },
	false,
	function(Value)
		Flags.TargetPart = Value[1]
	end
)

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
	"gravity compensation",
	Flags.GravityCompensation,
	0.1,
	0,
	250,
	"studs/s²",
	function(Value)
		Flags.GravityCompensation = Value
	end
)

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

SilentSection:Toggle("silent aim", false, function(Value)
	Flags.SilentAim = Value
end):Tooltip("Exports SilentAim(origin); the new game's shot function must call it.")

SilentSection:Label("resolver: SilentAim(origin)")
Win:AddSettingsTab("cog")

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
