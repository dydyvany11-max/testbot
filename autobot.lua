--!strict

-- AutoBot.client.lua
-- StarterPlayer > StarterPlayerScripts
--
-- Для собственного Roblox place.
--
-- НЕ ИСПОЛЬЗУЕТ:
-- Root.CFrame
-- PivotTo
-- изменение WalkSpeed
-- executor-only API
--
-- ИСПОЛЬЗУЕТ:
-- Humanoid:MoveTo()
-- PathfindingService
-- Workspace:Raycast()
-- Camera
-- Tool:Activate()

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local CONFIG = {

	-----------------------------------------------------------------
	-- AI
	-----------------------------------------------------------------

	ThinkInterval = 0.05,

	DetectionInterval = 0.08,

	-- Поиск противников вокруг себя.
	DetectionRadius = 500,

	-- Своих не атаковать.
	IgnoreSameTeam = true,

	-- Сколько помнить игрока после потери LOS.
	LostTargetTime = 3.5,

	-----------------------------------------------------------------
	-- CAMERA / AIM
	-----------------------------------------------------------------

	-- Скорость автоматического обзора,
	-- когда целей нет.
	ScanDegreesPerSecond = 75,

	-- Скорость доведения камеры к врагу.
	AimSpeed = 28,

	PreferHead = true,

	HeadAimChance = 0.92,

	-- Стрелять только если камера находится
	-- не дальше этого угла от цели.
	FireAimToleranceDegrees = 3.0,

	-----------------------------------------------------------------
	-- COMBAT
	-----------------------------------------------------------------

	AttackRange = 180,

	-- Ближе этого расстояния перестаём бежать прямо в игрока.
	StopDistance = 30,

	FireDelay = 0.10,

	-----------------------------------------------------------------
	-- PATHFINDING
	-----------------------------------------------------------------

	RepathInterval = 0.35,

	RepathDistance = 5,

	WaypointReachDistance = 4,

	AgentRadius = 2,

	AgentHeight = 5,

	AgentCanJump = true,

	AgentCanClimb = false,

	-----------------------------------------------------------------
	-- RANDOM MOVEMENT
	-----------------------------------------------------------------

	-- Бот выбирает новую точку относительно
	-- ТЕКУЩЕЙ позиции, поэтому постепенно гуляет по карте.
	PatrolStepMin = 45,

	PatrolStepMax = 110,

	-- Если он слишком долго идёт в одну точку,
	-- выбирается новая.
	PatrolDestinationTimeout = 8,

	PatrolPause = 0.15,

	-----------------------------------------------------------------
	-- WEAPONS
	-----------------------------------------------------------------

	WeaponPriority = {
		"AWP",

		"AK47",
		"AK-47",

		"M4A1",
		"M4A4",
		"M4",

		"Galil",
		"Famas",

		"P90",
		"MP5",

		"Deagle",
		"Desert Eagle",

		"P250",

		"USP",
		"USP-S",

		"Glock",
	},
}

---------------------------------------------------------------------
-- CHARACTER
---------------------------------------------------------------------

local Character: Model? = nil
local Humanoid: Humanoid? = nil
local Root: BasePart? = nil
local Head: BasePart? = nil

---------------------------------------------------------------------
-- TARGET
---------------------------------------------------------------------

local Target: Player? = nil

local LastSeenPosition: Vector3? = nil
local LastSeenTime = 0

local LastDetectionTime = 0

---------------------------------------------------------------------
-- CAMERA
---------------------------------------------------------------------

local AimPosition: Vector3? = nil

---------------------------------------------------------------------
-- WEAPON
---------------------------------------------------------------------

local LastShotTime = 0

---------------------------------------------------------------------
-- PATH
---------------------------------------------------------------------

local Waypoints = {}
local WaypointIndex = 1

local LastPathDestination: Vector3? = nil
local LastPathTime = 0

---------------------------------------------------------------------
-- PATROL
---------------------------------------------------------------------

local PatrolDestination: Vector3? = nil

local PatrolDestinationCreated = 0

local NextPatrolTime = 0

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

local function normalize(value: any): string
	return string.lower(tostring(value or ""))
end

---------------------------------------------------------------------
-- CHARACTER DATA
---------------------------------------------------------------------

local function getCharacterData(player: Player)

	local character = player.Character

	if not character then
		return nil
	end

	local humanoid =
		character:FindFirstChildOfClass("Humanoid")

	local root =
		character:FindFirstChild("HumanoidRootPart")

	if not humanoid
		or not root
		or not root:IsA("BasePart") then

		return nil
	end

	if humanoid.Health <= 0 then
		return nil
	end

	return character, humanoid, root
end

---------------------------------------------------------------------
-- SETUP CHARACTER
---------------------------------------------------------------------

local function setupCharacter(character: Model)

	Character = character

	Humanoid =
		character:WaitForChild("Humanoid") :: Humanoid

	Root =
		character:WaitForChild("HumanoidRootPart") :: BasePart

	Head =
		character:FindFirstChild("Head") :: BasePart?

	---------------------------------------------------------------
	-- Roblox сам поворачивает персонажа при движении.
	---------------------------------------------------------------

	Humanoid.AutoRotate = true

	---------------------------------------------------------------
	-- НЕ МЕНЯЕМ WalkSpeed.
	---------------------------------------------------------------

	Target = nil

	AimPosition = nil

	LastSeenPosition = nil

	Waypoints = {}

	PatrolDestination = nil

	print("[AutoBot] character initialized")
end

---------------------------------------------------------------------
-- TEAM CHECK
---------------------------------------------------------------------

local function isEnemy(player: Player): boolean

	if player == LocalPlayer then
		return false
	end

	if not CONFIG.IgnoreSameTeam then
		return true
	end

	---------------------------------------------------------------
	-- Одинаковая Team -> свой.
	---------------------------------------------------------------

	if LocalPlayer.Team
		and player.Team
		and LocalPlayer.Team == player.Team then

		return false
	end

	---------------------------------------------------------------
	-- Дополнительный fallback через TeamColor.
	---------------------------------------------------------------

	if LocalPlayer.TeamColor
		and player.TeamColor
		and LocalPlayer.TeamColor == player.TeamColor
		and LocalPlayer.Team ~= nil then

		return false
	end

	return true
end

---------------------------------------------------------------------
-- RAYCAST PARAMS
---------------------------------------------------------------------

local function getRaycastParams()

	local params = RaycastParams.new()

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
-- EYE POSITION
---------------------------------------------------------------------

local function getEyePosition(): Vector3?

	if Head then
		return Head.Position
	end

	if Root then

		return Root.Position
			+ Vector3.new(
				0,
				2,
				0
			)
	end

	return nil
end

---------------------------------------------------------------------
-- LINE OF SIGHT
---------------------------------------------------------------------

local function canSee(character: Model): boolean

	local origin =
		getEyePosition()

	if not origin then
		return false
	end

	---------------------------------------------------------------
	-- Сначала голова.
	---------------------------------------------------------------

	local target =
		character:FindFirstChild("Head")

	if not target then

		target =
			character:FindFirstChild(
				"HumanoidRootPart"
			)
	end

	if not target
		or not target:IsA("BasePart") then

		return false
	end

	local result =
		Workspace:Raycast(

			origin,

			target.Position - origin,

			getRaycastParams()
		)

	if not result then
		return false
	end

	---------------------------------------------------------------
	-- Луч должен реально первым встретить персонажа.
	---------------------------------------------------------------

	return result.Instance:
		IsDescendantOf(character)
end

---------------------------------------------------------------------
-- FIND TARGET - 360 DEGREES
---------------------------------------------------------------------
--
-- ВАЖНО:
-- цель больше НЕ обязана находиться перед камерой.
--
-- Камера визуально осматривается на 360,
-- но AI сам рассматривает всех игроков вокруг.
---------------------------------------------------------------------

local function findTarget(): Player?

	if not Root then
		return nil
	end

	local bestPlayer: Player? = nil
	local bestDistance = math.huge

	for _, player
		in ipairs(
			Players:GetPlayers()
		) do

		-------------------------------------------------------------
		-- Сначала team filter.
		-------------------------------------------------------------

		if not isEnemy(player) then
			continue
		end

		local character,
			_,
			targetRoot =
			getCharacterData(player)

		if not character then
			continue
		end

		local distance =
			(
				targetRoot.Position
				- Root.Position
			).Magnitude

		if distance > CONFIG.DetectionRadius then
			continue
		end

		if distance >= bestDistance then
			continue
		end

		-------------------------------------------------------------
		-- Стена?
		-------------------------------------------------------------

		if not canSee(character) then
			continue
		end

		bestDistance = distance
		bestPlayer = player
	end

	return bestPlayer
end

---------------------------------------------------------------------
-- AIM POSITION
---------------------------------------------------------------------

local function calculateAimPosition(
	character: Model,
	targetRoot: BasePart
): Vector3

	local targetPart: BasePart =
		targetRoot

	local head =
		character:FindFirstChild("Head")

	if CONFIG.PreferHead
		and head
		and head:IsA("BasePart")
		and math.random()
			<= CONFIG.HeadAimChance then

		targetPart = head
	end

	return targetPart.Position
end

---------------------------------------------------------------------
-- CAMERA ANGLE TO TARGET
---------------------------------------------------------------------

local function getCameraAngle(
	position: Vector3
): number

	local camera =
		Workspace.CurrentCamera

	if not camera then
		return math.huge
	end

	local offset =
		position - camera.CFrame.Position

	if offset.Magnitude <= 0.001 then
		return 0
	end

	local direction =
		offset.Unit

	local dot =
		math.clamp(
			camera.CFrame.LookVector:Dot(
				direction
			),
			-1,
			1
		)

	return math.deg(
		math.acos(dot)
	)
end

---------------------------------------------------------------------
-- CAMERA CONTROLLER
---------------------------------------------------------------------
--
-- TARGET:
--   плавно доворачивается к игроку.
--
-- NO TARGET:
--   автоматически крутится на 360 градусов.
--
-- Root.CFrame НЕ меняется.
---------------------------------------------------------------------

RunService:BindToRenderStep(

	"AutoBotCamera",

	Enum.RenderPriority.Camera.Value + 1,

	function(dt)

		local camera =
			Workspace.CurrentCamera

		if not camera then
			return
		end

		-------------------------------------------------------------
		-- AIM TARGET
		-------------------------------------------------------------

		if AimPosition then

			local current =
				camera.CFrame

			local desired =
				CFrame.lookAt(
					current.Position,
					AimPosition
				)

			local alpha =
				1
				- math.exp(
					-CONFIG.AimSpeed
					* dt
				)

			camera.CFrame =
				current:Lerp(
					desired,
					alpha
				)

			return
		end

		-------------------------------------------------------------
		-- 360 SCANNING
		-------------------------------------------------------------

		local yaw =
			math.rad(
				CONFIG.ScanDegreesPerSecond
			) * dt

		camera.CFrame =
			camera.CFrame
			* CFrame.Angles(
				0,
				yaw,
				0
			)
	end
)

---------------------------------------------------------------------
-- COMPUTE PATH
---------------------------------------------------------------------

local function computePath(
	destination: Vector3
): boolean

	if not Root then
		return false
	end

	local path =
		PathfindingService:CreatePath({

			AgentRadius =
				CONFIG.AgentRadius,

			AgentHeight =
				CONFIG.AgentHeight,

			AgentCanJump =
				CONFIG.AgentCanJump,

			AgentCanClimb =
				CONFIG.AgentCanClimb,
		})

	local success =
		pcall(function()

			path:ComputeAsync(
				Root.Position,
				destination
			)

		end)

	if not success
		or path.Status
			~= Enum.PathStatus.Success then

		Waypoints = {}

		return false
	end

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

local function needsRepath(
	destination: Vector3
): boolean

	if #Waypoints == 0 then
		return true
	end

	if os.clock()
		- LastPathTime
		>= CONFIG.RepathInterval then

		return true
	end

	if LastPathDestination then

		if (
			LastPathDestination
			- destination
		).Magnitude >= CONFIG.RepathDistance then

			return true
		end
	end

	return false
end

---------------------------------------------------------------------
-- FOLLOW PATH
---------------------------------------------------------------------

local function followPath(): boolean

	if not Root
		or not Humanoid then

		return false
	end

	local waypoint =
		Waypoints[
			WaypointIndex
		]

	if not waypoint then
		return false
	end

	---------------------------------------------------------------
	-- Следующая waypoint.
	---------------------------------------------------------------

	if (
		Root.Position
		- waypoint.Position
	).Magnitude
		<= CONFIG.WaypointReachDistance then

		WaypointIndex += 1

		waypoint =
			Waypoints[
				WaypointIndex
			]

		if not waypoint then
			return false
		end
	end

	---------------------------------------------------------------
	-- JUMP
	---------------------------------------------------------------

	if waypoint.Action
		== Enum.PathWaypointAction.Jump then

		Humanoid.Jump = true
	end

	Humanoid.AutoRotate = true

	Humanoid:MoveTo(
		waypoint.Position
	)

	return true
end

---------------------------------------------------------------------
-- MOVE TO
---------------------------------------------------------------------

local function moveTo(
	destination: Vector3
)

	if not Humanoid then
		return
	end

	Humanoid.AutoRotate = true

	if needsRepath(destination) then

		if not computePath(
			destination
		) then

			---------------------------------------------------------
			-- Pathfinding не смог ->
			-- всё равно пытаемся идти напрямую.
			---------------------------------------------------------

			Humanoid:MoveTo(
				destination
			)

			return
		end
	end

	followPath()
end

---------------------------------------------------------------------
-- STOP MOVEMENT
---------------------------------------------------------------------

local function stopMovement()

	if not Humanoid
		or not Root then

		return
	end

	Humanoid.AutoRotate = true

	Humanoid:MoveTo(
		Root.Position
	)
end

---------------------------------------------------------------------
-- CREATE PATROL DESTINATION
---------------------------------------------------------------------
--
-- Точка выбирается относительно ТЕКУЩЕЙ позиции,
-- а не spawn.
--
-- Поэтому бот может постепенно пройти всю карту.
---------------------------------------------------------------------

local function createPatrolDestination(): Vector3?

	if not Root then
		return nil
	end

	for _ = 1, 12 do

		local angle =
			math.random()
			* math.pi
			* 2

		local distance =
			math.random(
				CONFIG.PatrolStepMin,
				CONFIG.PatrolStepMax
			)

		local offset =
			Vector3.new(
				math.cos(angle) * distance,
				0,
				math.sin(angle) * distance
			)

		local candidate =
			Root.Position + offset

		-------------------------------------------------------------
		-- Ищем поверхность.
		-------------------------------------------------------------

		local result =
			Workspace:Raycast(

				candidate
					+ Vector3.new(
						0,
						100,
						0
					),

				Vector3.new(
					0,
					-250,
					0
				),

				getRaycastParams()
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

	if not Root
		or not Humanoid then

		return
	end

	if os.clock()
		< NextPatrolTime then

		return
	end

	---------------------------------------------------------------
	-- Нужна новая точка?
	---------------------------------------------------------------

	local needNewDestination =
		PatrolDestination == nil

	---------------------------------------------------------------
	-- Дошли.
	---------------------------------------------------------------

	if PatrolDestination
		and (
			Root.Position
			- PatrolDestination
		).Magnitude <= 7 then

		needNewDestination = true
	end

	---------------------------------------------------------------
	-- Слишком долго идём ->
	-- скорее всего застряли.
	---------------------------------------------------------------

	if PatrolDestination
		and os.clock()
			- PatrolDestinationCreated
			>= CONFIG.PatrolDestinationTimeout then

		needNewDestination = true
	end

	if needNewDestination then

		PatrolDestination =
			createPatrolDestination()

		PatrolDestinationCreated =
			os.clock()

		Waypoints = {}

		if not PatrolDestination then

			NextPatrolTime =
				os.clock() + 1

			return
		end
	end

	moveTo(
		PatrolDestination
	)

	NextPatrolTime =
		os.clock()
		+ CONFIG.PatrolPause
end

---------------------------------------------------------------------
-- FIND TOOL
---------------------------------------------------------------------

local function findTool(
	name: string
): Tool?

	local wanted =
		normalize(name)

	local function search(
		parent: Instance?
	): Tool?

		if not parent then
			return nil
		end

		for _, item
			in ipairs(
				parent:GetChildren()
			) do

			if not item:IsA("Tool") then
				continue
			end

			local currentName =
				normalize(
					item.Name
				)

			if currentName == wanted
				or string.find(
					currentName,
					wanted,
					1,
					true
				) then

				return item
			end
		end

		return nil
	end

	return search(Character)
		or search(
			LocalPlayer:
				FindFirstChildOfClass(
					"Backpack"
				)
		)
end

---------------------------------------------------------------------
-- CURRENT TOOL
---------------------------------------------------------------------

local function currentTool(): Tool?

	if not Character then
		return nil
	end

	return Character:
		FindFirstChildOfClass("Tool")
end

---------------------------------------------------------------------
-- EQUIP BEST TOOL
---------------------------------------------------------------------

local function equipBestTool(): Tool?

	if not Humanoid then
		return nil
	end

	for _, weaponName
		in ipairs(
			CONFIG.WeaponPriority
		) do

		local tool =
			findTool(
				weaponName
			)

		if tool then

			if tool.Parent
				~= Character then

				pcall(function()

					Humanoid:EquipTool(
						tool
					)

				end)
			end

			return tool
		end
	end

	---------------------------------------------------------------
	-- Любой Tool.
	---------------------------------------------------------------

	local equipped =
		currentTool()

	if equipped then
		return equipped
	end

	local backpack =
		LocalPlayer:
			FindFirstChildOfClass(
				"Backpack"
			)

	if backpack then

		local tool =
			backpack:
				FindFirstChildOfClass(
					"Tool"
				)

		if tool then

			pcall(function()

				Humanoid:EquipTool(tool)

			end)

			return tool
		end
	end

	return nil
end

---------------------------------------------------------------------
-- FIRE
---------------------------------------------------------------------

local function fireWeapon()

	if not AimPosition then
		return
	end

	---------------------------------------------------------------
	-- Не стреляем пока камера ещё только доворачивается.
	---------------------------------------------------------------

	local angle =
		getCameraAngle(
			AimPosition
		)

	if angle
		> CONFIG.FireAimToleranceDegrees then

		return
	end

	if os.clock()
		- LastShotTime
		< CONFIG.FireDelay then

		return
	end

	local tool =
		currentTool()
		or equipBestTool()

	if not tool then
		return
	end

	if not tool.Enabled then
		return
	end

	LastShotTime =
		os.clock()

	pcall(function()

		tool:Activate()

	end)
end

---------------------------------------------------------------------
-- CLEAR TARGET
---------------------------------------------------------------------

local function clearTarget()

	Target = nil

	AimPosition = nil

	LastSeenPosition = nil

	Waypoints = {}
end

---------------------------------------------------------------------
-- TARGET PROCESS
---------------------------------------------------------------------

local function processTarget(
	player: Player
): boolean

	if not Root then
		return false
	end

	---------------------------------------------------------------
	-- Если вдруг игрок стал тиммейтом.
	---------------------------------------------------------------

	if not isEnemy(player) then

		clearTarget()

		return false
	end

	local character,
		_,
		targetRoot =
		getCharacterData(player)

	if not character then

		clearTarget()

		return false
	end

	local distance =
		(
			targetRoot.Position
			- Root.Position
		).Magnitude

	---------------------------------------------------------------
	-- VISIBLE
	---------------------------------------------------------------

	if canSee(character) then

		LastSeenPosition =
			targetRoot.Position

		LastSeenTime =
			os.clock()

		AimPosition =
			calculateAimPosition(
				character,
				targetRoot
			)

		-------------------------------------------------------------
		-- TARGET FAR AWAY
		-------------------------------------------------------------

		if distance
			> CONFIG.AttackRange then

			moveTo(
				targetRoot.Position
			)

			return true
		end

		-------------------------------------------------------------
		-- COMBAT RANGE
		-------------------------------------------------------------

		if distance
			> CONFIG.StopDistance then

			---------------------------------------------------------
			-- Продолжаем бежать к противнику
			-- одновременно с aim/fire.
			---------------------------------------------------------

			moveTo(
				targetRoot.Position
			)

		else

			stopMovement()
		end

		-------------------------------------------------------------
		-- Стрельба будет только после того,
		-- как камера доведётся.
		-------------------------------------------------------------

		fireWeapon()

		return true
	end

	---------------------------------------------------------------
	-- PLAYER BEHIND WALL
	---------------------------------------------------------------

	AimPosition = nil

	if LastSeenPosition
		and os.clock()
			- LastSeenTime
			<= CONFIG.LostTargetTime then

		moveTo(
			LastSeenPosition
		)

		return true
	end

	clearTarget()

	return false
end

---------------------------------------------------------------------
-- DETECTION UPDATE
---------------------------------------------------------------------

local function updateDetection()

	if os.clock()
		- LastDetectionTime
		< CONFIG.DetectionInterval then

		return
	end

	LastDetectionTime =
		os.clock()

	---------------------------------------------------------------
	-- Если текущая цель ещё валидна,
	-- не обязательно каждый тик её менять.
	---------------------------------------------------------------

	if Target
		and isEnemy(Target) then

		local character =
			Target.Character

		if character then

			local humanoid =
				character:
					FindFirstChildOfClass(
						"Humanoid"
					)

			if humanoid
				and humanoid.Health > 0 then

				return
			end
		end
	end

	Target =
		findTarget()
end

---------------------------------------------------------------------
-- AI UPDATE
---------------------------------------------------------------------

local function updateAI()

	if not Character
		or not Character.Parent
		or not Humanoid
		or not Root then

		return
	end

	if Humanoid.Health <= 0 then

		AimPosition = nil

		return
	end

	---------------------------------------------------------------
	-- TARGET
	---------------------------------------------------------------

	updateDetection()

	if Target then

		if processTarget(
			Target
		) then

			return
		end
	end

	---------------------------------------------------------------
	-- NO TARGET
	--
	-- Камера сама сканирует 360,
	-- персонаж сам патрулирует.
	---------------------------------------------------------------

	AimPosition = nil

	patrol()
end

---------------------------------------------------------------------
-- CHARACTER ADDED
---------------------------------------------------------------------

LocalPlayer.CharacterAdded:
	Connect(function(character)

		task.wait(0.3)

		setupCharacter(
			character
		)

	end)

if LocalPlayer.Character then

	task.spawn(function()

		setupCharacter(
			LocalPlayer.Character
		)

	end)
end

---------------------------------------------------------------------
-- MAIN LOOP
---------------------------------------------------------------------

task.spawn(function()

	while true do

		local success, err =
			pcall(
				updateAI
			)

		if not success then

			warn(
				"[AutoBot]",
				err
			)
		end

		task.wait(
			CONFIG.ThinkInterval
		)
	end
end)

print("[AutoBot] loaded")
