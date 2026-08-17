-- AutoBot.server.lua
-- Script inside NPC Model

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

---------------------------------------------------------------------
-- NPC
---------------------------------------------------------------------

local NPC = script.Parent

local Humanoid =
	NPC:WaitForChild("Humanoid")

local Root =
	NPC:WaitForChild("HumanoidRootPart")

local Head =
	NPC:WaitForChild("Head")

Root:SetNetworkOwner(nil)

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local CONFIG = {

	ThinkInterval = 0.05,

	-------------------------------------------------------------
	-- TARGETING
	-------------------------------------------------------------

	GlobalChaseRadius = 5000,

	-- Если другой игрок внезапно вышел рядом.
	InterruptRadius = 350,

	TeamCheck = true,

	-------------------------------------------------------------
	-- MOVEMENT
	-------------------------------------------------------------

	WalkSpeed = 22,

	StopToShootDistance = 55,

	-------------------------------------------------------------
	-- PATH
	-------------------------------------------------------------

	AgentRadius = 2,
	AgentHeight = 5,

	AgentCanJump = true,

	WaypointReachDistance = 4,

	RepathInterval = 0.35,

	RepathDistance = 6,

	-------------------------------------------------------------
	-- COMBAT
	-------------------------------------------------------------

	AttackRange = 250,

	AimSettleTime = 0.05,

	FireDelay = 0.10,

	HeadDamage = 100,
	BodyDamage = 30,

	SpreadDegrees = 0.35,

	-------------------------------------------------------------
	-- PATROL
	-------------------------------------------------------------

	PatrolMinDistance = 50,
	PatrolMaxDistance = 130,

	PatrolTimeout = 7,

	Debug = true,
}

Humanoid.WalkSpeed =
	CONFIG.WalkSpeed

Humanoid.AutoRotate =
	true

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local ChaseTarget = nil
local CombatTarget = nil

local Waypoints = {}
local WaypointIndex = 1

local LastPathTime = 0
local LastPathDestination = nil

local AimStarted = nil
local LastShot = 0

local PatrolDestination = nil
local PatrolStarted = 0

local RNG = Random.new()

---------------------------------------------------------------------
-- TEAM
---------------------------------------------------------------------

local function getNPCTeam()

	return NPC:GetAttribute("Team")
		or NPC:GetAttribute("BotTeam")
end

local function isEnemy(player)

	local character =
		player.Character

	if not character then
		return false
	end

	local npcTeam =
		getNPCTeam()

	local playerTeam =
		player:GetAttribute("Team")

	if npcTeam ~= nil
		and playerTeam ~= nil
		and npcTeam == playerTeam then

		return false
	end

	return true
end

---------------------------------------------------------------------
-- PLAYER DATA
---------------------------------------------------------------------

local function getPlayerData(player)

	if not player
		or not isEnemy(player) then

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
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart") then

		return nil
	end

	return character,
		humanoid,
		root
end

---------------------------------------------------------------------
-- DISTANCE
---------------------------------------------------------------------

local function distanceTo(player)

	local character,
		humanoid,
		targetRoot =
		getPlayerData(player)

	if not character then
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

local function rayParams()

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		NPC,
	}

	params.IgnoreWater = true

	return params
end

---------------------------------------------------------------------
-- LOS
---------------------------------------------------------------------

local function canSee(character)

	local targetHead =
		character:
			FindFirstChild("Head")

	local targetRoot =
		character:
			FindFirstChild("HumanoidRootPart")

	local targets = {
		targetHead,
		targetRoot,
	}

	for _, part in ipairs(targets) do

		if not part
			or not part:IsA("BasePart") then

			continue
		end

		local result =
			Workspace:Raycast(

				Head.Position,

				part.Position
					- Head.Position,

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
-- VALID TARGET
---------------------------------------------------------------------

local function targetValid(player)

	local character,
		humanoid,
		targetRoot =
		getPlayerData(player)

	if not character then
		return false
	end

	return (
		targetRoot.Position
		- Root.Position
	).Magnitude
		<= CONFIG.GlobalChaseRadius
end

---------------------------------------------------------------------
-- FIND GLOBAL TARGET
---------------------------------------------------------------------

local function findNearestEnemy()

	local best = nil
	local bestDistance = math.huge

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		local character,
			humanoid,
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

		if distance < bestDistance then

			bestDistance =
				distance

			best =
				player
		end
	end

	return best
end

---------------------------------------------------------------------
-- FIND VISIBLE THREAT
---------------------------------------------------------------------

local function findVisibleThreat()

	local best = nil
	local bestDistance = math.huge

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		local character,
			humanoid,
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
			> CONFIG.InterruptRadius then

			continue
		end

		if not canSee(character) then
			continue
		end

		if distance < bestDistance then

			bestDistance =
				distance

			best =
				player
		end
	end

	return best
end

---------------------------------------------------------------------
-- PATH
---------------------------------------------------------------------

local function computePath(destination)

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

	local success, err =
		pcall(function()

			path:ComputeAsync(
				Root.Position,
				destination
			)
		end)

	if not success then

		if CONFIG.Debug then
			warn("[PATH]", err)
		end

		Waypoints = {}

		return false
	end

	if path.Status
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

	LastPathTime =
		os.clock()

	LastPathDestination =
		destination

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

		local difference =
			(
				destination
				- LastPathDestination
			).Magnitude

		if difference
			>= CONFIG.RepathDistance then

			return true
		end
	end

	return false
end

---------------------------------------------------------------------
-- FOLLOW PATH
---------------------------------------------------------------------

local function followPath()

	local waypoint =
		Waypoints[WaypointIndex]

	if not waypoint then
		return false
	end

	local distance =
		(
			waypoint.Position
			- Root.Position
		).Magnitude

	if distance
		<= CONFIG.WaypointReachDistance then

		WaypointIndex += 1

		waypoint =
			Waypoints[WaypointIndex]

		if not waypoint then
			return false
		end
	end

	if waypoint.Action
		== Enum.PathWaypointAction.Jump then

		Humanoid.Jump =
			true
	end

	Humanoid:MoveTo(
		waypoint.Position
	)

	return true
end

---------------------------------------------------------------------
-- MOVE
---------------------------------------------------------------------

local function moveTo(destination)

	if needsRepath(destination) then

		if not computePath(destination) then

			Humanoid:MoveTo(
				destination
			)

			return
		end
	end

	if not followPath() then

		Waypoints = {}

		Humanoid:MoveTo(
			destination
		)
	end
end

---------------------------------------------------------------------
-- STOP
---------------------------------------------------------------------

local function stopMovement()

	Humanoid:MoveTo(
		Root.Position
	)
end

---------------------------------------------------------------------
-- AIM NPC BODY
---------------------------------------------------------------------

local function aimAt(position)

	local flatTarget =
		Vector3.new(
			position.X,
			Root.Position.Y,
			position.Z
		)

	if (
		flatTarget
		- Root.Position
	).Magnitude < 0.01 then

		return
	end

	Root.CFrame =
		CFrame.lookAt(
			Root.Position,
			flatTarget
		)
end

---------------------------------------------------------------------
-- SPREAD
---------------------------------------------------------------------

local function applySpread(direction)

	local spread =
		math.rad(
			CONFIG.SpreadDegrees
		)

	local x =
		RNG:NextNumber(
			-spread,
			spread
		)

	local y =
		RNG:NextNumber(
			-spread,
			spread
		)

	local basis =
		CFrame.lookAt(
			Vector3.zero,
			direction
		)

	return (
		basis
		* CFrame.Angles(
			x,
			y,
			0
		)
	).LookVector
end

---------------------------------------------------------------------
-- FIRE
---------------------------------------------------------------------
--
-- Для собственного NPC:
-- сервер сам делает raycast и наносит damage.
---------------------------------------------------------------------

local function shoot(
	character,
	targetRoot
)

	if os.clock()
		- LastShot
		< CONFIG.FireDelay then

		return
	end

	local targetHead =
		character:
			FindFirstChild("Head")

	local targetPosition

	if targetHead
		and targetHead:IsA("BasePart") then

		targetPosition =
			targetHead.Position
	else

		targetPosition =
			targetRoot.Position
			+ Vector3.new(
				0,
				1.5,
				0
			)
	end

	local origin =
		Head.Position

	local direction =
		targetPosition
		- origin

	if direction.Magnitude
		> CONFIG.AttackRange then

		return
	end

	direction =
		applySpread(
			direction.Unit
		)

	local result =
		Workspace:Raycast(

			origin,

			direction
				* CONFIG.AttackRange,

			rayParams()
		)

	if not result then
		return
	end

	if not result.Instance:
		IsDescendantOf(character) then

		return
	end

	local humanoid =
		character:
			FindFirstChildOfClass("Humanoid")

	if not humanoid then
		return
	end

	LastShot =
		os.clock()

	local damage =
		CONFIG.BodyDamage

	if targetHead
		and result.Instance
			== targetHead then

		damage =
			CONFIG.HeadDamage
	end

	humanoid:
		TakeDamage(damage)

	if CONFIG.Debug then

		print(
			"[FIRE]",
			character.Name,
			"damage:",
			damage
		)
	end
end

---------------------------------------------------------------------
-- PATROL TARGET
---------------------------------------------------------------------

local function createPatrolDestination()

	for _ = 1, 12 do

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

		local point =
			Root.Position
			+ Vector3.new(

				math.cos(angle)
					* distance,

				0,

				math.sin(angle)
					* distance
			)

		local ground =
			Workspace:Raycast(

				point
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

				rayParams()
			)

		if ground then

			return ground.Position
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

	if PatrolDestination then

		if (
			PatrolDestination
			- Root.Position
		).Magnitude <= 6 then

			needNew = true
		end

		if os.clock()
			- PatrolStarted
			>= CONFIG.PatrolTimeout then

			needNew = true
		end
	end

	if needNew then

		PatrolDestination =
			createPatrolDestination()

		PatrolStarted =
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
-- UPDATE TARGETS
---------------------------------------------------------------------

local function updateTargets()

	---------------------------------------------------------------
	-- Main target.
	---------------------------------------------------------------

	if not targetValid(
		ChaseTarget
	) then

		ChaseTarget =
			findNearestEnemy()

		Waypoints = {}
	end

	---------------------------------------------------------------
	-- Immediate visible contact.
	---------------------------------------------------------------

	local threat =
		findVisibleThreat()

	if threat then

		if CombatTarget
			~= threat then

			CombatTarget =
				threat

			AimStarted =
				nil

			Waypoints = {}
		end

		return
	end

	---------------------------------------------------------------
	-- Otherwise use main target if visible.
	---------------------------------------------------------------

	CombatTarget = nil

	if targetValid(
		ChaseTarget
	) then

		local character =
			ChaseTarget.Character

		if character
			and canSee(character) then

			CombatTarget =
				ChaseTarget
		end
	end
end

---------------------------------------------------------------------
-- COMBAT
---------------------------------------------------------------------

local function processCombat(
	player
)

	local character,
		targetHumanoid,
		targetRoot =
		getPlayerData(player)

	if not character then
		return false
	end

	if not canSee(character) then

		AimStarted = nil

		return false
	end

	local distance =
		(
			targetRoot.Position
			- Root.Position
		).Magnitude

	local targetHead =
		character:
			FindFirstChild("Head")

	local aimPosition =
		targetHead
			and targetHead.Position
			or targetRoot.Position
				+ Vector3.new(
					0,
					1.5,
					0
				)

	-------------------------------------------------------------
	-- LOOK AT TARGET
	-------------------------------------------------------------

	aimAt(
		aimPosition
	)

	-------------------------------------------------------------
	-- Still far -> run toward him.
	-------------------------------------------------------------

	if distance
		> CONFIG.StopToShootDistance then

		AimStarted =
			nil

		moveTo(
			targetRoot.Position
		)

		return true
	end

	-------------------------------------------------------------
	-- STOP
	-------------------------------------------------------------

	stopMovement()

	-------------------------------------------------------------
	-- FAST SETTLE
	-------------------------------------------------------------

	if not AimStarted then

		AimStarted =
			os.clock()

		return true
	end

	if os.clock()
		- AimStarted
		< CONFIG.AimSettleTime then

		return true
	end

	-------------------------------------------------------------
	-- SHOOT
	-------------------------------------------------------------

	shoot(
		character,
		targetRoot
	)

	return true
end

---------------------------------------------------------------------
-- CHASE
---------------------------------------------------------------------

local function processChase(
	player
)

	local character,
		targetHumanoid,
		targetRoot =
		getPlayerData(player)

	if not character then
		return false
	end

	-------------------------------------------------------------
	-- Even through a wall, turn toward his general direction.
	-------------------------------------------------------------

	aimAt(
		targetRoot.Position
	)

	-------------------------------------------------------------
	-- But movement follows navmesh around the wall.
	-------------------------------------------------------------

	moveTo(
		targetRoot.Position
	)

	return true
end

---------------------------------------------------------------------
-- MAIN LOOP
---------------------------------------------------------------------

task.spawn(function()

	while Humanoid.Health > 0 do

		local success, err =
			pcall(function()

				updateTargets()

				-------------------------------------------------
				-- Visible enemy has priority.
				-------------------------------------------------

				if CombatTarget then

					if processCombat(
						CombatTarget
					) then

						return
					end
				end

				-------------------------------------------------
				-- Otherwise chase hidden target.
				-------------------------------------------------

				if ChaseTarget then

					if processChase(
						ChaseTarget
					) then

						return
					end
				end

				-------------------------------------------------
				-- Nobody.
				-------------------------------------------------

				patrol()
			end)

		if not success then

			warn(
				"[BOT ERROR]",
				err
			)
		end

		task.wait(
			CONFIG.ThinkInterval
		)
	end
end)

print("[BOT] NPC CHASE AI RUNNING")
