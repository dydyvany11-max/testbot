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
---------------------------------------------------------------------

local CONFIG = {

	ThinkInterval = 0.025,
	DetectionInterval = 0.04,

	TeamCheck = true,

	---------------------------------------------------------------
	-- SEARCH / CHASE
	---------------------------------------------------------------

	GlobalChaseRadius = 10000,
	InterruptRadius = 500,

	ThreatSwitchCooldown = 0.20,
	ThreatSwitchMargin = 15,

	---------------------------------------------------------------
	-- PRO AIM CONFIG
	---------------------------------------------------------------

	AimSmoothness = 0.65,    -- Агрессивная скорость флика (0.5 - 0.85)
	AimAccelRatio = 1.35,    -- Коэффициент ускорения при далеком прицеле
	HeadOffsetY = 1.50,

	PredictionTime = 0.045,  -- Упреждение движения цели в секундах

	FireAimTolerance = 12.0, -- Допуск угла в пикселях (стреляет почти мгновенно)

	---------------------------------------------------------------
	-- COMBAT TIMINGS
	---------------------------------------------------------------

	StopToShootDistance = 120,
	ResumeChaseDistance = 140,

	AimSettleTime = 0.01,    -- Нулевая задержка реакции
	FireDelay = 0.055,       -- Максимальный темп стрельбы
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
	-- Оставлено пустым для предотвращения бана за блокировку PlayerModule
end
---------------------------------------------------------------------
-- SETUP CHARACTER
---------------------------------------------------------------------

local function setupCharacter(character)

	Character = character

	Humanoid =
		character:WaitForChild("Humanoid")

	Root =
		character:WaitForChild(
			"HumanoidRootPart"
		)

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

---------------------------------------------------------------------
-- PRO AIM: PREDICTIVE HEAD POSITION
---------------------------------------------------------------------

local function getAimPosition(character, targetRoot)
	local head = character:FindFirstChild("Head") or targetRoot
	local headPos = head.Position

	-- Считываем вектор скорости движения цели
	local velocity = targetRoot.AssemblyLinearVelocity or targetRoot.Velocity or Vector3.zero

	-- Вычисляем упреждение (расчет позиции в будущем)
	local predictedPosition = headPos + (velocity * CONFIG.PredictionTime)

	return predictedPosition
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

local UserInputService = game:GetService("UserInputService")

---------------------------------------------------------------------
-- STABLE HEAD AIM WITH MICRO-NOISE (HUMANIZED)
---------------------------------------------------------------------

local function getAimPosition(character, targetRoot)
	-- Добавляем микро-шум к точке прицеливания (чтобы не было идеального лока в 1 пиксель)
	local noiseX = RNG:NextNumber(-0.12, 0.12)
	local noiseY = RNG:NextNumber(-0.08, 0.08)
	local noiseZ = RNG:NextNumber(-0.12, 0.12)

	return targetRoot.Position + Vector3.new(noiseX, CONFIG.HeadOffsetY + noiseY, noiseZ)
end

---------------------------------------------------------------------
-- BAC-SAFE CAMERA & MOUSE AIMING
---------------------------------------------------------------------

---------------------------------------------------------------------
-- PRO AIM: DYNAMIC FLICK & TRACKING
---------------------------------------------------------------------

local UserInputService = game:GetService("UserInputService")
local CAMERA_NAME = "AutoBotStableCamera"

RunService:UnbindFromRenderStep(CAMERA_NAME)

RunService:BindToRenderStep(
	CAMERA_NAME,
	Enum.RenderPriority.Camera.Value + 1,
	function(dt)
		if not Root or not Humanoid or Humanoid.Health <= 0 then
			return
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end

		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end

		if AimPosition and mousemoverel then
			local screenPos, onScreen = camera:WorldToViewportPoint(AimPosition)

			if onScreen then
				local mousePos = UserInputService:GetMouseLocation()
				local deltaX = screenPos.X - mousePos.X
				local deltaY = screenPos.Y - mousePos.Y

				local distance = math.sqrt(deltaX^2 + deltaY^2)

				-- Динамический коэффициент: дальний флик делаем быстрее, микро-доводку точнее
				local speedFactor = CONFIG.AimSmoothness
				if distance > 40 then
					speedFactor = math.min(0.95, CONFIG.AimSmoothness * CONFIG.AimAccelRatio)
				end

				local moveX = deltaX * speedFactor
				local moveY = deltaY * speedFactor

				-- Применяем мгновенное физическое смещение
				mousemoverel(moveX, moveY)
			end
		end
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

local FiringInProgress = false

local function performFire()
	if FiringInProgress then
		return false
	end

	FiringInProgress = true

	task.spawn(function()
		local pressDuration = math.random(10, 20) / 1000

		if mouse1press and mouse1release then
			mouse1press()
			task.wait(pressDuration)
			mouse1release()
		elseif mouse1click then
			mouse1click()
		else
			local VIM = game:GetService("VirtualInputManager")
			if VIM then
				VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
				task.wait(pressDuration)
				VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
			end
		end

		task.wait(CONFIG.FireDelay)
		FiringInProgress = false
	end)

	return true
end
	-----------------------------------------------------------------
	-- >>> FIRE HOOK <<<
	--
	-- Для нормального Roblox Tool сейчас:
	-----------------------------------------------------------------

	local success =
		pcall(function()

			tool:Activate()
		end)

	if not success then
		return false
	end

	task.delay(0.025, function()

		if tool
			and tool.Parent then

			pcall(function()
				tool:Deactivate()
			end)
		end
	end)

	return true
end

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
-- UPDATE TARGETS
---------------------------------------------------------------------

local function updateTargets()

	local now =
		os.clock()

	if now - LastDetection
		< CONFIG.DetectionInterval then

		return
	end

	LastDetection =
		now

	---------------------------------------------------------------
	-- MAIN CHASE TARGET
	---------------------------------------------------------------

	if not targetValid(
		ChaseTarget
	) then

		ChaseTarget =
			findNearestEnemy()

		Waypoints = {}
	end

	---------------------------------------------------------------
	-- AIM AT CHASE TARGET EVEN THROUGH WALL
	---------------------------------------------------------------

	if targetValid(
		ChaseTarget
	) then

		local character,
			humanoid,
			targetRoot =
			getPlayerData(
				ChaseTarget
			)

		if character
			and humanoid
			and targetRoot then

			AimPosition =
				getAimPosition(
					character,
					targetRoot
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
	-- NEW DIRECT CONTACT
	---------------------------------------------------------------

	local threat,
		threatDistance =
		findVisibleThreat()

	if threat then

		local shouldSwitch =
			false

		if not currentVisible then

			shouldSwitch =
				true

		elseif threat
			~= CombatTarget
			and now
				- LastThreatSwitch
				>= CONFIG.ThreatSwitchCooldown
			and threatDistance
				+ CONFIG.ThreatSwitchMargin
				< currentDistance then

			shouldSwitch =
				true
		end

		if shouldSwitch then

			CombatTarget =
				threat

			LastThreatSwitch =
				now

			FiringStance =
				false

			AimSettlingSince =
				nil

			SmoothedAimPosition =
				nil

			Waypoints = {}
		end

		return
	end

	---------------------------------------------------------------
	-- MAIN TARGET VISIBLE
	---------------------------------------------------------------

	if not currentVisible then

		CombatTarget =
			nil

		if targetValid(
			ChaseTarget
		) then

			local character =
				ChaseTarget.Character

			if character
				and canSee(character) then

				CombatTarget =
					ChaseTarget

				FiringStance =
					false

				AimSettlingSince =
					nil
			end
		end
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
-- MAIN
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
					-- DIRECT CONTACT FIRST
					-------------------------------------------------

					if CombatTarget then

						if processCombatTarget(
							CombatTarget
						) then

							return
						end

						CombatTarget =
							nil
					end

					-------------------------------------------------
					-- OTHERWISE CHASE
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
					-- NOTHING
					-------------------------------------------------

					stopMovement()
				end)

			if not success then

				warn(
					"[BOT ERROR]",
					err
				)
			end

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
