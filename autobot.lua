-- AutoBot.client.lua

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

	-------------------------------------------------------------
	-- AI
	-------------------------------------------------------------

	ThinkInterval = 0.03,

	DetectionInterval = 0.03,

	-- Полный поиск вокруг персонажа.
	DetectionRadius = 600,

	LostTargetTime = 4,

	TeamCheck = true,

	-------------------------------------------------------------
	-- AIM
	-------------------------------------------------------------

	-- Быстрое наведение.
	AimSpeed = 65,

	-- Когда врага нет, камера сама осматривает 360°.
	ScanDegreesPerSecond = 130,

	-- Стрелять только после доведения камеры.
	FireAimTolerance = 5,

	AimHead = true,

	-------------------------------------------------------------
	-- COMBAT
	-------------------------------------------------------------

	AttackRange = 230,

	-- На таком расстоянии перестаём бежать прямо во врага.
	StopDistance = 28,

	FireDelay = 0.10,

	-------------------------------------------------------------
	-- PATH
	-------------------------------------------------------------

	AgentRadius = 2,

	AgentHeight = 5,

	AgentCanJump = true,

	RepathInterval = 0.25,

	RepathDistance = 5,

	WaypointReachDistance = 4,

	-------------------------------------------------------------
	-- PATROL
	-------------------------------------------------------------

	PatrolMinDistance = 50,

	PatrolMaxDistance = 130,

	PatrolTimeout = 7,
}

---------------------------------------------------------------------
-- CHARACTER
---------------------------------------------------------------------

local Character = nil
local Humanoid = nil
local Root = nil
local Head = nil

---------------------------------------------------------------------
-- PLAYER CONTROLS
---------------------------------------------------------------------
--
-- Отключаем стандартное WASD управление, чтобы PlayerModule
-- не перезаписывал Humanoid:Move().
---------------------------------------------------------------------

local Controls = nil

pcall(function()

	local PlayerModule =
		require(
			LocalPlayer:
				WaitForChild("PlayerScripts"):
				WaitForChild("PlayerModule")
		)

	Controls =
		PlayerModule:GetControls()

	Controls:Disable()

	print("[BOT] default controls disabled")
end)

---------------------------------------------------------------------
-- TARGET STATE
---------------------------------------------------------------------

local Target = nil

local LastSeenPosition = nil
local LastSeenTime = 0

local LastDetection = 0

---------------------------------------------------------------------
-- PATH STATE
---------------------------------------------------------------------

local CurrentPath = nil

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
-- FIRE STATE
---------------------------------------------------------------------

local LastShot = 0

---------------------------------------------------------------------
-- CHARACTER SETUP
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

	-------------------------------------------------------------
	-- WalkSpeed специально НЕ трогаем.
	-------------------------------------------------------------

	Target = nil

	LastSeenPosition = nil

	CurrentPath = nil

	Waypoints = {}

	PatrolDestination = nil

	print(
		"[BOT] character ready:",
		character.Name
	)
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
-- TEAM
---------------------------------------------------------------------

local function getTeamKey(player)

	-------------------------------------------------------------
	-- Roblox Teams.
	-------------------------------------------------------------

	if player.Team then
		return "TEAM:" .. player.Team.Name
	end

	-------------------------------------------------------------
	-- Кастомные варианты для своего place.
	-------------------------------------------------------------

	local teamAttribute =
		player:GetAttribute("Team")

	if teamAttribute ~= nil then

		return "ATTR:"
			.. tostring(teamAttribute)
	end

	local sideAttribute =
		player:GetAttribute("Side")

	if sideAttribute ~= nil then

		return "SIDE:"
			.. tostring(sideAttribute)
	end

	local character =
		player.Character

	if character then

		local characterTeam =
			character:GetAttribute("Team")

		if characterTeam ~= nil then

			return "CHAR:"
				.. tostring(characterTeam)
		end
	end

	return nil
end

local function isEnemy(player)

	if player == LocalPlayer then
		return false
	end

	if not CONFIG.TeamCheck then
		return true
	end

	local myTeam =
		getTeamKey(LocalPlayer)

	local theirTeam =
		getTeamKey(player)

	-------------------------------------------------------------
	-- Если обе команды известны и совпадают -> свой.
	-------------------------------------------------------------

	if myTeam
		and theirTeam
		and myTeam == theirTeam then

		return false
	end

	return true
end

---------------------------------------------------------------------
-- RAYCAST PARAMS
---------------------------------------------------------------------

local function getRaycastParams()

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
-- LINE OF SIGHT
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

		local origin =
			Head.Position

		local direction =
			part.Position - origin

		local result =
			Workspace:Raycast(
				origin,
				direction,
				getRaycastParams()
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
-- FIND TARGET - 360°
---------------------------------------------------------------------

local function findTarget()

	if not Root then
		return nil
	end

	local bestPlayer = nil

	local bestDistance =
		math.huge

	for _, player
		in ipairs(
			Players:GetPlayers()
		) do

		---------------------------------------------------------
		-- Сразу исключаем тиммейтов.
		---------------------------------------------------------

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
			> CONFIG.DetectionRadius then

			continue
		end

		if distance
			>= bestDistance then

			continue
		end

		---------------------------------------------------------
		-- Не берём цель сквозь стену.
		---------------------------------------------------------

		if not canSee(character) then
			continue
		end

		bestPlayer =
			player

		bestDistance =
			distance
	end

	return bestPlayer
end

---------------------------------------------------------------------
-- TARGET AIM PART
---------------------------------------------------------------------

local function getAimPosition(
	character,
	root
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

	return root.Position
end

---------------------------------------------------------------------
-- CAMERA ANGLE
---------------------------------------------------------------------

local function cameraAngleTo(
	position
)

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

RunService:BindToRenderStep(

	"AutoBotCamera",

	Enum.RenderPriority.Camera.Value + 1,

	function(dt)

		local camera =
			Workspace.CurrentCamera

		if not camera then
			return
		end

		---------------------------------------------------------
		-- TARGET AIM
		---------------------------------------------------------

		if Target then

			local character,
				_,
				targetRoot =
				getPlayerData(Target)

			if character
				and targetRoot
				and isEnemy(Target)
				and canSee(character) then

				local aimPosition =
					getAimPosition(
						character,
						targetRoot
					)

				local current =
					camera.CFrame

				local wanted =
					CFrame.lookAt(
						current.Position,
						aimPosition
					)

				local alpha =
					1
					- math.exp(
						-CONFIG.AimSpeed
						* dt
					)

				camera.CFrame =
					current:Lerp(
						wanted,
						alpha
					)

				return
			end
		end

		---------------------------------------------------------
		-- NO TARGET -> 360 SCAN
		---------------------------------------------------------

		local amount =
			math.rad(
				CONFIG.ScanDegreesPerSecond
			) * dt

		camera.CFrame =
			camera.CFrame
			* CFrame.Angles(
				0,
				amount,
				0
			)
	end
)

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
			})

	local success, errorMessage =
		pcall(function()

			path:ComputeAsync(
				Root.Position,
				destination
			)
		end)

	if not success then

		warn(
			"[BOT] path error:",
			errorMessage
		)

		CurrentPath = nil

		Waypoints = {}

		return false
	end

	if path.Status
		~= Enum.PathStatus.Success then

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
-- NEED REPATH
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

		local moved =
			(
				destination
				- LastPathDestination
			).Magnitude

		if moved
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

	if Humanoid then

		Humanoid:Move(
			Vector3.zero,
			false
		)
	end
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

		stopMovement()

		return false
	end

	local difference =
		waypoint.Position
		- Root.Position

	local flatDifference =
		Vector3.new(
			difference.X,
			0,
			difference.Z
		)

	-------------------------------------------------------------
	-- Waypoint reached.
	-------------------------------------------------------------

	if flatDifference.Magnitude
		<= CONFIG.WaypointReachDistance then

		WaypointIndex += 1

		waypoint =
			Waypoints[
				WaypointIndex
			]

		if not waypoint then

			stopMovement()

			return false
		end

		difference =
			waypoint.Position
			- Root.Position

		flatDifference =
			Vector3.new(
				difference.X,
				0,
				difference.Z
			)
	end

	-------------------------------------------------------------
	-- Jump waypoint.
	-------------------------------------------------------------

	if waypoint.Action
		== Enum.PathWaypointAction.Jump then

		Humanoid.Jump =
			true
	end

	-------------------------------------------------------------
	-- ВАЖНО:
	--
	-- Здесь теперь не Humanoid:MoveTo(),
	-- а постоянный Humanoid:Move().
	--
	-- Для LocalPlayer это обычно стабильнее.
	-------------------------------------------------------------

	if flatDifference.Magnitude
		> 0.01 then

		Humanoid.AutoRotate =
			true

		Humanoid:Move(
			flatDifference.Unit,
			false
		)

		return true
	end

	stopMovement()

	return false
end

---------------------------------------------------------------------
-- MOVE TO
---------------------------------------------------------------------

local function moveTo(
	destination
)

	if not Humanoid
		or not Root then

		return
	end

	if needsRepath(
		destination
	) then

		local pathFound =
			computePath(
				destination
			)

		---------------------------------------------------------
		-- Если Pathfinding не смог,
		-- идём напрямую.
		---------------------------------------------------------

		if not pathFound then

			local difference =
				destination
				- Root.Position

			local flat =
				Vector3.new(
					difference.X,
					0,
					difference.Z
				)

			if flat.Magnitude > 0.1 then

				Humanoid:Move(
					flat.Unit,
					false
				)
			end

			return
		end
	end

	followPath()
end

---------------------------------------------------------------------
-- RANDOM PATROL DESTINATION
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

		---------------------------------------------------------
		-- Ищем землю.
		---------------------------------------------------------

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

	local needNew =
		PatrolDestination == nil

	-------------------------------------------------------------
	-- Дошли до точки.
	-------------------------------------------------------------

	if PatrolDestination
		and (
			Root.Position
			- PatrolDestination
		).Magnitude <= 7 then

		needNew = true
	end

	-------------------------------------------------------------
	-- Застряли.
	-------------------------------------------------------------

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

		CurrentPath = nil

		Waypoints = {}
	end

	if PatrolDestination then

		moveTo(
			PatrolDestination
		)
	end
end

---------------------------------------------------------------------
-- GET TOOL
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

---------------------------------------------------------------------
-- EQUIP TOOL
---------------------------------------------------------------------

local function equipTool()

	if not Character
		or not Humanoid then

		return nil
	end

	local alreadyEquipped =
		getEquippedTool()

	if alreadyEquipped then
		return alreadyEquipped
	end

	local backpack =
		LocalPlayer:
			FindFirstChildOfClass(
				"Backpack"
			)

	if not backpack then
		return nil
	end

	local tool =
		backpack:
			FindFirstChildOfClass(
				"Tool"
			)

	if not tool then
		return nil
	end

	Humanoid:EquipTool(
		tool
	)

	return tool
end

---------------------------------------------------------------------
-- FIRE WEAPON
---------------------------------------------------------------------
--
-- В этом клиентском варианте больше НЕТ:
--
-- BotBullet
-- TakeDamage
-- fake magazine
-- fake projectile physics
--
-- Нажимаем штатный Tool.
---------------------------------------------------------------------

local function fireWeapon(
	targetPosition
)

	if os.clock() - LastShot
		< CONFIG.FireDelay then

		return
	end

	-------------------------------------------------------------
	-- Ещё не довелись до цели.
	-------------------------------------------------------------

	if cameraAngleTo(
		targetPosition
	) > CONFIG.FireAimTolerance then

		return
	end

	local tool =
		getEquippedTool()
		or equipTool()

	if not tool then

		warn(
			"[BOT] no weapon/tool"
		)

		return
	end

	if not tool.Enabled then
		return
	end

	LastShot =
		os.clock()

	-------------------------------------------------------------
	-- Один короткий trigger pulse.
	-------------------------------------------------------------

	tool:Activate()

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
end

---------------------------------------------------------------------
-- CLEAR TARGET
---------------------------------------------------------------------

local function clearTarget()

	Target = nil

	LastSeenPosition = nil

	CurrentPath = nil

	Waypoints = {}
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

	-------------------------------------------------------------
	-- Проверяем team каждый раз.
	-------------------------------------------------------------

	if not isEnemy(player) then

		clearTarget()

		return false
	end

	local character,
		_,
		targetRoot =
		getPlayerData(player)

	if not character then

		clearTarget()

		return false
	end

	local distance =
		(
			targetRoot.Position
			- Root.Position
		).Magnitude

	-------------------------------------------------------------
	-- TARGET VISIBLE.
	-------------------------------------------------------------

	if canSee(character) then

		LastSeenPosition =
			targetRoot.Position

		LastSeenTime =
			os.clock()

		local aimPosition =
			getAimPosition(
				character,
				targetRoot
			)

		---------------------------------------------------------
		-- RUN TOWARDS TARGET.
		---------------------------------------------------------

		if distance
			> CONFIG.StopDistance then

			moveTo(
				targetRoot.Position
			)

		else

			stopMovement()
		end

		---------------------------------------------------------
		-- FIRE.
		---------------------------------------------------------

		if distance
			<= CONFIG.AttackRange then

			fireWeapon(
				aimPosition
			)
		end

		return true
	end

	-------------------------------------------------------------
	-- LOST TARGET.
	-------------------------------------------------------------

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
-- UPDATE DETECTION
---------------------------------------------------------------------

local function updateDetection()

	if os.clock()
		- LastDetection
		< CONFIG.DetectionInterval then

		return
	end

	LastDetection =
		os.clock()

	-------------------------------------------------------------
	-- Validate current target.
	-------------------------------------------------------------

	if Target then

		local character,
			humanoid =
			getPlayerData(Target)

		if character
			and humanoid
			and humanoid.Health > 0
			and isEnemy(Target) then

			return
		end
	end

	-------------------------------------------------------------
	-- Search all around us.
	-------------------------------------------------------------

	Target =
		findTarget()
end

---------------------------------------------------------------------
-- CHARACTER RESPAWN
---------------------------------------------------------------------

LocalPlayer.CharacterAdded:
	Connect(function(character)

		task.wait(0.25)

		setupCharacter(
			character
		)
	end)

if LocalPlayer.Character then

	task.spawn(
		setupCharacter,
		LocalPlayer.Character
	)
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
					-- Быстрый 360° detection.
					-------------------------------------------------

					updateDetection()

					-------------------------------------------------
					-- Combat.
					-------------------------------------------------

					if Target then

						if processTarget(
							Target
						) then

							return
						end
					end

					-------------------------------------------------
					-- No enemy -> patrol.
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

print("[AutoBot] CLIENT BOT RUNNING")
