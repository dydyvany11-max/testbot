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

	---------------------------------------------------------------
	-- LOOP
	---------------------------------------------------------------

	ThinkInterval = 0.04,
	DetectionInterval = 0.08,

	---------------------------------------------------------------
	-- TARGETS
	---------------------------------------------------------------

	TeamCheck = true,

	GlobalChaseRadius = 5000,

	-- Если во время погони рядом появился видимый противник,
	-- сразу временно переключаемся на него.
	InterruptRadius = 160,

	---------------------------------------------------------------
	-- AIM
	---------------------------------------------------------------

	AimHead = true,

	-- Плавность камеры.
	AimSpeed = 24,

	-- Сглаживание самой позиции головы.
	AimPositionSpeed = 20,

	-- Насколько точно камера должна смотреть перед выстрелом.
	FireAimTolerance = 2,

	---------------------------------------------------------------
	-- COMBAT
	---------------------------------------------------------------

	AttackRange = 250,

	-- Пока дальше этого расстояния — бежим.
	StopToShootDistance = 55,

	AimSettleTime = 0.10,

	FireDelay = 0.11,

	---------------------------------------------------------------
	-- PATHFINDING
	---------------------------------------------------------------

	AgentRadius = 2,
	AgentHeight = 5,

	AgentCanJump = true,
	AgentCanClimb = false,

	WaypointReachDistance = 4,

	RepathInterval = 0.45,

	RepathDistance = 7,

	---------------------------------------------------------------
	-- PATROL
	---------------------------------------------------------------

	PatrolMinDistance = 60,
	PatrolMaxDistance = 140,

	PatrolTimeout = 8,

	---------------------------------------------------------------
	-- BUY
	---------------------------------------------------------------

	AutoBuy = true,
	BuyDelay = 1.5,

	---------------------------------------------------------------
	-- DEBUG
	---------------------------------------------------------------

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

		local module =
			require(
				LocalPlayer
					:WaitForChild("PlayerScripts")
					:WaitForChild("PlayerModule")
			)

		Controls =
			module:GetControls()

		Controls:Disable()
	end)
end

---------------------------------------------------------------------
-- TARGET STATE
---------------------------------------------------------------------

-- Основная цель:
-- к ней бот продолжает идти через комнаты.
local ChaseTarget = nil

-- Временная цель:
-- видимый противник, которого сейчас надо убить.
local CombatTarget = nil

local LastDetection = 0

---------------------------------------------------------------------
-- AIM STATE
---------------------------------------------------------------------

local AimPosition = nil

local SmoothedAimPosition = nil

local AimSettlingSince = nil

---------------------------------------------------------------------
-- FIRE STATE
---------------------------------------------------------------------

local LastShot = 0

local LastFireDebug = 0

---------------------------------------------------------------------
-- PATH STATE
---------------------------------------------------------------------

local Waypoints = {}

local WaypointIndex = 1

local LastPathDestination = nil

local LastPathTime = 0

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

	ChaseTarget = nil
	CombatTarget = nil

	AimPosition = nil
	SmoothedAimPosition = nil

	AimSettlingSince = nil

	Waypoints = {}

	LastPathDestination = nil

	PatrolDestination = nil

	disableControls()

	if CONFIG.Debug then

		print(
			"[BOT] READY",
			"speed:",
			Humanoid.WalkSpeed
		)
	end
end

---------------------------------------------------------------------
-- PLAYER DATA
---------------------------------------------------------------------

local function getPlayerData(player)

	if not player then
		return nil
	end

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

	if not player then
		return false
	end

	if player == LocalPlayer then
		return false
	end

	if not CONFIG.TeamCheck then
		return true
	end

	---------------------------------------------------------------
	-- Standard Roblox Teams
	---------------------------------------------------------------

	if LocalPlayer.Team
		and player.Team
		and LocalPlayer.Team == player.Team then

		return false
	end

	---------------------------------------------------------------
	-- Team attribute
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
	-- Side attribute
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
-- DISTANCE
---------------------------------------------------------------------

local function distanceTo(player)

	if not Root then
		return math.huge
	end

	local character,
		humanoid,
		targetRoot =
		getPlayerData(player)

	if not character
		or not humanoid
		or not targetRoot then

		return math.huge
	end

	return (
		targetRoot.Position
		- Root.Position
	).Magnitude
end

---------------------------------------------------------------------
-- RAYCAST
---------------------------------------------------------------------

local function createRayParams()

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	if Character then

		params.FilterDescendantsInstances = {
			Character
		}
	end

	params.IgnoreWater = true

	return params
end

---------------------------------------------------------------------
-- LINE OF SIGHT
---------------------------------------------------------------------

local function canSee(character)

	if not Head
		or not character then

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

				createRayParams()
			)

		if result
			and result.Instance:
				IsDescendantOf(
					character
				) then

			return true
		end
	end

	return false
end

---------------------------------------------------------------------
-- TARGET VALID
---------------------------------------------------------------------

local function targetValid(player)

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

	return (
		targetRoot.Position
		- Root.Position
	).Magnitude
		<= CONFIG.GlobalChaseRadius
end

---------------------------------------------------------------------
-- FIND GLOBAL CHASE TARGET
---------------------------------------------------------------------

local function findNearestEnemy()

	if not Root then
		return nil
	end

	local best =
		nil

	local bestDistance =
		math.huge

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		if not isEnemy(player) then
			continue
		end

		local distance =
			distanceTo(player)

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
-- FIND IMMEDIATE VISIBLE THREAT
---------------------------------------------------------------------
--
-- Вот эта функция делает то, что ты попросил.
--
-- Даже если бот преследует другого игрока,
-- любой близкий видимый противник может стать CombatTarget.
---------------------------------------------------------------------

local function findVisibleThreat()

	if not Root then
		return nil
	end

	local best =
		nil

	local bestDistance =
		math.huge

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		if not isEnemy(player) then
			continue
		end

		local character,
			humanoid,
			targetRoot =
			getPlayerData(player)

		if not character
			or not humanoid
			or not targetRoot then

			continue
		end

		local distance =
			(
				targetRoot.Position
				- Root.Position
			).Magnitude

		---------------------------------------------------------
		-- Только непосредственная угроза.
		---------------------------------------------------------

		if distance
			> CONFIG.InterruptRadius then

			continue
		end

		---------------------------------------------------------
		-- Обязательный прямой контакт.
		---------------------------------------------------------

		if not canSee(character) then
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
			and targetHead:IsA(
				"BasePart"
			) then

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

	local delta =
		position
		- camera.CFrame.Position

	if delta.Magnitude
		<= 0.001 then

		return 0
	end

	local dot =
		math.clamp(

			camera.CFrame.LookVector:
				Dot(delta.Unit),

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
-- Камера меняется ТОЛЬКО когда есть видимая боевая цель.
--
-- Никакого автоматического 360-spin.
---------------------------------------------------------------------

RunService:BindToRenderStep(

	"AutoBotCamera",

	Enum.RenderPriority.Camera.Value + 1,

	function(dt)

		if not AimPosition then
			return
		end

		local camera =
			Workspace.CurrentCamera

		if not camera then
			return
		end

		---------------------------------------------------------
		-- Smooth moving Head.
		---------------------------------------------------------

		if not SmoothedAimPosition then

			SmoothedAimPosition =
				AimPosition

		else

			local positionAlpha =
				1
				- math.exp(
					-CONFIG.AimPositionSpeed
					* dt
				)

			SmoothedAimPosition =
				SmoothedAimPosition:
					Lerp(
						AimPosition,
						positionAlpha
					)
		end

		---------------------------------------------------------
		-- Smooth camera.
		---------------------------------------------------------

		local current =
			camera.CFrame

		local desired =
			CFrame.lookAt(
				current.Position,
				SmoothedAimPosition
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
	end
)

---------------------------------------------------------------------
-- STOP
---------------------------------------------------------------------

local function stopMovement()

	if Humanoid then

		Humanoid:Move(
			Vector3.zero,
			false
		)
	end
end

---------------------------------------------------------------------
-- COMPUTE PATH
---------------------------------------------------------------------

local function computePath(
	destination
)

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
			warn("[BOT PATH]", err)
		end

		Waypoints = {}

		return false
	end

	if path.Status
		~= Enum.PathStatus.Success then

		if CONFIG.Debug then

			warn(
				"[BOT PATH]",
				path.Status
			)
		end

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
	destination
)

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
-- DIRECT MOVE
---------------------------------------------------------------------

local function directMove(destination)

	if not Root
		or not Humanoid then

		return
	end

	local delta =
		destination
		- Root.Position

	local flat =
		Vector3.new(
			delta.X,
			0,
			delta.Z
		)

	if flat.Magnitude
		<= 0.1 then

		stopMovement()

		return
	end

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

	local waypoint =
		Waypoints[
			WaypointIndex
		]

	if not waypoint then
		return false
	end

	local delta =
		waypoint.Position
		- Root.Position

	local flat =
		Vector3.new(
			delta.X,
			0,
			delta.Z
		)

	-------------------------------------------------------------
	-- waypoint reached
	-------------------------------------------------------------

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

		delta =
			waypoint.Position
			- Root.Position

		flat =
			Vector3.new(
				delta.X,
				0,
				delta.Z
			)
	end

	-------------------------------------------------------------
	-- Pathfinding-requested jump only.
	-------------------------------------------------------------

	if waypoint.Action
		== Enum.PathWaypointAction.Jump then

		Humanoid.Jump =
			true
	end

	-------------------------------------------------------------
	-- movement
	-------------------------------------------------------------

	if flat.Magnitude > 0.05 then

		Humanoid.AutoRotate =
			true

		Humanoid:Move(
			flat.Unit,
			false
		)

		return true
	end

	return false
end

---------------------------------------------------------------------
-- MOVE
---------------------------------------------------------------------

local function moveTo(destination)

	if not Root
		or not Humanoid then

		return
	end

	if needsRepath(
		destination
	) then

		if not computePath(
			destination
		) then

			directMove(
				destination
			)

			return
		end
	end

	if not followPath() then

		Waypoints = {}

		directMove(
			destination
		)
	end
end

---------------------------------------------------------------------
-- PATROL DESTINATION
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
						100,
						0
					),

				Vector3.new(
					0,
					-250,
					0
				),

				createRayParams()
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

	AimPosition = nil
	SmoothedAimPosition = nil

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

		Waypoints = {}
	end

	if PatrolDestination then

		moveTo(
			PatrolDestination
		)
	end
end

---------------------------------------------------------------------
-- WEAPONS
---------------------------------------------------------------------

local function getEquippedTool()

	if not Character then
		return nil
	end

	for _, child in ipairs(
		Character:GetChildren()
	) do

		if child:IsA("Tool") then
			return child
		end
	end

	return nil
end

---------------------------------------------------------------------
-- ALL TOOLS
---------------------------------------------------------------------

local function getAllTools()

	local result = {}

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
					result,
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

	return result
end

---------------------------------------------------------------------
-- WEAPON PRIORITY
---------------------------------------------------------------------

local WEAPON_PRIORITY = {

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
}

local function weaponScore(tool)

	local toolName =
		string.lower(
			tool.Name
		)

	for index, name in ipairs(
		WEAPON_PRIORITY
	) do

		name =
			string.lower(name)

		if toolName == name
			or string.find(
				toolName,
				name,
				1,
				true
			) then

			return index
		end
	end

	return 999
end

---------------------------------------------------------------------
-- EQUIP BEST
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
					"[BOT WEAPON]",
					tool.Name
				)
			end

			return tool
		end
	end

	return nil
end

---------------------------------------------------------------------
-- LOCAL FIRE
---------------------------------------------------------------------

local FIRE_NAMES = {

	"Fire",
	"Shoot",

	"FireWeapon",
	"ShootWeapon",

	"FireGun",
	"ShootGun",

	"PrimaryFire",
	"PrimaryAttack",
}

local function tryLocalFire(
	parent,
	targetPosition
)

	if not parent then
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

	-------------------------------------------------------------
	-- Must actually aim first.
	-------------------------------------------------------------

	if cameraAngleTo(
		targetPosition
	) > CONFIG.FireAimTolerance then

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
				"[BOT FIRE] no weapon"
			)
		end

		return false
	end

	-------------------------------------------------------------
	-- Custom local fire.
	-------------------------------------------------------------

	if tryLocalFire(
		tool,
		targetPosition
	) then

		LastShot =
			os.clock()

		return true
	end

	-------------------------------------------------------------
	-- Standard Tool.
	-------------------------------------------------------------

	if not tool.Enabled then
		return false
	end

	local success, err =
		pcall(function()

			tool:Activate()
		end)

	if CONFIG.Debug
		and os.clock()
			- LastFireDebug > 0.5 then

		LastFireDebug =
			os.clock()

		print(
			"[BOT FIRE]",
			tool.Name,
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
		0.04,

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
-- BUY ADAPTERS
---------------------------------------------------------------------

local BUY_NAMES = {

	"BuyWeapon",
	"PurchaseWeapon",

	"BuyItem",
	"PurchaseItem",
}

local function findBuyAdapter()

	local roots = {

		ReplicatedStorage,

		LocalPlayer:
			FindFirstChild("PlayerGui"),

		LocalPlayer:
			FindFirstChild("PlayerScripts"),
	}

	for _, rootObject in ipairs(
		roots
	) do

		if not rootObject then
			continue
		end

		for _, name in ipairs(
			BUY_NAMES
		) do

			local object =
				rootObject:
					FindFirstChild(
						name,
						true
					)

			if object
				and (
					object:IsA(
						"BindableEvent"
					)
					or object:IsA(
						"BindableFunction"
					)
				) then

				return object
			end
		end
	end

	return nil
end

local function buyWeapon(name)

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

---------------------------------------------------------------------
-- AUTO BUY
---------------------------------------------------------------------

local function autoBuy()

	if not CONFIG.AutoBuy then
		return
	end

	-------------------------------------------------------------
	-- Deagle
	-------------------------------------------------------------

	for _, name in ipairs({

		"Deagle",
		"Desert Eagle",

	}) do

		if buyWeapon(name) then

			if CONFIG.Debug then
				print("[BUY]", name)
			end

			break
		end
	end

	task.wait(0.1)

	-------------------------------------------------------------
	-- AK / M4
	-------------------------------------------------------------

	for _, name in ipairs({

		"AK47",
		"AK-47",

		"M4A1",
		"M4A4",
		"M4",

	}) do

		if buyWeapon(name) then

			if CONFIG.Debug then
				print("[BUY]", name)
			end

			break
		end
	end

	task.wait(0.15)

	equipBestWeapon()
end

---------------------------------------------------------------------
-- UPDATE TARGETS
---------------------------------------------------------------------

local function updateTargets()

	if os.clock()
		- LastDetection
		< CONFIG.DetectionInterval then

		return
	end

	LastDetection =
		os.clock()

	-------------------------------------------------------------
	-- MAIN CHASE TARGET
	-------------------------------------------------------------

	if not targetValid(
		ChaseTarget
	) then

		ChaseTarget =
			findNearestEnemy()

		Waypoints = {}

		if CONFIG.Debug
			and ChaseTarget then

			print(
				"[CHASE]",
				ChaseTarget.Name
			)
		end
	end

	-------------------------------------------------------------
	-- DIRECT VISIBLE THREAT
	-------------------------------------------------------------

	local threat =
		findVisibleThreat()

	if threat then

		---------------------------------------------------------
		-- Сразу переключаем стрельбу.
		---------------------------------------------------------

		if threat
			~= CombatTarget then

			CombatTarget =
				threat

			AimSettlingSince =
				nil

			SmoothedAimPosition =
				nil

			Waypoints = {}

			if CONFIG.Debug then

				print(
					"[INTERRUPT]",
					threat.Name
				)
			end
		end

		return
	end

	-------------------------------------------------------------
	-- Нет близкого внезапного врага.
	--
	-- Если основная цель уже видима —
	-- она становится боевой.
	-------------------------------------------------------------

	if targetValid(
		ChaseTarget
	) then

		local character =
			ChaseTarget.Character

		if character
			and canSee(character) then

			if CombatTarget
				~= ChaseTarget then

				CombatTarget =
					ChaseTarget

				AimSettlingSince =
					nil

				SmoothedAimPosition =
					nil
			end

			return
		end
	end

	-------------------------------------------------------------
	-- Никого напрямую не видим.
	-------------------------------------------------------------

	CombatTarget =
		nil

	AimPosition =
		nil

	SmoothedAimPosition =
		nil

	AimSettlingSince =
		nil
end

---------------------------------------------------------------------
-- PROCESS COMBAT TARGET
---------------------------------------------------------------------

local function processCombatTarget(
	player
)

	if not targetValid(player) then
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

	-------------------------------------------------------------
	-- Must remain visible.
	-------------------------------------------------------------

	if not canSee(character) then
		return false
	end

	local distance =
		(
			targetRoot.Position
			- Root.Position
		).Magnitude

	local headPosition =
		getAimPosition(
			character,
			targetRoot
		)

	-------------------------------------------------------------
	-- CAMERA -> HEAD
	-------------------------------------------------------------

	AimPosition =
		headPosition

	-------------------------------------------------------------
	-- Still far:
	--
	-- run and simultaneously keep looking at head.
	-------------------------------------------------------------

	if distance
		> CONFIG.StopToShootDistance then

		AimSettlingSince =
			nil

		moveTo(
			targetRoot.Position
		)

		return true
	end

	-------------------------------------------------------------
	-- STOP TO SHOOT
	-------------------------------------------------------------

	stopMovement()

	-------------------------------------------------------------
	-- AIM SETTLING
	-------------------------------------------------------------

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

	-------------------------------------------------------------
	-- Accuracy
	-------------------------------------------------------------

	if cameraAngleTo(
		headPosition
	) > CONFIG.FireAimTolerance then

		return true
	end

	-------------------------------------------------------------
	-- Final LOS
	-------------------------------------------------------------

	if not canSee(character) then

		AimSettlingSince =
			nil

		return false
	end

	-------------------------------------------------------------
	-- FIRE HEAD
	-------------------------------------------------------------

	if distance
		<= CONFIG.AttackRange then

		fireWeapon(
			headPosition
		)
	end

	return true
end

---------------------------------------------------------------------
-- PROCESS CHASE TARGET
---------------------------------------------------------------------

local function processChaseTarget(
	player
)

	if not targetValid(player) then
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

	-------------------------------------------------------------
	-- Target is hidden:
	-- run through map toward current position.
	-------------------------------------------------------------

	AimPosition =
		nil

	SmoothedAimPosition =
		nil

	AimSettlingSince =
		nil

	moveTo(
		targetRoot.Position
	)

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

					-------------------------------------------------
					-- Update both layers of targets.
					-------------------------------------------------

					updateTargets()

					-------------------------------------------------
					-- Immediate visible enemy wins.
					-------------------------------------------------

					if CombatTarget then

						if processCombatTarget(
							CombatTarget
						) then

							return
						else

							CombatTarget =
								nil

							AimPosition =
								nil

							SmoothedAimPosition =
								nil
						end
					end

					-------------------------------------------------
					-- Continue chasing original target.
					-------------------------------------------------

					if ChaseTarget then

						if processChaseTarget(
							ChaseTarget
						) then

							return
						else

							ChaseTarget =
								nil
						end
					end

					-------------------------------------------------
					-- Nobody exists.
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
	end)
end

---------------------------------------------------------------------
-- READY
---------------------------------------------------------------------

print("[AutoBot] RUNNING")
