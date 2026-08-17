--!strict

-- AutoBot.client.lua
--
-- StarterPlayer
-- └── StarterPlayerScripts
--     └── AutoBot.client.lua
--
-- НЕ использует:
--   HumanoidRootPart.CFrame
--   WalkSpeed modification
--   VirtualInputManager
--   firesignal
--   getgenv
--
-- Использует:
--   PathfindingService
--   Humanoid:MoveTo()
--   Workspace:Raycast()
--   Camera.CFrame для клиентской камеры
--   Tool:Activate()

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

	ThinkInterval = 0.05,
	DetectionInterval = 0.08,

	DetectionRadius = 450,

	IgnoreSameTeam = true,

	LostTargetTime = 4,

	-----------------------------------------------------------------
	-- AIM
	-----------------------------------------------------------------

	-- Ширина области поиска цели относительно камеры.
	AimFOVDegrees = 170,

	-- Чем выше — тем быстрее камера поворачивается.
	CameraAimSpeed = 18,

	-- Реальный визуальный FOV камеры.
	-- Можешь поставить nil, чтобы вообще его не менять.
	CameraFieldOfView = nil,

	PreferHead = true,

	HeadAimChance = 0.85,

	-----------------------------------------------------------------
	-- COMBAT
	-----------------------------------------------------------------

	AttackRange = 160,

	-- Насколько близко подходить.
	StopDistance = 35,

	FireDelay = 0.11,

	-----------------------------------------------------------------
	-- PATHFINDING
	-----------------------------------------------------------------

	RepathInterval = 0.35,

	TargetRepathDistance = 6,

	WaypointReachDistance = 4,

	AgentRadius = 2,

	AgentHeight = 5,

	AgentCanJump = true,

	AgentCanClimb = false,

	-----------------------------------------------------------------
	-- PATROL
	-----------------------------------------------------------------

	PatrolFolder = "PatrolPoints",

	RandomPatrolRadius = 220,

	PatrolPause = 0.5,

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

	-----------------------------------------------------------------
	-- OPTIONAL AUTO BUY
	-----------------------------------------------------------------

	AutoBuy = true,

	BuyDelay = 1.5,

	BuyPriority = {
		"AWP",
		"AK47",
		"M4A1",
		"M4A4",
		"Galil",
		"Famas",
		"P90",
		"MP5",
		"Deagle",
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

local LastDetection = 0

---------------------------------------------------------------------
-- AIM
---------------------------------------------------------------------

local AimPosition: Vector3? = nil

local LastShot = 0

---------------------------------------------------------------------
-- PATH
---------------------------------------------------------------------

local Waypoints = {}
local WaypointIndex = 1

local LastPathPosition: Vector3? = nil
local LastPathTime = 0

---------------------------------------------------------------------
-- PATROL
---------------------------------------------------------------------

local SpawnPosition: Vector3? = nil

local PatrolPoints = {}

local PatrolIndex = 1

local RandomPatrolPosition: Vector3? = nil

local NextPatrolTime = 0

---------------------------------------------------------------------
-- UTILITY
---------------------------------------------------------------------

local function normalize(value: any): string
	return string.lower(tostring(value or ""))
end

---------------------------------------------------------------------
-- CHARACTER DATA
---------------------------------------------------------------------

local function getPlayerCharacter(player: Player)

	local character = player.Character

	if not character then
		return nil
	end

	local humanoid =
		character:FindFirstChildOfClass("Humanoid")

	local root =
		character:FindFirstChild("HumanoidRootPart")

	if not humanoid then
		return nil
	end

	if not root
		or not root:IsA("BasePart") then
		return nil
	end

	if humanoid.Health <= 0 then
		return nil
	end

	return character, humanoid, root
end

---------------------------------------------------------------------
-- LOCAL CHARACTER SETUP
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
	-- ВАЖНО:
	--
	-- WalkSpeed НЕ меняем.
	-- Root.CFrame НЕ меняем.
	---------------------------------------------------------------

	Humanoid.AutoRotate = true

	SpawnPosition = Root.Position

	Target = nil

	AimPosition = nil

	LastSeenPosition = nil

	Waypoints = {}

	RandomPatrolPosition = nil

	---------------------------------------------------------------
	-- FOV камеры менять необязательно.
	---------------------------------------------------------------

	local camera = Workspace.CurrentCamera

	if camera
		and CONFIG.CameraFieldOfView then

		camera.FieldOfView =
			CONFIG.CameraFieldOfView
	end

	print("[AutoBot] character ready")
end

---------------------------------------------------------------------
-- ENEMY
---------------------------------------------------------------------

local function isEnemy(player: Player): boolean

	if player == LocalPlayer then
		return false
	end

	if not CONFIG.IgnoreSameTeam then
		return true
	end

	if LocalPlayer.Team
		and player.Team
		and LocalPlayer.Team == player.Team then

		return false
	end

	return true
end

---------------------------------------------------------------------
-- RAYCAST
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
			+ Vector3.new(0, 2, 0)
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

	local targetPart =
		character:FindFirstChild("Head")
		or character:FindFirstChild("HumanoidRootPart")

	if not targetPart
		or not targetPart:IsA("BasePart") then

		return false
	end

	local result =
		Workspace:Raycast(

			origin,

			targetPart.Position - origin,

			getRaycastParams()
		)

	if not result then
		return false
	end

	return result.Instance:IsDescendantOf(
		character
	)
end

---------------------------------------------------------------------
-- CAMERA ANGLE
---------------------------------------------------------------------

local function getCameraAngle(
	position: Vector3
): number

	local camera =
		Workspace.CurrentCamera

	if not camera then
		return math.huge
	end

	local difference =
		position - camera.CFrame.Position

	if difference.Magnitude <= 0.01 then
		return 0
	end

	local targetDirection =
		difference.Unit

	local dot =
		math.clamp(

			camera.CFrame.LookVector:
				Dot(targetDirection),

			-1,
			1
		)

	return math.deg(
		math.acos(dot)
	)
end

---------------------------------------------------------------------
-- TARGET SEARCH
---------------------------------------------------------------------

local function findTarget(): Player?

	if not Root then
		return nil
	end

	local bestPlayer: Player? = nil
	local bestScore = math.huge

	local maxAngle =
		CONFIG.AimFOVDegrees / 2

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		if not isEnemy(player) then
			continue
		end

		local character,
			_,
			targetRoot =
			getPlayerCharacter(player)

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

		local aimPart =
			character:FindFirstChild("Head")
			or targetRoot

		if not aimPart
			or not aimPart:IsA("BasePart") then
			continue
		end

		local angle =
			getCameraAngle(
				aimPart.Position
			)

		if angle > maxAngle then
			continue
		end

		if not canSee(character) then
			continue
		end

		-------------------------------------------------------------
		-- Ближе к центру камеры = приоритетнее.
		-------------------------------------------------------------

		local score =
			angle * 3
			+ distance * 0.02

		if score < bestScore then

			bestScore = score

			bestPlayer = player
		end
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
-- CAMERA CONTROLLER
---------------------------------------------------------------------
--
-- Здесь изменяется ТОЛЬКО камера.
--
-- Character / Root не вращаем.
---------------------------------------------------------------------

RunService.RenderStepped:Connect(
	function(dt)

		if not AimPosition then
			return
		end

		local camera =
			Workspace.CurrentCamera

		if not camera then
			return
		end

		local current =
			camera.CFrame

		local wanted =
			CFrame.lookAt(
				current.Position,
				AimPosition
			)

		local alpha =
			1
			- math.exp(
				-CONFIG.CameraAimSpeed
				* dt
			)

		camera.CFrame =
			current:Lerp(
				wanted,
				alpha
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

	LastPathPosition =
		destination

	LastPathTime =
		os.clock()

	return true
end

---------------------------------------------------------------------
-- REPATH
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

	if LastPathPosition then

		local moved =
			(
				LastPathPosition
				- destination
			).Magnitude

		if moved
			>= CONFIG.TargetRepathDistance then

			return true
		end
	end

	return false
end

---------------------------------------------------------------------
-- FOLLOW PATH
---------------------------------------------------------------------

local function followPath()

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

	if waypoint.Action
		== Enum.PathWaypointAction.Jump then

		Humanoid.Jump = true
	end

	---------------------------------------------------------------
	-- Roblox сам вращает Character.
	---------------------------------------------------------------

	Humanoid.AutoRotate = true

	Humanoid:MoveTo(
		waypoint.Position
	)

	return true
end

---------------------------------------------------------------------
-- MOVE
---------------------------------------------------------------------

local function moveTo(
	destination: Vector3
)

	if not Humanoid then
		return
	end

	---------------------------------------------------------------
	-- Не меняем WalkSpeed.
	---------------------------------------------------------------

	Humanoid.AutoRotate = true

	if needsRepath(destination) then

		if not computePath(destination) then

			---------------------------------------------------------
			-- Fallback:
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

	if not Root
		or not Humanoid then

		return
	end

	Humanoid.AutoRotate = true

	Humanoid:MoveTo(
		Root.Position
	)
end

---------------------------------------------------------------------
-- PATROL POINTS
---------------------------------------------------------------------

local function loadPatrolPoints()

	table.clear(
		PatrolPoints
	)

	local folder =
		Workspace:FindFirstChild(
			CONFIG.PatrolFolder
		)

	if not folder then
		return
	end

	for _, object in ipairs(
		folder:GetChildren()
	) do

		if object:IsA("BasePart") then

			table.insert(
				PatrolPoints,
				object
			)
		end
	end

	table.sort(
		PatrolPoints,

		function(a, b)
			return a.Name < b.Name
		end
	)
end

---------------------------------------------------------------------
-- RANDOM PATROL LOCATION
---------------------------------------------------------------------

local function createRandomDestination(): Vector3?

	if not Root then
		return nil
	end

	local base =
		SpawnPosition
		or Root.Position

	for _ = 1, 8 do

		local radius =
			CONFIG.RandomPatrolRadius

		local candidate =
			base
			+ Vector3.new(

				math.random(
					-radius,
					radius
				),

				0,

				math.random(
					-radius,
					radius
				)
			)

		-------------------------------------------------------------
		-- Find ground.
		-------------------------------------------------------------

		local result =
			Workspace:Raycast(

				candidate
					+ Vector3.new(
						0,
						150,
						0
					),

				Vector3.new(
					0,
					-400,
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

	if not Root then
		return
	end

	if os.clock()
		< NextPatrolTime then

		return
	end

	---------------------------------------------------------------
	-- MANUAL PATROL POINTS
	---------------------------------------------------------------

	if #PatrolPoints > 0 then

		local point =
			PatrolPoints[
				PatrolIndex
			]

		if not point then

			PatrolIndex = 1

			return
		end

		if (
			Root.Position
			- point.Position
		).Magnitude <= 5 then

			PatrolIndex += 1

			if PatrolIndex
				> #PatrolPoints then

				PatrolIndex = 1
			end

			Waypoints = {}

			NextPatrolTime =
				os.clock()
				+ CONFIG.PatrolPause

			return
		end

		moveTo(
			point.Position
		)

		return
	end

	---------------------------------------------------------------
	-- RANDOM PATROL
	---------------------------------------------------------------

	if not RandomPatrolPosition then

		RandomPatrolPosition =
			createRandomDestination()

		Waypoints = {}
	end

	if not RandomPatrolPosition then
		return
	end

	if (
		Root.Position
		- RandomPatrolPosition
	).Magnitude <= 6 then

		RandomPatrolPosition =
			nil

		Waypoints = {}

		NextPatrolTime =
			os.clock()
			+ CONFIG.PatrolPause

		return
	end

	moveTo(
		RandomPatrolPosition
	)
end

---------------------------------------------------------------------
-- TOOL SEARCH
---------------------------------------------------------------------

local function findTool(
	weaponName: string
): Tool?

	local wanted =
		normalize(
			weaponName
		)

	local function search(
		parent: Instance?
	): Tool?

		if not parent then
			return nil
		end

		for _, object
			in ipairs(
				parent:GetChildren()
			) do

			if not object:IsA("Tool") then
				continue
			end

			local name =
				normalize(
					object.Name
				)

			if name == wanted
				or string.find(
					name,
					wanted,
					1,
					true
				) then

				return object
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
		FindFirstChildOfClass(
			"Tool"
		)
end

---------------------------------------------------------------------
-- EQUIP WEAPON
---------------------------------------------------------------------

local function equipBestWeapon(): Tool?

	if not Humanoid then
		return nil
	end

	for _, weapon
		in ipairs(
			CONFIG.WeaponPriority
		) do

		local tool =
			findTool(
				weapon
			)

		if tool then

			if tool.Parent
				~= Character then

				Humanoid:
					EquipTool(
						tool
					)
			end

			return tool
		end
	end

	---------------------------------------------------------------
	-- Any Tool fallback.
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

			Humanoid:
				EquipTool(
					tool
				)

			return tool
		end
	end

	return nil
end

---------------------------------------------------------------------
-- FIRE
---------------------------------------------------------------------

local function fire()

	if os.clock()
		- LastShot
		< CONFIG.FireDelay then

		return
	end

	local tool =
		currentTool()
		or equipBestWeapon()

	if not tool then
		return
	end

	if not tool.Enabled then
		return
	end

	LastShot =
		os.clock()

	---------------------------------------------------------------
	-- Обычная Roblox Tool activation.
	---------------------------------------------------------------

	tool:Activate()
end

---------------------------------------------------------------------
-- BUY ADAPTER
---------------------------------------------------------------------
--
-- Для твоего place создай:
--
-- ReplicatedStorage
-- └── BuyWeapon (BindableFunction)
--
-- Или замени этот код вызовом своего ShopController.
---------------------------------------------------------------------

local function buyWeapon(
	weaponName: string
): boolean

	local buyFunction =
		ReplicatedStorage:
			FindFirstChild(
				"BuyWeapon"
			)

	if not buyFunction
		or not buyFunction:IsA(
			"BindableFunction"
		) then

		return false
	end

	local success, result =
		pcall(function()

			return buyFunction:
				Invoke(
					weaponName
				)
		end)

	return success
		and result ~= false
end

---------------------------------------------------------------------
-- AUTO BUY
---------------------------------------------------------------------

local function autoBuy()

	if not CONFIG.AutoBuy then

		equipBestWeapon()

		return
	end

	for _, weapon
		in ipairs(
			CONFIG.BuyPriority
		) do

		if findTool(weapon) then
			continue
		end

		if buyWeapon(weapon) then

			task.wait(0.2)

			if findTool(weapon) then

				print(
					"[AutoBot] bought:",
					weapon
				)

				break
			end
		end
	end

	equipBestWeapon()
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
-- PROCESS TARGET
---------------------------------------------------------------------

local function processTarget(
	player: Player
): boolean

	if not Root then
		return false
	end

	local character,
		_,
		targetRoot =
		getPlayerCharacter(
			player
		)

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
		-- ATTACK
		-------------------------------------------------------------

		if distance
			<= CONFIG.AttackRange then

			if distance
				> CONFIG.StopDistance then

				moveTo(
					targetRoot.Position
				)

			else

				stopMovement()
			end

			fire()

			return true
		end

		-------------------------------------------------------------
		-- CHASE
		-------------------------------------------------------------

		moveTo(
			targetRoot.Position
		)

		return true
	end

	---------------------------------------------------------------
	-- LOS LOST
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
-- DETECTION
---------------------------------------------------------------------

local function updateDetection()

	if os.clock()
		- LastDetection
		< CONFIG.DetectionInterval then

		return
	end

	LastDetection =
		os.clock()

	local found =
		findTarget()

	if found then

		Target = found
	end
end

---------------------------------------------------------------------
-- UPDATE AI
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
	-- Не меняем WalkSpeed.
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
	-- No target:
	---------------------------------------------------------------

	AimPosition = nil

	patrol()
end

---------------------------------------------------------------------
-- CHARACTER SPAWN
---------------------------------------------------------------------

local function characterAdded(
	character: Model
)

	setupCharacter(
		character
	)

	loadPatrolPoints()

	task.delay(
		CONFIG.BuyDelay,

		function()

			if Humanoid
				and Humanoid.Health > 0 then

				autoBuy()
			end
		end
	)
end

---------------------------------------------------------------------
-- EVENTS
---------------------------------------------------------------------

LocalPlayer.CharacterAdded:
	Connect(
		characterAdded
	)

if LocalPlayer.Character then

	task.spawn(
		characterAdded,
		LocalPlayer.Character
	)
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
