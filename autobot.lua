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
	-- AI
	---------------------------------------------------------------

	ThinkInterval = 0.025,
	DetectionInterval = 0.04,

	TeamCheck = true,

	-- Расстояние глобального поиска.
	GlobalChaseRadius = 10000,

	-- Видимый враг в этом радиусе может прервать погоню.
	InterruptRadius = 500,

	-- Не переключаться между двумя игроками каждую миллисекунду.
	ThreatSwitchCooldown = 0.18,
	ThreatSwitchMargin = 12,

	---------------------------------------------------------------
	-- AIM
	---------------------------------------------------------------

	AimSpeed = 55,

	AimPositionSpeed = 45,

	-- Стабильная точка примерно уровня головы.
	HeadOffsetY = 1.55,

	FireAimTolerance = 1.5,

	---------------------------------------------------------------
	-- CAMERA
	---------------------------------------------------------------

	-- Камера считается от HumanoidRootPart,
	-- а не от Head, поэтому running animation её не трясёт.
	CameraHeight = 1.9,

	---------------------------------------------------------------
	-- COMBAT
	---------------------------------------------------------------

	AttackRange = 350,

	-- До этого расстояния бежит.
	StopToShootDistance = 65,

	-- После остановки опять побежит только если враг отошёл дальше.
	ResumeChaseDistance = 82,

	-- Очень быстрое доведение.
	AimSettleTime = 0.035,

	FireDelay = 0.075,

	---------------------------------------------------------------
	-- PATHFINDING
	---------------------------------------------------------------

	AgentRadius = 2,
	AgentHeight = 5,

	AgentCanJump = true,
	AgentCanClimb = false,

	WaypointReachDistance = 5,

	RepathInterval = 0.40,

	RepathDistance = 7,

	---------------------------------------------------------------
	-- PATROL
	---------------------------------------------------------------

	PatrolMinDistance = 70,
	PatrolMaxDistance = 170,

	PatrolTimeout = 8,

	---------------------------------------------------------------
	-- BUY
	---------------------------------------------------------------

	AutoBuy = true,
	BuyDelay = 1.0,

	Debug = true,
}

---------------------------------------------------------------------
-- CHARACTER
---------------------------------------------------------------------

local Character = nil
local Humanoid = nil
local Root = nil

---------------------------------------------------------------------
-- CONTROLS
---------------------------------------------------------------------

local Controls = nil

local function disableNormalControls()

	if Controls then
		return
	end

	pcall(function()

		local PlayerModule =
			require(
				LocalPlayer
					:WaitForChild("PlayerScripts")
					:WaitForChild("PlayerModule")
			)

		Controls =
			PlayerModule:GetControls()

		Controls:Disable()

		if CONFIG.Debug then
			print("[BOT] controls disabled")
		end
	end)
end

---------------------------------------------------------------------
-- TARGET STATE
---------------------------------------------------------------------

-- Основной противник, которого преследуем через карту.
local ChaseTarget = nil

-- Враг, с которым прямо сейчас есть контакт.
local CombatTarget = nil

local LastDetection = 0
local LastThreatSwitch = 0

---------------------------------------------------------------------
-- AIM STATE
---------------------------------------------------------------------

local AimPosition = nil
local SmoothedAimPosition = nil

local CameraForward = Vector3.new(0, 0, -1)

local AimSettlingSince = nil

local FiringStance = false

---------------------------------------------------------------------
-- PATH STATE
---------------------------------------------------------------------

local Waypoints = {}
local WaypointIndex = 1

local LastPathDestination = nil
local LastPathTime = 0

---------------------------------------------------------------------
-- FIRE STATE
---------------------------------------------------------------------

local LastShot = 0
local LastFireDebug = 0

---------------------------------------------------------------------
-- PATROL STATE
---------------------------------------------------------------------

local PatrolDestination = nil
local PatrolCreated = 0

local RNG = Random.new()

---------------------------------------------------------------------
-- SETUP CHARACTER
---------------------------------------------------------------------

local function setupCharacter(character)

	Character = character

	Humanoid =
		character:WaitForChild("Humanoid")

	Root =
		character:WaitForChild("HumanoidRootPart")

	Humanoid.AutoRotate = true

	ChaseTarget = nil
	CombatTarget = nil

	AimPosition = nil
	SmoothedAimPosition = nil

	AimSettlingSince = nil
	FiringStance = false

	Waypoints = {}
	WaypointIndex = 1

	LastPathDestination = nil

	PatrolDestination = nil

	disableNormalControls()

	task.delay(0.1, function()

		local camera =
			Workspace.CurrentCamera

		if camera then

			if camera.CFrame.LookVector.Magnitude > 0.01 then
				CameraForward =
					camera.CFrame.LookVector.Unit
			end

			camera.CameraType =
				Enum.CameraType.Scriptable
		end
	end)

	if CONFIG.Debug then

		print(
			"[BOT] character ready",
			"WalkSpeed:",
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
			FindFirstChildOfClass("Humanoid")

	local root =
		character:
			FindFirstChild("HumanoidRootPart")

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
	-- Standard Roblox teams.
	---------------------------------------------------------------

	if LocalPlayer.Team
		and player.Team
		and LocalPlayer.Team == player.Team then

		return false
	end

	---------------------------------------------------------------
	-- Custom Team attribute.
	---------------------------------------------------------------

	local myTeam =
		LocalPlayer:GetAttribute("Team")

	local enemyTeam =
		player:GetAttribute("Team")

	if myTeam ~= nil
		and enemyTeam ~= nil
		and myTeam == enemyTeam then

		return false
	end

	---------------------------------------------------------------
	-- Custom Side attribute.
	---------------------------------------------------------------

	local mySide =
		LocalPlayer:GetAttribute("Side")

	local enemySide =
		player:GetAttribute("Side")

	if mySide ~= nil
		and enemySide ~= nil
		and mySide == enemySide then

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
-- RAYCAST PARAMS
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
-- LOS
---------------------------------------------------------------------

local function canSee(character)

	if not Root
		or not character then

		return false
	end

	local origin =
		Root.Position
		+ Vector3.new(
			0,
			CONFIG.HeadOffsetY,
			0
		)

	local parts = {

		character:
			FindFirstChild("Head"),

		character:
			FindFirstChild("HumanoidRootPart"),
	}

	for _, part in ipairs(parts) do

		if not part
			or not part:IsA("BasePart") then

			continue
		end

		local result =
			Workspace:Raycast(

				origin,

				part.Position
					- origin,

				createRayParams()
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
-- VALID TARGET
---------------------------------------------------------------------

local function targetValid(player)

	if not isEnemy(player) then
		return false
	end

	local character,
		humanoid,
		targetRoot =
		getPlayerData(player)

	if not character
		or not humanoid
		or not targetRoot
		or not Root then

		return false
	end

	return (
		targetRoot.Position
		- Root.Position
	).Magnitude
		<= CONFIG.GlobalChaseRadius
end

---------------------------------------------------------------------
-- FIND NEAREST GLOBAL ENEMY
---------------------------------------------------------------------

local function findNearestEnemy()

	if not Root then
		return nil
	end

	local best = nil
	local bestDistance = math.huge

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

		if distance < bestDistance then

			bestDistance = distance
			best = player
		end
	end

	return best
end

---------------------------------------------------------------------
-- FIND VISIBLE ENEMY
---------------------------------------------------------------------

local function findVisibleThreat()

	if not Root then
		return nil, math.huge
	end

	local best = nil
	local bestDistance = math.huge

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

		if distance
			> CONFIG.InterruptRadius then

			continue
		end

		if not canSee(character) then
			continue
		end

		if distance < bestDistance then

			best = player
			bestDistance = distance
		end
	end

	return best,
		bestDistance
end

---------------------------------------------------------------------
-- STABLE AIM POSITION
---------------------------------------------------------------------
--
-- Не используем реальную Head.Position.
--
-- Голова качается от анимации.
-- Берём стабильную точку над HRP.
---------------------------------------------------------------------

local function getAimPosition(
	character,
	targetRoot
)

	return targetRoot.Position
		+ Vector3.new(
			0,
			CONFIG.HeadOffsetY,
			0
		)
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

	if delta.Magnitude <= 0.001 then
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
-- Самая важная часть.
--
-- Камера:
--
-- НЕ использует Root.CFrame.LookVector
-- НЕ использует Head.Position
-- НЕ сканирует 360
--
-- Если есть ChaseTarget:
-- камера сразу смотрит на него даже через стену.
---------------------------------------------------------------------

local CAMERA_BIND =
	"AutoBotStableCamera"

RunService:UnbindFromRenderStep(
	CAMERA_BIND
)

RunService:BindToRenderStep(

	CAMERA_BIND,

	Enum.RenderPriority.Last.Value,

	function(dt)

		if not Character
			or not Root
			or not Humanoid
			or Humanoid.Health <= 0 then

			return
		end

		local camera =
			Workspace.CurrentCamera

		if not camera then
			return
		end

		-----------------------------------------------------------
		-- Захватываем камеру.
		-----------------------------------------------------------

		if camera.CameraType
			~= Enum.CameraType.Scriptable then

			camera.CameraType =
				Enum.CameraType.Scriptable
		end

		-----------------------------------------------------------
		-- Stable camera position.
		-----------------------------------------------------------

		local cameraPosition =
			Root.Position
			+ Vector3.new(
				0,
				CONFIG.CameraHeight,
				0
			)

		-----------------------------------------------------------
		-- TARGET EXISTS
		-----------------------------------------------------------

		if AimPosition then

			-------------------------------------------------------
			-- Smooth target movement.
			-------------------------------------------------------

			if not SmoothedAimPosition then

				SmoothedAimPosition =
					AimPosition

			else

				local targetAlpha =
					1
					- math.exp(
						-CONFIG.AimPositionSpeed
						* dt
					)

				SmoothedAimPosition =
					SmoothedAimPosition:
						Lerp(
							AimPosition,
							targetAlpha
						)
			end

			local direction =
				SmoothedAimPosition
				- cameraPosition

			if direction.Magnitude > 0.01 then

				local alpha =
					1
					- math.exp(
						-CONFIG.AimSpeed
						* dt
					)

				CameraForward =
					CameraForward:Lerp(
						direction.Unit,
						alpha
					)

				if CameraForward.Magnitude > 0.01 then

					CameraForward =
						CameraForward.Unit
				end
			end
		end

		-----------------------------------------------------------
		-- Если AimPosition == nil:
		--
		-- ничего НЕ крутим.
		-- Сохраняется последнее направление камеры.
		-----------------------------------------------------------

		camera.CFrame =
			CFrame.lookAt(
				cameraPosition,
				cameraPosition
					+ CameraForward
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

		Humanoid:MoveTo(
			Root.Position
		)
	end
end

---------------------------------------------------------------------
-- COMPUTE PATH
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
				"[BOT PATH ERROR]",
				err
			)
		end

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
-- NEED REPATH
---------------------------------------------------------------------

local function needsRepath(destination)

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
-- DIRECT FALLBACK
---------------------------------------------------------------------

local function directMove(destination)

	if not Humanoid then
		return
	end

	Humanoid.AutoRotate = true

	Humanoid:MoveTo(
		destination
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

	local distance =
		(
			waypoint.Position
			- Root.Position
		).Magnitude

	---------------------------------------------------------------
	-- NEXT WAYPOINT
	---------------------------------------------------------------

	if distance
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
	-- Jump ONLY if navmesh says so.
	---------------------------------------------------------------

	if waypoint.Action
		== Enum.PathWaypointAction.Jump then

		Humanoid.Jump = true
	end

	---------------------------------------------------------------
	-- Important:
	--
	-- MoveTo instead of Humanoid:Move().
	---------------------------------------------------------------

	Humanoid.AutoRotate = true

	Humanoid:MoveTo(
		waypoint.Position
	)

	return true
end

---------------------------------------------------------------------
-- MOVE TO
---------------------------------------------------------------------

local function moveTo(destination)

	if not Root
		or not Humanoid then

		return
	end

	if needsRepath(destination) then

		if not computePath(destination) then

			directMove(destination)

			return
		end
	end

	if not followPath() then

		Waypoints = {}

		directMove(destination)
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

	for index, wanted in ipairs(
		WEAPON_PRIORITY
	) do

		wanted =
			string.lower(wanted)

		if toolName == wanted
			or string.find(
				toolName,
				wanted,
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
				"[BOT FIRE] no Tool"
			)
		end

		return false
	end

	---------------------------------------------------------------
	-- Custom local adapter.
	---------------------------------------------------------------

	if tryLocalFire(
		tool,
		targetPosition
	) then

		LastShot =
			os.clock()

		return true
	end

	---------------------------------------------------------------
	-- Standard Roblox Tool.
	---------------------------------------------------------------

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
		0.025,

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
-- BUY ADAPTER
---------------------------------------------------------------------
--
-- Для своего магазина:
--
-- BindableEvent/BindableFunction:
--
-- ReplicatedStorage.BuyWeapon
--
-- BuyWeapon:Fire("AK47")
-- или
-- BuyWeapon:Invoke("AK47")
---------------------------------------------------------------------

local function findBuyAdapter()

	local locations = {

		ReplicatedStorage,

		LocalPlayer:
			FindFirstChild("PlayerGui"),

		LocalPlayer:
			FindFirstChild("PlayerScripts"),
	}

	for _, location in ipairs(
		locations
	) do

		if not location then
			continue
		end

		for _, name in ipairs({

			"BuyWeapon",
			"PurchaseWeapon",

			"BuyItem",
			"PurchaseItem",

		}) do

			local object =
				location:
					FindFirstChild(
						name,
						true
					)

			if object
				and (
					object:IsA("BindableEvent")
					or object:IsA("BindableFunction")
				) then

				return object
			end
		end
	end

	return nil
end

---------------------------------------------------------------------
-- BUY
---------------------------------------------------------------------

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

	local boughtSomething = false

	---------------------------------------------------------------
	-- PISTOL
	---------------------------------------------------------------

	for _, name in ipairs({

		"Deagle",
		"Desert Eagle",

	}) do

		if buyWeapon(name) then

			boughtSomething = true

			if CONFIG.Debug then
				print("[BOT BUY]", name)
			end

			break
		end
	end

	task.wait(0.08)

	---------------------------------------------------------------
	-- RIFLE
	---------------------------------------------------------------

	for _, name in ipairs({

		"AK47",
		"AK-47",

		"M4A1",
		"M4A4",
		"M4",

	}) do

		if buyWeapon(name) then

			boughtSomething = true

			if CONFIG.Debug then
				print("[BOT BUY]", name)
			end

			break
		end
	end

	if not boughtSomething
		and CONFIG.Debug then

		warn(
			"[BOT BUY] BuyWeapon adapter not found"
		)
	end

	task.wait(0.1)

	equipBestWeapon()
end

---------------------------------------------------------------------
-- UPDATE TARGETS
---------------------------------------------------------------------

local function updateTargets()

	local now =
		os.clock()

	if now - LastDetection
		< CONFIG.DetectionInterval then

		return
	end

	LastDetection = now

	---------------------------------------------------------------
	-- MAIN CHASE TARGET
	---------------------------------------------------------------

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

	---------------------------------------------------------------
	-- IMPORTANT:
	--
	-- Даже если ChaseTarget ЗА СТЕНОЙ,
	-- камера уже должна смотреть на него.
	---------------------------------------------------------------

	if targetValid(
		ChaseTarget
	) then

		local chaseCharacter,
			chaseHumanoid,
			chaseRoot =
			getPlayerData(
				ChaseTarget
			)

		if chaseCharacter
			and chaseHumanoid
			and chaseRoot then

			AimPosition =
				getAimPosition(
					chaseCharacter,
					chaseRoot
				)
		end
	end

	---------------------------------------------------------------
	-- CURRENT COMBAT TARGET
	---------------------------------------------------------------

	local currentVisible =
		false

	local currentDistance =
		math.huge

	if targetValid(
		CombatTarget
	) then

		local character =
			CombatTarget.Character

		if character
			and canSee(character) then

			currentVisible =
				true

			currentDistance =
				distanceTo(
					CombatTarget
				)
		end
	end

	---------------------------------------------------------------
	-- NEW VISIBLE THREAT
	---------------------------------------------------------------

	local threat,
		threatDistance =
		findVisibleThreat()

	if threat then

		local switch =
			false

		if not currentVisible then

			switch = true

		elseif threat
			== CombatTarget then

			switch = false

		elseif now
			- LastThreatSwitch
			>= CONFIG.ThreatSwitchCooldown
			and threatDistance
				+ CONFIG.ThreatSwitchMargin
				< currentDistance then

			switch = true
		end

		if switch then

			CombatTarget =
				threat

			LastThreatSwitch =
				now

			AimSettlingSince =
				nil

			FiringStance =
				false

			SmoothedAimPosition =
				nil

			Waypoints = {}

			if CONFIG.Debug then

				print(
					"[COMBAT]",
					threat.Name
				)
			end
		end

		return
	end

	---------------------------------------------------------------
	-- No interrupt.
	---------------------------------------------------------------

	if not currentVisible then

		CombatTarget =
			nil

		-----------------------------------------------------------
		-- Main chase target visible?
		-----------------------------------------------------------

		if targetValid(
			ChaseTarget
		) then

			local character =
				ChaseTarget.Character

			if character
				and canSee(character) then

				CombatTarget =
					ChaseTarget

				AimSettlingSince =
					nil

				FiringStance =
					false

				SmoothedAimPosition =
					nil
			end
		end
	end
end

---------------------------------------------------------------------
-- PROCESS COMBAT
---------------------------------------------------------------------

local function processCombatTarget(
	player
)

	if not targetValid(player) then
		return false
	end

	local character,
		targetHumanoid,
		targetRoot =
		getPlayerData(player)

	if not character
		or not targetHumanoid
		or not targetRoot then

		return false
	end

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

	---------------------------------------------------------------
	-- DIRECT CONTACT:
	-- always aim head.
	---------------------------------------------------------------

	AimPosition =
		headPosition

	---------------------------------------------------------------
	-- ENTER SHOOTING STANCE
	---------------------------------------------------------------

	if not FiringStance
		and distance
			<= CONFIG.StopToShootDistance then

		FiringStance =
			true

		AimSettlingSince =
			os.clock()
	end

	---------------------------------------------------------------
	-- TARGET MOVED AWAY
	---------------------------------------------------------------

	if FiringStance
		and distance
			> CONFIG.ResumeChaseDistance then

		FiringStance =
			false

		AimSettlingSince =
			nil
	end

	---------------------------------------------------------------
	-- RUN + AIM
	---------------------------------------------------------------

	if not FiringStance then

		AimSettlingSince =
			nil

		moveTo(
			targetRoot.Position
		)

		return true
	end

	---------------------------------------------------------------
	-- STOP
	---------------------------------------------------------------

	stopMovement()

	---------------------------------------------------------------
	-- FAST AIM SETTLE
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
	-- AIM ACCURACY
	---------------------------------------------------------------

	if cameraAngleTo(
		headPosition
	) > CONFIG.FireAimTolerance then

		return true
	end

	---------------------------------------------------------------
	-- FINAL LOS
	---------------------------------------------------------------

	if not canSee(character) then

		FiringStance =
			false

		AimSettlingSince =
			nil

		return false
	end

	---------------------------------------------------------------
	-- FIRE
	---------------------------------------------------------------

	if distance
		<= CONFIG.AttackRange then

		fireWeapon(
			headPosition
		)
	end

	return true
end

---------------------------------------------------------------------
-- PROCESS CHASE
---------------------------------------------------------------------

local function processChaseTarget(
	player
)

	if not targetValid(player) then
		return false
	end

	local character,
		targetHumanoid,
		targetRoot =
		getPlayerData(player)

	if not character
		or not targetHumanoid
		or not targetRoot then

		return false
	end

	---------------------------------------------------------------
	-- THIS FIXES YOUR MAIN PROBLEM:
	--
	-- ВРАГ ЗА СТЕНОЙ:
	--
	-- камера НЕ обнуляется.
	-- камера смотрит прямо на позицию врага.
	---------------------------------------------------------------

	AimPosition =
		getAimPosition(
			character,
			targetRoot
		)

	---------------------------------------------------------------
	-- Но движение идёт не сквозь стену,
	-- а по Pathfinding.
	---------------------------------------------------------------

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

					updateTargets()

					-------------------------------------------------
					-- DIRECT VISIBLE ENEMY
					-------------------------------------------------

					if CombatTarget then

						if processCombatTarget(
							CombatTarget
						) then

							return
						else

							CombatTarget =
								nil

							FiringStance =
								false

							AimSettlingSince =
								nil
						end
					end

					-------------------------------------------------
					-- GLOBAL CHASE TARGET
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
					-- NOBODY
					-------------------------------------------------

					AimPosition = nil

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

		task.wait(0.20)

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
-- CURRENT CHARACTER
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

print(
	"[AutoBot] STABLE CHASE BOT RUNNING"
)
