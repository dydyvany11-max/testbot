-- AutoBot.client.lua
-- StarterPlayer > StarterPlayerScripts

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local CONFIG = {

	-----------------------------------------------------------------
	-- AI
	-----------------------------------------------------------------

	ThinkInterval = 0.03,

	DetectionInterval = 0.05,

	-- Ищет врага на всей карте.
	GlobalChaseRadius = 5000,

	TeamCheck = true,

	-----------------------------------------------------------------
	-- AIM
	-----------------------------------------------------------------

	-- Камера быстро доводится, но без дерганий.
	AimSpeed = 32,

	-- Сглаживание самой позиции головы.
	AimPositionSpeed = 24,

	-- Стрелять только при очень точном наведении.
	FireAimTolerance = 1.5,

	AimHead = true,

	-----------------------------------------------------------------
	-- COMBAT
	-----------------------------------------------------------------

	-- До этого расстояния сначала подбегает.
	CombatStopDistance = 120,

	AttackRange = 250,

	-- Сколько постоять после остановки перед первым выстрелом.
	AimSettleTime = 0.12,

	FireDelay = 0.10,

	-- Небольшая пауза после выстрела,
	-- чтобы не начинал сразу дергаться.
	PostShotPause = 0.07,

	-----------------------------------------------------------------
	-- PATH
	-----------------------------------------------------------------

	AgentRadius = 2,
	AgentHeight = 5,

	AgentCanJump = true,
	AgentCanClimb = false,

	WaypointReachDistance = 4,

	-- Через сколько обязательно пересчитать путь.
	ForceRepathAfter = 0.8,

	-- Насколько должна сместиться цель.
	RepathDistance = 5,

	-----------------------------------------------------------------
	-- STUCK
	-----------------------------------------------------------------

	StuckCheckInterval = 0.5,

	StuckMinMovement = 1.3,

	MaxStuckChecks = 3,

	-----------------------------------------------------------------
	-- PATROL
	-----------------------------------------------------------------

	PatrolMinDistance = 60,
	PatrolMaxDistance = 150,

	PatrolTimeout = 8,

	-----------------------------------------------------------------
	-- WEAPONS
	-----------------------------------------------------------------

	WeaponPriority = {

		"AK47",
		"AK-47",

		"M4A1",
		"M4A4",
		"M4",

		"Deagle",
		"Desert Eagle",

		"AWP",

		"Galil",
		"Famas",

		"P90",
		"MP5",

		"USP",
		"USP-S",

		"Glock",
	},

	TryBindableFire = true,

	-----------------------------------------------------------------
	-- OPTIONAL BUY ADAPTER
	-----------------------------------------------------------------

	AutoBuy = true,

	BuyDelay = 1.5,

	BuyPriority = {
		"AK47",
		"AK-47",
		"M4A1",
		"M4A4",
		"Deagle",
		"Desert Eagle",
	},

	-----------------------------------------------------------------
	-- DEBUG
	-----------------------------------------------------------------

	Debug = true,
}

---------------------------------------------------------------------
-- CHARACTER
---------------------------------------------------------------------

local Character = nil
local Humanoid = nil
local Root = nil
local Head = nil

---------------------------------------------------------------------
-- CONTROLS
---------------------------------------------------------------------

local Controls = nil

local function disableControls()

	if Controls then
		return
	end

	pcall(function()

		local playerModule =
			require(
				LocalPlayer
					:WaitForChild("PlayerScripts")
					:WaitForChild("PlayerModule")
			)

		Controls =
			playerModule:GetControls()

		Controls:Disable()

		if CONFIG.Debug then
			print("[BOT] standard controls disabled")
		end
	end)
end

---------------------------------------------------------------------
-- TARGET
---------------------------------------------------------------------

local Target = nil

-- Не сырая позиция головы,
-- а сглаженная позиция для камеры.
local DesiredAimPosition = nil
local SmoothedAimPosition = nil

local LastDetection = 0

---------------------------------------------------------------------
-- COMBAT STATE
---------------------------------------------------------------------

local AimSettlingSince = nil

local MovementLockedUntil = 0

local LastShot = 0

local LastFireDebug = 0

---------------------------------------------------------------------
-- PATH STATE
---------------------------------------------------------------------

local CurrentPath = nil

local Waypoints = {}

local WaypointIndex = 1

local LastPathDestination = nil

local LastPathTime = 0

local ForceRepath = false

---------------------------------------------------------------------
-- MOVEMENT
---------------------------------------------------------------------

local WantsMovement = false

---------------------------------------------------------------------
-- STUCK
---------------------------------------------------------------------

local LastStuckPosition = nil

local LastStuckCheck = 0

local StuckChecks = 0

---------------------------------------------------------------------
-- PATROL
---------------------------------------------------------------------

local PatrolDestination = nil

local PatrolCreated = 0

local RNG = Random.new()

---------------------------------------------------------------------
-- SETUP
---------------------------------------------------------------------

local function setupCharacter(character)

	Character = character

	Humanoid =
		character:WaitForChild("Humanoid")

	Root =
		character:WaitForChild("HumanoidRootPart")

	Head =
		character:WaitForChild("Head")

	Humanoid.AutoRotate = true

	---------------------------------------------------------------
	-- WalkSpeed специально НЕ меняем.
	---------------------------------------------------------------

	Target = nil

	DesiredAimPosition = nil
	SmoothedAimPosition = nil

	AimSettlingSince = nil

	CurrentPath = nil

	Waypoints = {}

	PatrolDestination = nil

	LastStuckPosition =
		Root.Position

	StuckChecks = 0

	ForceRepath = true

	disableControls()

	if CONFIG.Debug then

		print(
			"[BOT] READY:",
			character.Name,
			"WalkSpeed:",
			Humanoid.WalkSpeed
		)
	end
end

---------------------------------------------------------------------
-- PLAYER DATA
---------------------------------------------------------------------

local function getPlayerData(player)

	local character =
		player.Character

	if not character then
		return nil
	end

	local humanoid =
		character:
			FindFirstChildOfClass(
				"Humanoid"
			)

	local root =
		character:
			FindFirstChild(
				"HumanoidRootPart"
			)

	if not humanoid
		or not root
		or not root:IsA("BasePart") then

		return nil
	end

	if humanoid.Health <= 0 then
		return nil
	end

	return character,
		humanoid,
		root
end

---------------------------------------------------------------------
-- TEAM CHECK
---------------------------------------------------------------------

local function isEnemy(player)

	if player == LocalPlayer then
		return false
	end

	if not CONFIG.TeamCheck then
		return true
	end

	---------------------------------------------------------------
	-- Standard Teams.
	---------------------------------------------------------------

	if LocalPlayer.Team
		and player.Team
		and LocalPlayer.Team == player.Team then

		return false
	end

	---------------------------------------------------------------
	-- Player Team attribute.
	---------------------------------------------------------------

	local myTeam =
		LocalPlayer:GetAttribute("Team")

	local theirTeam =
		player:GetAttribute("Team")

	if myTeam ~= nil
		and theirTeam ~= nil
		and myTeam == theirTeam then

		return false
	end

	---------------------------------------------------------------
	-- Side attribute.
	---------------------------------------------------------------

	local mySide =
		LocalPlayer:GetAttribute("Side")

	local theirSide =
		player:GetAttribute("Side")

	if mySide ~= nil
		and theirSide ~= nil
		and mySide == theirSide then

		return false
	end

	return true
end

---------------------------------------------------------------------
-- RAYCAST PARAMS
---------------------------------------------------------------------

local function createRaycastParams()

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	if Character then

		params.FilterDescendantsInstances = {
			Character,
		}
	end

	params.IgnoreWater = true

	return params
end

---------------------------------------------------------------------
-- LOS
---------------------------------------------------------------------

local function canSee(character)

	if not Head then
		return false
	end

	local parts = {

		character:
			FindFirstChild("Head"),

		character:
			FindFirstChild(
				"HumanoidRootPart"
			),
	}

	for _, part in ipairs(parts) do

		if not part
			or not part:IsA("BasePart") then

			continue
		end

		local result =
			Workspace:Raycast(

				Head.Position,

				part.Position
					- Head.Position,

				createRaycastParams()
			)

		if result
			and result.Instance:
				IsDescendantOf(character) then

			return true
		end
	end

	return false
end

---------------------------------------------------------------------
-- NEAREST ENEMY - 360 DEGREES
---------------------------------------------------------------------
--
-- Камера вообще НЕ нужна для поиска.
--
-- Поэтому никакого постоянного вращения камеры больше нет.
---------------------------------------------------------------------

local function findNearestEnemy()

	if not Root then
		return nil
	end

	local best = nil

	local bestDistance =
		math.huge

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		if not isEnemy(player) then
			continue
		end

		local character,
			_,
			targetRoot =
			getPlayerData(player)

		if not character then
			continue
		end

		local distance =
			(
				targetRoot.Position
				- Root.Position
			).Magnitude

		if distance
			> CONFIG.GlobalChaseRadius then

			continue
		end

		if distance
			< bestDistance then

			bestDistance =
				distance

			best =
				player
		end
	end

	return best
end

---------------------------------------------------------------------
-- AIM POSITION
---------------------------------------------------------------------

local function getAimPosition(
	character,
	targetRoot
)

	if CONFIG.AimHead then

		local targetHead =
			character:
				FindFirstChild("Head")

		if targetHead
			and targetHead:IsA("BasePart") then

			return targetHead.Position
		end
	end

	return targetRoot.Position
end

---------------------------------------------------------------------
-- CAMERA ANGLE
---------------------------------------------------------------------

local function cameraAngleTo(position)

	local camera =
		Workspace.CurrentCamera

	if not camera then
		return math.huge
	end

	local difference =
		position
		- camera.CFrame.Position

	if difference.Magnitude
		<= 0.001 then

		return 0
	end

	local direction =
		difference.Unit

	local dot =
		math.clamp(

			camera.CFrame.LookVector:
				Dot(direction),

			-1,
			1
		)

	return math.deg(
		math.acos(dot)
	)
end

---------------------------------------------------------------------
-- CAMERA
---------------------------------------------------------------------
--
-- ВАЖНО:
--
-- НЕТ ЦЕЛИ:
--   камера вообще не трогается.
--
-- ЕСТЬ ЦЕЛЬ:
--   всегда смотрим на неё,
--   даже пока бежим к ней.
--
-- Поэтому исчезает:
-- scan -> aim -> scan -> aim -> дерганье.
---------------------------------------------------------------------

RunService:BindToRenderStep(

	"AutoBotCamera",

	Enum.RenderPriority.Camera.Value + 1,

	function(dt)

		if not DesiredAimPosition then
			return
		end

		local camera =
			Workspace.CurrentCamera

		if not camera then
			return
		end

		-----------------------------------------------------------
		-- Сначала сглаживаем саму движущуюся Head.Position.
		-----------------------------------------------------------

		if not SmoothedAimPosition then

			SmoothedAimPosition =
				DesiredAimPosition

		else

			local positionAlpha =
				1
				- math.exp(
					-CONFIG.AimPositionSpeed
					* dt
				)

			SmoothedAimPosition =
				SmoothedAimPosition:Lerp(
					DesiredAimPosition,
					positionAlpha
				)
		end

		-----------------------------------------------------------
		-- Затем плавно двигаем камеру.
		-----------------------------------------------------------

		local current =
			camera.CFrame

		local wanted =
			CFrame.lookAt(
				current.Position,
				SmoothedAimPosition
			)

		local cameraAlpha =
			1
				- math.exp(
					-CONFIG.AimSpeed
					* dt
				)

		camera.CFrame =
			current:Lerp(
				wanted,
				cameraAlpha
			)
	end
)

---------------------------------------------------------------------
-- PATH
---------------------------------------------------------------------

local function computePath(destination)

	if not Root then
		return false
	end

	local path =
		PathfindingService:
			CreatePath({

				AgentRadius =
					CONFIG.AgentRadius,

				AgentHeight =
					CONFIG.AgentHeight,

				AgentCanJump =
					CONFIG.AgentCanJump,

				AgentCanClimb =
					CONFIG.AgentCanClimb,
			})

	local success, err =
		pcall(function()

			path:ComputeAsync(
				Root.Position,
				destination
			)
		end)

	if not success then

		if CONFIG.Debug then

			warn(
				"[BOT PATH]",
				err
			)
		end

		CurrentPath = nil

		Waypoints = {}

		return false
	end

	if path.Status
		~= Enum.PathStatus.Success then

		if CONFIG.Debug then

			warn(
				"[BOT PATH STATUS]",
				path.Status
			)
		end

		CurrentPath = nil

		Waypoints = {}

		return false
	end

	CurrentPath =
		path

	Waypoints =
		path:GetWaypoints()

	WaypointIndex =
		#Waypoints >= 2
		and 2
		or 1

	LastPathDestination =
		destination

	LastPathTime =
		os.clock()

	return true
end

---------------------------------------------------------------------
-- REPATH?
---------------------------------------------------------------------

local function needsRepath(destination)

	if ForceRepath then

		ForceRepath = false

		return true
	end

	if #Waypoints == 0 then
		return true
	end

	if os.clock()
		- LastPathTime
		>= CONFIG.ForceRepathAfter then

		return true
	end

	if LastPathDestination then

		if (
			destination
			- LastPathDestination
		).Magnitude
			>= CONFIG.RepathDistance then

			return true
		end
	end

	return false
end

---------------------------------------------------------------------
-- STOP
---------------------------------------------------------------------

local function stopMovement()

	WantsMovement = false

	if Humanoid then

		Humanoid:Move(
			Vector3.zero,
			false
		)
	end
end

---------------------------------------------------------------------
-- DIRECT MOVEMENT
---------------------------------------------------------------------

local function directMove(destination)

	if not Root
		or not Humanoid then

		return
	end

	if os.clock()
		< MovementLockedUntil then

		stopMovement()

		return
	end

	local difference =
		destination
		- Root.Position

	local flat =
		Vector3.new(
			difference.X,
			0,
			difference.Z
		)

	if flat.Magnitude <= 0.1 then

		stopMovement()

		return
	end

	WantsMovement = true

	Humanoid.AutoRotate = true

	Humanoid:Move(
		flat.Unit,
		false
	)
end

---------------------------------------------------------------------
-- FOLLOW PATH
---------------------------------------------------------------------

local function followPath()

	if not Root
		or not Humanoid then

		return false
	end

	if os.clock()
		< MovementLockedUntil then

		stopMovement()

		return true
	end

	local waypoint =
		Waypoints[
			WaypointIndex
		]

	if not waypoint then
		return false
	end

	local difference =
		waypoint.Position
		- Root.Position

	local flat =
		Vector3.new(
			difference.X,
			0,
			difference.Z
		)

	---------------------------------------------------------------
	-- REACHED
	---------------------------------------------------------------

	if flat.Magnitude
		<= CONFIG.WaypointReachDistance then

		WaypointIndex += 1

		waypoint =
			Waypoints[
				WaypointIndex
			]

		if not waypoint then
			return false
		end

		difference =
			waypoint.Position
			- Root.Position

		flat =
			Vector3.new(
				difference.X,
				0,
				difference.Z
			)
	end

	---------------------------------------------------------------
	-- JUMP
	---------------------------------------------------------------

	if waypoint.Action
		== Enum.PathWaypointAction.Jump then

		Humanoid.Jump = true
	end

	---------------------------------------------------------------
	-- MOVEMENT
	---------------------------------------------------------------

	if flat.Magnitude > 0.05 then

		WantsMovement = true

		Humanoid.AutoRotate = true

		Humanoid:Move(
			flat.Unit,
			false
		)

		return true
	end

	return false
end

---------------------------------------------------------------------
-- MOVE TO
---------------------------------------------------------------------

local function moveTo(destination)

	if not Root
		or not Humanoid then

		return
	end

	if os.clock()
		< MovementLockedUntil then

		stopMovement()

		return
	end

	if needsRepath(destination) then

		local success =
			computePath(
				destination
			)

		if not success then

			directMove(
				destination
			)

			return
		end
	end

	if not followPath() then

		ForceRepath = true

		directMove(
			destination
		)
	end
end

---------------------------------------------------------------------
-- STUCK
---------------------------------------------------------------------

local function updateStuckDetection()

	if not Root then
		return
	end

	local now =
		os.clock()

	if now - LastStuckCheck
		< CONFIG.StuckCheckInterval then

		return
	end

	LastStuckCheck =
		now

	if not LastStuckPosition then

		LastStuckPosition =
			Root.Position

		return
	end

	local moved =
		(
			Root.Position
			- LastStuckPosition
		).Magnitude

	LastStuckPosition =
		Root.Position

	if not WantsMovement then

		StuckChecks = 0

		return
	end

	if moved
		< CONFIG.StuckMinMovement then

		StuckChecks += 1

	else

		StuckChecks = 0
	end

	if StuckChecks
		>= CONFIG.MaxStuckChecks then

		if CONFIG.Debug then
			print("[BOT] STUCK -> REPATH")
		end

		StuckChecks = 0

		ForceRepath = true

		CurrentPath = nil

		Waypoints = {}

		if Humanoid then
			Humanoid.Jump = true
		end
	end
end

---------------------------------------------------------------------
-- RANDOM PATROL
---------------------------------------------------------------------

local function createPatrolDestination()

	if not Root then
		return nil
	end

	for _ = 1, 15 do

		local angle =
			RNG:NextNumber(
				0,
				math.pi * 2
			)

		local distance =
			RNG:NextNumber(
				CONFIG.PatrolMinDistance,
				CONFIG.PatrolMaxDistance
			)

		local candidate =
			Root.Position
			+ Vector3.new(

				math.cos(angle)
					* distance,

				0,

				math.sin(angle)
					* distance
			)

		local result =
			Workspace:Raycast(

				candidate
					+ Vector3.new(
						0,
						120,
						0
					),

				Vector3.new(
					0,
					-300,
					0
				),

				createRaycastParams()
			)

		if result then

			return result.Position
				+ Vector3.new(
					0,
					2,
					0
				)
		end
	end

	return nil
end

---------------------------------------------------------------------
-- PATROL
---------------------------------------------------------------------

local function patrol()

	DesiredAimPosition = nil
	SmoothedAimPosition = nil

	if not Root then
		return
	end

	local needNew =
		PatrolDestination == nil

	if PatrolDestination
		and (
			Root.Position
			- PatrolDestination
		).Magnitude <= 7 then

		needNew = true
	end

	if PatrolDestination
		and os.clock()
			- PatrolCreated
			>= CONFIG.PatrolTimeout then

		needNew = true
	end

	if needNew then

		PatrolDestination =
			createPatrolDestination()

		PatrolCreated =
			os.clock()

		ForceRepath = true

		Waypoints = {}
	end

	if PatrolDestination then

		moveTo(
			PatrolDestination
		)
	end
end

---------------------------------------------------------------------
-- TOOLS
---------------------------------------------------------------------

local function getAllTools()

	local tools = {}

	local seen = {}

	local function scan(parent)

		if not parent then
			return
		end

		for _, object in ipairs(
			parent:GetDescendants()
		) do

			if object:IsA("Tool")
				and not seen[object] then

				seen[object] = true

				table.insert(
					tools,
					object
				)
			end
		end
	end

	scan(Character)

	scan(
		LocalPlayer:
			FindFirstChildOfClass(
				"Backpack"
			)
	)

	return tools
end

---------------------------------------------------------------------
-- EQUIPPED TOOL
---------------------------------------------------------------------

local function getEquippedTool()

	if not Character then
		return nil
	end

	for _, object in ipairs(
		Character:GetChildren()
	) do

		if object:IsA("Tool") then
			return object
		end
	end

	return nil
end

---------------------------------------------------------------------
-- WEAPON NAME SCORE
---------------------------------------------------------------------

local function weaponScore(tool)

	local lowerName =
		string.lower(
			tool.Name
		)

	for index, name in ipairs(
		CONFIG.WeaponPriority
	) do

		local wanted =
			string.lower(name)

		if lowerName == wanted
			or string.find(
				lowerName,
				wanted,
				1,
				true
			) then

			return index
		end
	end

	return 9999
end

---------------------------------------------------------------------
-- EQUIP BEST WEAPON
---------------------------------------------------------------------

local function equipBestWeapon()

	local equipped =
		getEquippedTool()

	if equipped then
		return equipped
	end

	if not Humanoid then
		return nil
	end

	local tools =
		getAllTools()

	table.sort(
		tools,

		function(a, b)

			return weaponScore(a)
				< weaponScore(b)
		end
	)

	for _, tool in ipairs(tools) do

		pcall(function()

			Humanoid:
				EquipTool(tool)
		end)

		task.wait()

		if tool.Parent
			== Character then

			if CONFIG.Debug then

				print(
					"[BOT] equipped:",
					tool.Name
				)
			end

			return tool
		end
	end

	return nil
end

---------------------------------------------------------------------
-- LOCAL FIRE ADAPTERS
---------------------------------------------------------------------

local FIRE_NAMES = {

	"Fire",
	"Shoot",
	"Trigger",

	"FireWeapon",
	"ShootWeapon",

	"FireGun",
	"ShootGun",

	"PrimaryFire",
	"PrimaryAttack",
}

local function tryBindableFire(
	parent,
	targetPosition
)

	if not CONFIG.TryBindableFire
		or not parent then

		return false
	end

	for _, name in ipairs(
		FIRE_NAMES
	) do

		local object =
			parent:
				FindFirstChild(
					name,
					true
				)

		if not object then
			continue
		end

		if object:IsA(
			"BindableEvent"
		) then

			object:Fire(
				targetPosition
			)

			if CONFIG.Debug then

				print(
					"[BOT FIRE] event:",
					object:GetFullName()
				)
			end

			return true
		end

		if object:IsA(
			"BindableFunction"
		) then

			local success =
				pcall(function()

					object:Invoke(
						targetPosition
					)
				end)

			if success then

				if CONFIG.Debug then

					print(
						"[BOT FIRE] function:",
						object:GetFullName()
					)
				end

				return true
			end
		end
	end

	return false
end

---------------------------------------------------------------------
-- FIRE
---------------------------------------------------------------------

local function fireWeapon(
	targetPosition
)

	if os.clock()
		- LastShot
		< CONFIG.FireDelay then

		return false
	end

	---------------------------------------------------------------
	-- Очень точное наведение.
	---------------------------------------------------------------

	local angle =
		cameraAngleTo(
			targetPosition
		)

	if angle
		> CONFIG.FireAimTolerance then

		return false
	end

	local tool =
		getEquippedTool()
		or equipBestWeapon()

	if not tool then

		if CONFIG.Debug
			and os.clock()
				- LastFireDebug > 1 then

			LastFireDebug =
				os.clock()

			warn(
				"[BOT FIRE] NO TOOL"
			)
		end

		return false
	end

	---------------------------------------------------------------
	-- Сначала custom local Fire/Shoot.
	---------------------------------------------------------------

	if tryBindableFire(
		tool,
		targetPosition
	) then

		LastShot =
			os.clock()

		return true
	end

	---------------------------------------------------------------
	-- Затем Character adapter.
	---------------------------------------------------------------

	if tryBindableFire(
		Character,
		targetPosition
	) then

		LastShot =
			os.clock()

		return true
	end

	---------------------------------------------------------------
	-- Затем общий local adapter.
	---------------------------------------------------------------

	if tryBindableFire(
		ReplicatedStorage,
		targetPosition
	) then

		LastShot =
			os.clock()

		return true
	end

	---------------------------------------------------------------
	-- Standard Tool.
	---------------------------------------------------------------

	if not tool.Enabled then

		if CONFIG.Debug then

			warn(
				"[BOT FIRE]",
				tool.Name,
				"disabled"
			)
		end

		return false
	end

	local success, err =
		pcall(function()

			tool:Activate()
		end)

	if CONFIG.Debug
		and os.clock()
			- LastFireDebug > 0.8 then

		LastFireDebug =
			os.clock()

		print(
			"[BOT FIRE]",
			tool.Name,
			"Activate:",
			success,
			err or ""
		)
	end

	if not success then
		return false
	end

	LastShot =
		os.clock()

	task.delay(
		0.035,

		function()

			if tool
				and tool.Parent then

				pcall(function()

					tool:Deactivate()
				end)
			end
		end
	)

	return true
end

---------------------------------------------------------------------
-- OPTIONAL BUY ADAPTER
---------------------------------------------------------------------
--
-- Для своего магазина можно добавить:
--
-- BindableFunction BuyWeapon
--
-- или
--
-- BindableEvent BuyWeapon
--
-- Например:
--
-- BuyWeapon:Invoke("AK47")
---------------------------------------------------------------------

local function findBuyAdapter()

	local function scan(parent)

		if not parent then
			return nil
		end

		local object =
			parent:
				FindFirstChild(
					"BuyWeapon",
					true
				)

		if object
			and (
				object:IsA("BindableEvent")
				or object:IsA(
					"BindableFunction"
				)
			) then

			return object
		end

		return nil
	end

	return scan(ReplicatedStorage)
		or scan(LocalPlayer.PlayerGui)
end

local function tryBuyWeapon(name)

	local adapter =
		findBuyAdapter()

	if not adapter then
		return false
	end

	if adapter:IsA(
		"BindableEvent"
	) then

		adapter:Fire(name)

		return true
	end

	if adapter:IsA(
		"BindableFunction"
	) then

		local success, result =
			pcall(function()

				return adapter:
					Invoke(name)
			end)

		return success
			and result ~= false
	end

	return false
end

local function autoBuy()

	if not CONFIG.AutoBuy then
		return
	end

	for _, weaponName in ipairs(
		CONFIG.BuyPriority
	) do

		local success =
			tryBuyWeapon(
				weaponName
			)

		if success then

			if CONFIG.Debug then

				print(
					"[BOT BUY]",
					weaponName
				)
			end

			task.wait(0.15)
		end
	end
end

---------------------------------------------------------------------
-- CLEAR TARGET
---------------------------------------------------------------------

local function clearTarget()

	Target = nil

	DesiredAimPosition = nil

	SmoothedAimPosition = nil

	AimSettlingSince = nil

	CurrentPath = nil

	Waypoints = {}

	ForceRepath = true
end

---------------------------------------------------------------------
-- TARGET VALID?
---------------------------------------------------------------------

local function targetStillValid(
	player
)

	if not player
		or not isEnemy(player) then

		return false
	end

	local character,
		humanoid,
		targetRoot =
		getPlayerData(player)

	if not character
		or not humanoid
		or not targetRoot then

		return false
	end

	if not Root then
		return false
	end

	if (
		targetRoot.Position
		- Root.Position
	).Magnitude
		> CONFIG.GlobalChaseRadius then

		return false
	end

	return true
end

---------------------------------------------------------------------
-- UPDATE TARGET
---------------------------------------------------------------------
--
-- ВАЖНО:
--
-- Цель теперь НЕ меняется каждые 0.1 секунды.
--
-- Пока она живая и доступная,
-- бот преследует ОДНОГО игрока.
--
-- Это тоже сильно уменьшает тряску камеры.
---------------------------------------------------------------------

local function updateTarget()

	if os.clock()
		- LastDetection
		< CONFIG.DetectionInterval then

		return
	end

	LastDetection =
		os.clock()

	if targetStillValid(
		Target
	) then

		return
	end

	local newTarget =
		findNearestEnemy()

	if newTarget
		~= Target then

		Target =
			newTarget

		ForceRepath =
			true

		Waypoints = {}

		AimSettlingSince =
			nil

		SmoothedAimPosition =
			nil

		if CONFIG.Debug
			and Target then

			print(
				"[BOT TARGET]",
				Target.Name
			)
		end
	end
end

---------------------------------------------------------------------
-- PROCESS TARGET
---------------------------------------------------------------------

local function processTarget(
	player
)

	if not Root
		or not Humanoid then

		return false
	end

	local character,
		targetHumanoid,
		targetRoot =
		getPlayerData(player)

	if not character
		or not targetHumanoid
		or not targetRoot then

		clearTarget()

		return false
	end

	if not isEnemy(player) then

		clearTarget()

		return false
	end

	local distance =
		(
			targetRoot.Position
			- Root.Position
		).Magnitude

	---------------------------------------------------------------
	-- ГОЛОВУ ДЕРЖИМ ПОСТОЯННО.
	--
	-- Даже пока бежим.
	---------------------------------------------------------------

	local aimPosition =
		getAimPosition(
			character,
			targetRoot
		)

	DesiredAimPosition =
		aimPosition

	local visible =
		canSee(character)

	---------------------------------------------------------------
	-- TARGET BEHIND WALL
	---------------------------------------------------------------
	--
	-- Камера всё равно уже направлена в его сторону,
	-- но стрелять не пытаемся.
	--
	-- Pathfinding ведёт к текущему HumanoidRootPart.
	---------------------------------------------------------------

	if not visible then

		AimSettlingSince =
			nil

		moveTo(
			targetRoot.Position
		)

		return true
	end

	---------------------------------------------------------------
	-- TARGET VISIBLE BUT TOO FAR
	---------------------------------------------------------------

	if distance
		> CONFIG.CombatStopDistance then

		AimSettlingSince =
			nil

		---------------------------------------------------------
		-- БЕЖИМ + ОДНОВРЕМЕННО СМОТРИМ НА ГОЛОВУ.
		---------------------------------------------------------

		moveTo(
			targetRoot.Position
		)

		return true
	end

	---------------------------------------------------------------
	-- ENTER FIRING POSITION
	---------------------------------------------------------------

	stopMovement()

	---------------------------------------------------------------
	-- Камера должна стабилизироваться.
	---------------------------------------------------------------

	if not AimSettlingSince then

		AimSettlingSince =
			os.clock()

		return true
	end

	if os.clock()
		- AimSettlingSince
		< CONFIG.AimSettleTime then

		return true
	end

	---------------------------------------------------------------
	-- Очень точное доведение.
	---------------------------------------------------------------

	if cameraAngleTo(
		aimPosition
	) > CONFIG.FireAimTolerance then

		return true
	end

	---------------------------------------------------------------
	-- Перед выстрелом ещё раз проверяем стену.
	---------------------------------------------------------------

	if not canSee(character) then

		AimSettlingSince =
			nil

		return true
	end

	---------------------------------------------------------------
	-- FIRE
	---------------------------------------------------------------

	if distance
		<= CONFIG.AttackRange then

		local fired =
			fireWeapon(
				aimPosition
			)

		if fired then

			-----------------------------------------------------
			-- Не начинаем мгновенно двигаться после выстрела.
			-----------------------------------------------------

			MovementLockedUntil =
				os.clock()
				+ CONFIG.PostShotPause

			AimSettlingSince =
				os.clock()
		end
	end

	return true
end

---------------------------------------------------------------------
-- MAIN LOOP
---------------------------------------------------------------------

task.spawn(function()

	while true do

		if Character
			and Character.Parent
			and Humanoid
			and Root
			and Humanoid.Health > 0 then

			local success, err =
				pcall(function()

					updateStuckDetection()

					updateTarget()

					-------------------------------------------------
					-- TARGET EXISTS
					-------------------------------------------------

					if Target then

						if processTarget(
							Target
						) then

							return
						end
					end

					-------------------------------------------------
					-- NO PLAYER -> RANDOM PATROL
					-------------------------------------------------

					patrol()
				end)

			if not success then

				warn(
					"[BOT ERROR]",
					err
				)
			end

		else

			stopMovement()
		end

		task.wait(
			CONFIG.ThinkInterval
		)
	end
end)

---------------------------------------------------------------------
-- RESPAWN
---------------------------------------------------------------------

LocalPlayer.CharacterAdded:
	Connect(function(character)

		task.wait(0.25)

		setupCharacter(
			character
		)

		task.delay(
			CONFIG.BuyDelay,

			function()

				autoBuy()

				equipBestWeapon()
			end
		)
	end)

---------------------------------------------------------------------
-- EXISTING CHARACTER
---------------------------------------------------------------------

if LocalPlayer.Character then

	task.spawn(function()

		setupCharacter(
			LocalPlayer.Character
		)

		task.wait(
			CONFIG.BuyDelay
		)

		autoBuy()

		equipBestWeapon()
	end)
end

---------------------------------------------------------------------
-- READY
---------------------------------------------------------------------

print(
	"[AutoBot] FULL CLIENT BOT RUNNING"
)
