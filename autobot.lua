-- AutoBot.client.lua
-- StarterPlayer > StarterPlayerScripts

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


local CONFIG = {

	ThinkInterval = 0.025,
	DetectionInterval = 0.04,

	TeamCheck = false,

	---------------------------------------------------------------
	-- SEARCH / CHASE
	---------------------------------------------------------------

	GlobalChaseRadius = 10000,
	InterruptRadius = 500,

	ThreatSwitchCooldown = 0.20,
	ThreatSwitchMargin = 15,

	---------------------------------------------------------------
	-- SAFE AIM (BAC SAFE)
	---------------------------------------------------------------
	AimSpeed = 65,
	AimPositionSpeed = 40,
	CameraHeight = 1.8,
	HeadOffsetY = 1.5,
	FireAimTolerance = 2.0,
-- Допуск угла (в пикселях/градусах) перед выстрелом

	---------------------------------------------------------------
	-- COMBAT
	---------------------------------------------------------------

	AttackRange = 350,

	StopToShootDistance = 60,
	ResumeChaseDistance = 78,

	AimSettleTime = 0.06, -- Задержка реакции перед выстрелом
	FireDelay = 0.09,     -- Задержка между выстрелами

	---------------------------------------------------------------
	-- PATH & PATROL
	---------------------------------------------------------------

	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
	AgentCanClimb = false,

	WaypointReachDistance = 5,
	RepathInterval = 0.35,
	RepathDistance = 6,

	Debug = false,
}
---------------------------------------------------------------------
-- CHARACTER
---------------------------------------------------------------------

local Character = nil
local Humanoid = nil
local Root = nil


---------------------------------------------------------------------
-- TARGETS
---------------------------------------------------------------------

local ChaseTarget = nil
local CombatTarget = nil

local LastDetection = 0
local LastThreatSwitch = 0


---------------------------------------------------------------------
-- AIM
---------------------------------------------------------------------

local AimPosition = nil
local SmoothedAimPosition = nil

local CameraForward =
	Vector3.new(0, 0, -1)

local AimSettlingSince = nil
local FiringStance = false

---------------------------------------------------------------------
-- PATH
---------------------------------------------------------------------

local Waypoints = {}
local WaypointIndex = 1

local LastPathDestination = nil
local LastPathTime = 0

---------------------------------------------------------------------
-- FIRE
---------------------------------------------------------------------

local LastShot = 0

---------------------------------------------------------------------
-- PATROL
---------------------------------------------------------------------

local PatrolDestination = nil
local PatrolCreated = 0

local RNG = Random.new()

---------------------------------------------------------------------
-- CONTROLS
---------------------------------------------------------------------

local Controls = nil

local function disableControls()

	if Controls then
		return
	end

	local success, err =
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
		end)

	if success then
		print("[BOT] Player controls disabled")
	else
		warn("[BOT] Failed to disable controls:", err)
	end
end
---------------------------------------------------------------------
-- SETUP CHARACTER
---------------------------------------------------------------------

local function setupCharacter(character)

	Character = character

	Humanoid =
		character:WaitForChild("Humanoid")

	Root =
		character:WaitForChild("HumanoidRootPart")

	Humanoid.AutoRotate = false

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

	disableControls()

		disableControls()

	task.delay(0.1, function()

		local camera =
			Workspace.CurrentCamera

		if not camera then
			return
		end

		if camera.CFrame.LookVector.Magnitude > 0.01 then

			CameraForward =
				camera.CFrame.LookVector.Unit
		end

		camera.CameraType =
			Enum.CameraType.Scriptable
	end)

	print(
		"[BOT] READY",
		"WalkSpeed:",
		Humanoid.WalkSpeed
	)
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
-- TEAM
---------------------------------------------------------------------

local function isEnemy(player)

	if not player
		or player == LocalPlayer then

		return false
	end

	if not CONFIG.TeamCheck then
		return true
	end

	if LocalPlayer.Team
		and player.Team
		and LocalPlayer.Team == player.Team then

		return false
	end

	local myTeam =
		LocalPlayer:GetAttribute("Team")

	local theirTeam =
		player:GetAttribute("Team")

	if myTeam ~= nil
		and theirTeam ~= nil
		and myTeam == theirTeam then

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
-- RAY PARAMS
---------------------------------------------------------------------

local function rayParams()

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

		character:FindFirstChild("Head"),

		character:FindFirstChild(
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

				origin,

				part.Position - origin,

				rayParams()
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
-- TARGET VALID
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
-- FIND NEAREST
---------------------------------------------------------------------

local function findNearestEnemy()

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

			best = player
			bestDistance = distance
		end
	end

	return best
end

---------------------------------------------------------------------
-- VISIBLE THREAT
---------------------------------------------------------------------

local function findVisibleThreat()

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
-- STABLE HEAD AIM
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
-- STABLE CAMERA AIM
---------------------------------------------------------------------

local CAMERA_NAME =
	"AutoBotStableCamera"

RunService:UnbindFromRenderStep(
	CAMERA_NAME
)

RunService:BindToRenderStep(

	CAMERA_NAME,

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

		---------------------------------------------------------
		-- НИКТО кроме нас камерой не управляет
		---------------------------------------------------------

		if camera.CameraType
			~= Enum.CameraType.Scriptable then

			camera.CameraType =
				Enum.CameraType.Scriptable
		end

		---------------------------------------------------------
		-- СТАБИЛЬНАЯ позиция камеры
		-- НЕ camera.CFrame.Position
		---------------------------------------------------------

		local cameraPosition =
			Root.Position
			+ Vector3.new(
				0,
				CONFIG.CameraHeight,
				0
			)

		---------------------------------------------------------
		-- TARGET SMOOTHING
		---------------------------------------------------------

		if AimPosition then

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
					SmoothedAimPosition:Lerp(
						AimPosition,
						positionAlpha
					)
			end

			-----------------------------------------------------
			-- ROTATION SMOOTHING
			-----------------------------------------------------

			local direction =
				SmoothedAimPosition
				- cameraPosition

			if direction.Magnitude > 0.01 then

				local aimAlpha =
					1
					- math.exp(
						-CONFIG.AimSpeed
						* dt
					)

				CameraForward =
					CameraForward:Lerp(
						direction.Unit,
						aimAlpha
					)

				if CameraForward.Magnitude > 0.01 then
					CameraForward =
						CameraForward.Unit
				end
			end
		end

		---------------------------------------------------------
		-- ЕДИНСТВЕННАЯ запись камеры за кадр
		---------------------------------------------------------

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
	end
end

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
-- REPATH
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

	if LastPathDestination
		and (
			destination
			- LastPathDestination
		).Magnitude
			>= CONFIG.RepathDistance then

		return true
	end

	return false
end

---------------------------------------------------------------------
-- DIRECT MOVEMENT
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

	if flat.Magnitude <= 0.1 then

		stopMovement()

		return
	end

	Humanoid.AutoRotate = false

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

	if waypoint.Action
		== Enum.PathWaypointAction.Jump then

		Humanoid.Jump = true
	end

	if flat.Magnitude > 0.05 then

		Humanoid.AutoRotate = false

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

	if needsRepath(destination) then

		if not computePath(
			destination
		) then

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
-- WEAPON
---------------------------------------------------------------------

local function getEquippedTool()

	if not Character then
		return nil
	end

	return Character:
		FindFirstChildOfClass(
			"Tool"
		)
end

local function equipTool()

	if not Humanoid then
		return nil
	end

	local tool =
		getEquippedTool()

	if tool then
		return tool
	end

	local backpack =
		LocalPlayer:
			FindFirstChildOfClass(
				"Backpack"
			)

	if not backpack then
		return nil
	end

	tool =
		backpack:
			FindFirstChildOfClass(
				"Tool"
			)

	if not tool then
		return nil
	end

	pcall(function()

		Humanoid:
			EquipTool(tool)
	end)

	return tool
end

---------------------------------------------------------------------
-- REAL FIRE ACTION
---------------------------------------------------------------------
--
-- Вот единственное место, отвечающее а ФАКТИЧЕСКИЙ выстрел.
---------------------------------------------------------------------

---------------------------------------------------------------------
-- REAL FIRE ACTION
---------------------------------------------------------------------
--
-- Вот единственное место, отвечающее за ФАКТИЧЕСКИЙ выстрел.
---------------------------------------------------------------------
local FiringInProgress = false

local function performFire()
	if FiringInProgress then
		return false
	end

	FiringInProgress = true

	task.spawn(function()
		pcall(function()
			-- Запрос к Python-серверу на ПК
			game:HttpGet("http://10.0.2.2:8080/fire")
		end)

		-- Задержка между выстрелами (подгони под темп оружия)
		task.wait(CONFIG.FireDelay or 0.08)
		FiringInProgress = false
	end)

	return true
end
	-----------------------------------------------------------------
	-- >>> FIRE HOOK <<<
	--
	-- Для нормального Roblox Tool сейчас:
	-----------------------------------------------------------------

	

---------------------------------------------------------------------
-- FIRE DECISION
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

	if not performFire() then
		return false
	end

	LastShot =
		os.clock()

	return true
end

---------------------------------------------------------------------
local function updateTargets()

	local now = os.clock()

	if now - LastDetection < CONFIG.DetectionInterval then
		return
	end

	LastDetection = now

	-----------------------------------------------------------------
	-- 1. ИЩЕМ БЛИЖАЙШЕГО ВИДИМОГО ПРОТИВНИКА
	-----------------------------------------------------------------

	local visibleTarget, visibleDistance =
		findVisibleThreat()

	-----------------------------------------------------------------
	-- 2. КОГО-ТО ВИДИМ -> СРАЗУ ПЕРЕКЛЮЧАЕМ COMBAT TARGET
	-----------------------------------------------------------------

	if visibleTarget then

		if CombatTarget ~= visibleTarget then

			CombatTarget = visibleTarget

			FiringStance = false
			AimSettlingSince = nil

			-- ВАЖНО:
			-- SmoothedAimPosition НЕ ОБНУЛЯЕМ,
			-- иначе камера будет резко прыгать между целями.

			Waypoints = {}
		end

		-------------------------------------------------------------
		-- AIM НА ТЕКУЩУЮ ВИДИМУЮ ЦЕЛЬ
		-------------------------------------------------------------

		local character,
			targetHumanoid,
			targetRoot =
			getPlayerData(CombatTarget)

		if character
			and targetHumanoid
			and targetRoot then

			AimPosition =
				getAimPosition(
					character,
					targetRoot
				)
		end

		return
	end

	-----------------------------------------------------------------
	-- 3. ВИДИМОЙ ЦЕЛИ БОЛЬШЕ НЕТ
	-----------------------------------------------------------------

	CombatTarget = nil

	FiringStance = false
	AimSettlingSince = nil

	-----------------------------------------------------------------
	-- 4. ПРОВЕРЯЕМ ОСНОВНУЮ ЦЕЛЬ ДЛЯ ПРЕСЛЕДОВАНИЯ
	-----------------------------------------------------------------

	if not targetValid(ChaseTarget) then

		ChaseTarget =
			findNearestEnemy()

		Waypoints = {}
	end

	-----------------------------------------------------------------
	-- 5. ЕСЛИ ЕСТЬ CHASE TARGET —
	-- ДЕРЖИМ AIM В ЕГО СТОРОНУ ДАЖЕ ЧЕРЕЗ СТЕНУ
	-----------------------------------------------------------------

	if targetValid(ChaseTarget) then

		local character,
			targetHumanoid,
			targetRoot =
			getPlayerData(ChaseTarget)

		if character
			and targetHumanoid
			and targetRoot then

			AimPosition =
				getAimPosition(
					character,
					targetRoot
				)
		end

	else

		ChaseTarget = nil
		AimPosition = nil
	end
end

---------------------------------------------------------------------
-- COMBAT
---------------------------------------------------------------------

local function processCombatTarget(player)

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

	local targetPosition =
		getAimPosition(
			character,
			targetRoot
		)

	AimPosition =
		targetPosition

	---------------------------------------------------------------
	-- FAR -> RUN + AIM
	---------------------------------------------------------------

	if not FiringStance
		and distance
			> CONFIG.StopToShootDistance then

		AimSettlingSince =
			nil

		moveTo(
			targetRoot.Position
		)

		return true
	end

	---------------------------------------------------------------
	-- ENTER FIRING STANCE
	---------------------------------------------------------------

	if not FiringStance then

		FiringStance =
			true

		AimSettlingSince =
			os.clock()
	end

	---------------------------------------------------------------
	-- TARGET RAN AWAY
	---------------------------------------------------------------

	if distance
		> CONFIG.ResumeChaseDistance then

		FiringStance =
			false

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
	-- SETTLE
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
	-- FIRE
	---------------------------------------------------------------

	if distance
		<= CONFIG.AttackRange
		and canSee(character) then

		fireWeapon(
			targetPosition
		)
	end

	return true
end

---------------------------------------------------------------------
-- CHASE THROUGH WALLS
---------------------------------------------------------------------

local function processChaseTarget(player)

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

	---------------------------------------------------------------
	-- Look toward enemy.
	---------------------------------------------------------------

	AimPosition =
		getAimPosition(
			character,
			targetRoot
		)

	---------------------------------------------------------------
	-- Run through pathfinding.
	---------------------------------------------------------------

	FiringStance =
		false

	AimSettlingSince =
		nil

	moveTo(
		targetRoot.Position
	)

	return true
end
---------------------------------------------------------------------
-- MAIN AI LOOP
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
					-- Ищем / обновляем цели
					-------------------------------------------------

					updateTargets()

					-------------------------------------------------
					-- Сначала прямой контакт
					-------------------------------------------------

					if CombatTarget then

						if processCombatTarget(
							CombatTarget
						) then

							return
						end

						CombatTarget =
							nil

						FiringStance =
							false

						AimSettlingSince =
							nil
					end

					-------------------------------------------------
					-- Если прямого контакта нет:
					-- преследуем ближайшую цель через Pathfinding
					-------------------------------------------------

					if ChaseTarget then

						if processChaseTarget(
							ChaseTarget
						) then

							return
						end

						ChaseTarget =
							nil
					end

					-------------------------------------------------
					-- Никого нет
					-------------------------------------------------

					stopMovement()

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

		task.wait(0.2)

		setupCharacter(character)

		task.delay(0.5, function()
			equipTool()
		end)
	end)

---------------------------------------------------------------------
-- EXISTING CHARACTER
---------------------------------------------------------------------

if LocalPlayer.Character then

	task.spawn(function()

		setupCharacter(
			LocalPlayer.Character
		)

		task.wait(0.5)

		equipTool()
	end)
end

print("[BOT] CHASE + AIM + FIRE READY")
