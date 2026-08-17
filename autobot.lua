-- AutoBot.client.lua

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
	-- GENERAL
	---------------------------------------------------------------

	ThinkInterval = 0.03,

	---------------------------------------------------------------
	-- TARGETING
	---------------------------------------------------------------

	DetectionInterval = 0.03,

	-- Когда игрок видим.
	DetectionRadius = 700,

	-- Можно преследовать игрока даже через комнаты.
	GlobalChaseRadius = 5000,

	TargetRefreshInterval = 0.15,

	TeamCheck = true,

	---------------------------------------------------------------
	-- CAMERA
	---------------------------------------------------------------

	AimSpeed = 65,

	ScanDegreesPerSecond = 130,

	AimHead = true,

	---------------------------------------------------------------
	-- COMBAT
	---------------------------------------------------------------

	AttackRange = 250,

	StopDistance = 28,

	FireDelay = 0.10,

	FireAimTolerance = 6,

	---------------------------------------------------------------
	-- PATHFINDING
	---------------------------------------------------------------

	AgentRadius = 2,
	AgentHeight = 5,

	AgentCanJump = true,
	AgentCanClimb = false,

	RepathDistance = 5,

	ForceRepathAfter = 0.8,

	WaypointReachDistance = 4,

	---------------------------------------------------------------
	-- STUCK
	---------------------------------------------------------------

	StuckCheckInterval = 0.5,

	StuckMinMovement = 1.5,

	MaxStuckChecks = 3,

	---------------------------------------------------------------
	-- PATROL
	---------------------------------------------------------------

	PatrolMinDistance = 50,

	PatrolMaxDistance = 150,

	PatrolTimeout = 8,

	---------------------------------------------------------------
	-- WEAPON
	---------------------------------------------------------------

	-- Сначала пытаемся использовать уже экипированную пушку.
	PreferEquippedTool = true,

	-- Если ничего не экипировано, бот сам возьмёт Tool.
	AutoEquip = true,

	-- Дополнительно искать локальные Bindable Fire/Shoot.
	TryBindableFire = true,

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
			print("[BOT] default controls disabled")
		end
	end)
end

---------------------------------------------------------------------
-- TARGET
---------------------------------------------------------------------

local Target = nil
local CurrentAimPosition = nil

local LastDetection = 0
local LastTargetRefresh = 0

---------------------------------------------------------------------
-- PATH
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
-- FIRE
---------------------------------------------------------------------

local LastShot = 0
local LastFireDebug = 0

---------------------------------------------------------------------
-- SETUP CHARACTER
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

	Target = nil
	CurrentAimPosition = nil

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
			"[BOT] character ready:",
			character.Name,
			"speed:",
			Humanoid.WalkSpeed
		)
	end
end

---------------------------------------------------------------------
-- GET PLAYER DATA
---------------------------------------------------------------------

local function getPlayerData(player)

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

	if player == LocalPlayer then
		return false
	end

	if not CONFIG.TeamCheck then
		return true
	end

	---------------------------------------------------------------
	-- Roblox Teams.
	---------------------------------------------------------------

	if LocalPlayer.Team
		and player.Team
		and LocalPlayer.Team == player.Team then

		return false
	end

	---------------------------------------------------------------
	-- Player attribute.
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
	-- Side attribute.
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
-- RAYCAST
---------------------------------------------------------------------

local function createRayParams()

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
			FindFirstChild("HumanoidRootPart"),
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
				IsDescendantOf(character) then

			return true
		end
	end

	return false
end

---------------------------------------------------------------------
-- FIND TARGET
---------------------------------------------------------------------

local function findTarget()

	if not Root then
		return nil
	end

	local bestVisible = nil
	local bestVisibleDistance =
		math.huge

	local bestHidden = nil
	local bestHiddenDistance =
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

		-----------------------------------------------------------
		-- VISIBLE
		-----------------------------------------------------------

		if distance
			<= CONFIG.DetectionRadius
			and canSee(character) then

			if distance
				< bestVisibleDistance then

				bestVisibleDistance =
					distance

				bestVisible =
					player
			end

		else

			-------------------------------------------------------
			-- BEHIND WALL
			-------------------------------------------------------

			if distance
				< bestHiddenDistance then

				bestHiddenDistance =
					distance

				bestHidden =
					player
			end
		end
	end

	return bestVisible
		or bestHidden
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
-- CAMERA CONTROL
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

		-----------------------------------------------------------
		-- AIM
		-----------------------------------------------------------

		if CurrentAimPosition then

			local current =
				camera.CFrame

			local target =
				CFrame.lookAt(
					current.Position,
					CurrentAimPosition
				)

			local alpha =
				1
				- math.exp(
					-CONFIG.AimSpeed
					* dt
				)

			camera.CFrame =
				current:Lerp(
					target,
					alpha
				)

			return
		end

		-----------------------------------------------------------
		-- 360 SCAN
		-----------------------------------------------------------

		local rotation =
			math.rad(
				CONFIG.ScanDegreesPerSecond
			) * dt

		camera.CFrame =
			camera.CFrame
			* CFrame.Angles(
				0,
				rotation,
				0
			)
	end
)

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
				"[BOT PATH] failed:",
				path.Status
			)
		end

		CurrentPath = nil
		Waypoints = {}

		return false
	end

	CurrentPath = path

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
-- DIRECT MOVE
---------------------------------------------------------------------

local function directMove(destination)

	if not Root
		or not Humanoid then

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
	-- REACHED WAYPOINT
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
	-- MOVE
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
-- STUCK DETECTION
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

	local movement =
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

	if movement
		< CONFIG.StuckMinMovement then

		StuckChecks += 1

	else

		StuckChecks = 0
	end

	---------------------------------------------------------------
	-- STUCK
	---------------------------------------------------------------

	if StuckChecks
		>= CONFIG.MaxStuckChecks then

		if CONFIG.Debug then
			print("[BOT] stuck -> repath")
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

		local position =
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

				position
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
-- GET ALL TOOLS
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

	local backpack =
		LocalPlayer:
			FindFirstChildOfClass(
				"Backpack"
			)

	scan(backpack)

	return tools
end

---------------------------------------------------------------------
-- PRINT WEAPONS
---------------------------------------------------------------------

local function printWeapons()

	if not CONFIG.Debug then
		return
	end

	print("========== BOT WEAPONS ==========")

	local tools =
		getAllTools()

	if #tools == 0 then

		warn("[BOT] ZERO Tool objects")

	else

		for index, tool in ipairs(tools) do

			print(
				index,
				tool.Name,
				"Class:",
				tool.ClassName,
				"Parent:",
				tool.Parent
					and tool.Parent.Name
					or "nil",
				"Enabled:",
				tool.Enabled
			)
		end
	end

	print("=================================")
end

---------------------------------------------------------------------
-- GET EQUIPPED TOOL
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
-- EQUIP TOOL
---------------------------------------------------------------------

local function equipAnyTool()

	if not Humanoid then
		return nil
	end

	local current =
		getEquippedTool()

	if current then
		return current
	end

	local tools =
		getAllTools()

	for _, tool in ipairs(tools) do

		if tool.Parent ~= Character then

			local success =
				pcall(function()

					Humanoid:
						EquipTool(tool)
				end)

			if success then

				task.wait()

				if tool.Parent
					== Character then

					if CONFIG.Debug then

						print(
							"[BOT WEAPON] equipped:",
							tool.Name
						)
					end

					return tool
				end
			end
		end
	end

	return nil
end

---------------------------------------------------------------------
-- LOCAL FIRE NAMES
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

---------------------------------------------------------------------
-- TRY BINDABLE FIRE
---------------------------------------------------------------------

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

		if object then

			-------------------------------------------------------
			-- EVENT
			-------------------------------------------------------

			if object:IsA(
				"BindableEvent"
			) then

				object:Fire(
					targetPosition
				)

				if CONFIG.Debug then

					print(
						"[BOT FIRE] BindableEvent:",
						object:GetFullName()
					)
				end

				return true
			end

			-------------------------------------------------------
			-- FUNCTION
			-------------------------------------------------------

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
							"[BOT FIRE] BindableFunction:",
							object:GetFullName()
						)
					end

					return true
				end
			end
		end
	end

	return false
end

---------------------------------------------------------------------
-- ACTIVATE TOOL
---------------------------------------------------------------------

local function activateTool(tool)

	if not tool then
		return false
	end

	if tool.Parent
		~= Character then

		if Humanoid
			and CONFIG.AutoEquip then

			pcall(function()

				Humanoid:
					EquipTool(tool)
			end)

			task.wait()
		end
	end

	if tool.Parent
		~= Character then

		return false
	end

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

	if CONFIG.Debug then

		print(
			"[BOT FIRE] Tool:Activate():",
			tool.Name,
			"success:",
			success,
			err or ""
		)
	end

	if not success then
		return false
	end

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
-- FIRE WEAPON
---------------------------------------------------------------------

local function fireWeapon(
	targetPosition
)

	---------------------------------------------------------------
	-- RATE LIMIT
	---------------------------------------------------------------

	if os.clock()
		- LastShot
		< CONFIG.FireDelay then

		return
	end

	---------------------------------------------------------------
	-- WAIT UNTIL AIMED
	---------------------------------------------------------------

	if cameraAngleTo(
		targetPosition
	) > CONFIG.FireAimTolerance then

		return
	end

	---------------------------------------------------------------
	-- ALL TOOLS
	---------------------------------------------------------------

	local tools =
		getAllTools()

	---------------------------------------------------------------
	-- DEBUG
	---------------------------------------------------------------

	if #tools == 0 then

		if os.clock()
			- LastFireDebug > 1 then

			LastFireDebug =
				os.clock()

			warn(
				"[BOT FIRE] no Tool found"
			)

			printWeapons()
		end

		return
	end

	---------------------------------------------------------------
	-- 1. CURRENT EQUIPPED TOOL
	---------------------------------------------------------------

	local equipped =
		getEquippedTool()

	if equipped then

		-----------------------------------------------------------
		-- Local weapon adapter inside gun.
		-----------------------------------------------------------

		if tryBindableFire(
			equipped,
			targetPosition
		) then

			LastShot =
				os.clock()

			return
		end

		-----------------------------------------------------------
		-- Normal Tool.
		-----------------------------------------------------------

		if activateTool(
			equipped
		) then

			LastShot =
				os.clock()

			return
		end
	end

	---------------------------------------------------------------
	-- 2. TRY LOCAL FIRE CONTROLLER
	---------------------------------------------------------------

	if tryBindableFire(
		Character,
		targetPosition
	) then

		LastShot =
			os.clock()

		return
	end

	if tryBindableFire(
		ReplicatedStorage,
		targetPosition
	) then

		LastShot =
			os.clock()

		return
	end

	---------------------------------------------------------------
	-- 3. TRY EVERY TOOL UNTIL ONE ACTIVATES
	---------------------------------------------------------------

	for _, tool in ipairs(tools) do

		-----------------------------------------------------------
		-- Try custom local event first.
		-----------------------------------------------------------

		if tryBindableFire(
			tool,
			targetPosition
		) then

			LastShot =
				os.clock()

			return
		end

		-----------------------------------------------------------
		-- Equip + Activate.
		-----------------------------------------------------------

		if activateTool(
			tool
		) then

			LastShot =
				os.clock()

			return
		end
	end

	---------------------------------------------------------------
	-- NOTHING WORKED
	---------------------------------------------------------------

	if os.clock()
		- LastFireDebug > 1 then

		LastFireDebug =
			os.clock()

		warn(
			"[BOT FIRE] weapons found, but no fire handler worked"
		)

		printWeapons()
	end
end

---------------------------------------------------------------------
-- CLEAR TARGET
---------------------------------------------------------------------

local function clearTarget()

	Target = nil

	CurrentAimPosition = nil

	CurrentPath = nil

	Waypoints = {}

	ForceRepath = true
end

---------------------------------------------------------------------
-- PROCESS TARGET
---------------------------------------------------------------------

local function processTarget(player)

	if not Root
		or not Humanoid then

		return false
	end

	if not isEnemy(player) then

		clearTarget()

		return false
	end

	local character,
		humanoid,
		targetRoot =
		getPlayerData(player)

	if not character
		or not humanoid
		or not targetRoot then

		clearTarget()

		return false
	end

	local distance =
		(
			targetRoot.Position
			- Root.Position
		).Magnitude

	local visible =
		canSee(character)

	-----------------------------------------------------------------
	-- VISIBLE
	-----------------------------------------------------------------

	if visible then

		local aimPosition =
			getAimPosition(
				character,
				targetRoot
			)

		CurrentAimPosition =
			aimPosition

		-------------------------------------------------------------
		-- RUN
		-------------------------------------------------------------

		if distance
			> CONFIG.StopDistance then

			moveTo(
				targetRoot.Position
			)

		else

			stopMovement()
		end

		-------------------------------------------------------------
		-- FIRE
		-------------------------------------------------------------

		if distance
			<= CONFIG.AttackRange then

			fireWeapon(
				aimPosition
			)
		end

		return true
	end

	-----------------------------------------------------------------
	-- PLAYER BEHIND WALL
	-----------------------------------------------------------------
	--
	-- Не целимся сквозь стену.
	-- Просто преследуем через Pathfinding.
	-----------------------------------------------------------------

	CurrentAimPosition =
		nil

	if distance
		<= CONFIG.GlobalChaseRadius then

		moveTo(
			targetRoot.Position
		)

		return true
	end

	clearTarget()

	return false
end

---------------------------------------------------------------------
-- UPDATE TARGET
---------------------------------------------------------------------

local function updateTarget()

	local now =
		os.clock()

	if now - LastDetection
		< CONFIG.DetectionInterval then

		return
	end

	LastDetection =
		now

	---------------------------------------------------------------
	-- VALIDATE
	---------------------------------------------------------------

	if Target then

		local character,
			humanoid =
			getPlayerData(Target)

		if not character
			or not humanoid
			or humanoid.Health <= 0
			or not isEnemy(Target) then

			Target = nil
		end
	end

	---------------------------------------------------------------
	-- REFRESH
	---------------------------------------------------------------

	if not Target
		or now - LastTargetRefresh
			>= CONFIG.TargetRefreshInterval then

		LastTargetRefresh =
			now

		local newTarget =
			findTarget()

		if newTarget ~= Target then

			Target =
				newTarget

			ForceRepath =
				true

			Waypoints = {}

			if CONFIG.Debug
				and Target then

				print(
					"[BOT] target:",
					Target.Name
				)
			end
		end
	end
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
					-- STUCK
					-------------------------------------------------

					updateStuckDetection()

					-------------------------------------------------
					-- TARGET
					-------------------------------------------------

					updateTarget()

					-------------------------------------------------
					-- COMBAT / CHASE
					-------------------------------------------------

					if Target then

						if processTarget(
							Target
						) then

							return
						end
					end

					-------------------------------------------------
					-- PATROL
					-------------------------------------------------

					CurrentAimPosition =
						nil

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
-- CHARACTER RESPAWN
---------------------------------------------------------------------

LocalPlayer.CharacterAdded:
	Connect(function(character)

		task.wait(0.25)

		setupCharacter(
			character
		)

		task.delay(
			2,

			function()
				printWeapons()
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

		task.wait(2)

		printWeapons()
	end)
end

---------------------------------------------------------------------
-- READY
---------------------------------------------------------------------

print("[AutoBot] CLIENT BOT RUNNING")
