--!strict

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

---------------------------------------------------------------------
-- NPC
---------------------------------------------------------------------

local NPC = script.Parent
local Humanoid = NPC:WaitForChild("Humanoid") :: Humanoid
local Root = NPC:WaitForChild("HumanoidRootPart") :: BasePart
local Head = NPC:WaitForChild("Head") :: BasePart

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local CONFIG = {

	-------------------------------------------------------------
	-- AI
	-------------------------------------------------------------

	ThinkInterval = 0.05,
	DetectionInterval = 0.05,

	DetectionRadius = 500,
	LostTargetTime = 4,

	-------------------------------------------------------------
	-- MOVEMENT
	-------------------------------------------------------------

	WalkSpeed = 22,

	StopDistance = 30,

	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,

	RepathInterval = 0.35,
	RepathDistance = 5,
	WaypointReachDistance = 4,

	-------------------------------------------------------------
	-- RANDOM PATROL
	-------------------------------------------------------------

	PatrolMinDistance = 40,
	PatrolMaxDistance = 120,

	PatrolTimeout = 7,

	-------------------------------------------------------------
	-- WEAPON
	-------------------------------------------------------------

	ShootingRange = 220,

	FireDelay = 0.10,

	MagazineSize = 30,
	ReserveAmmo = 120,

	ReloadTime = 2.3,

	-------------------------------------------------------------
	-- BULLET
	-------------------------------------------------------------

	BulletSpeed = 950,
	BulletRange = 250,

	BodyDamage = 28,
	HeadDamage = 100,

	SpreadDegrees = 1.1,

	PreferHead = true,
	HeadChance = 0.90,

	BulletSize = Vector3.new(
		0.08,
		0.08,
		1
	),
}

---------------------------------------------------------------------
-- NETWORK / HUMANOID
---------------------------------------------------------------------

Humanoid.WalkSpeed = CONFIG.WalkSpeed
Humanoid.AutoRotate = true

pcall(function()
	Root:SetNetworkOwner(nil)
end)

---------------------------------------------------------------------
-- TEAM
---------------------------------------------------------------------

-- Например:
-- NPC:SetAttribute("BotTeam", "T")

local BOT_TEAM =
	NPC:GetAttribute("BotTeam")

local function isEnemy(player: Player): boolean

	if not BOT_TEAM then
		return true
	end

	if player.Team
		and player.Team.Name == BOT_TEAM then

		return false
	end

	local character = player.Character

	if character then

		local team =
			character:GetAttribute("Team")

		if team == BOT_TEAM then
			return false
		end
	end

	return true
end

---------------------------------------------------------------------
-- PROJECTILES
---------------------------------------------------------------------

local ProjectileFolder =
	Workspace:FindFirstChild("BotProjectiles")

if not ProjectileFolder then

	ProjectileFolder = Instance.new("Folder")
	ProjectileFolder.Name = "BotProjectiles"
	ProjectileFolder.Parent = Workspace
end

local Bullets = {}

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local Target: Player? = nil

local LastSeenPosition: Vector3? = nil
local LastSeenTime = 0

local LastDetection = 0

local Waypoints = {}
local WaypointIndex = 1

local LastPathDestination: Vector3? = nil
local LastPathTime = 0

local PatrolDestination: Vector3? = nil
local PatrolCreated = 0

local LastShot = 0

local Magazine =
	CONFIG.MagazineSize

local ReserveAmmo =
	CONFIG.ReserveAmmo

local Reloading = false
local ReloadFinished = 0

local RNG = Random.new()

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
		ProjectileFolder,
	}

	params.IgnoreWater = true

	return params
end

---------------------------------------------------------------------
-- PLAYER CHARACTER
---------------------------------------------------------------------

local function getPlayerCharacter(player: Player)

	local character =
		player.Character

	if not character then
		return nil
	end

	local humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not humanoid
		or not root
		or humanoid.Health <= 0 then

		return nil
	end

	return character,
		humanoid,
		root
end

---------------------------------------------------------------------
-- LINE OF SIGHT
---------------------------------------------------------------------

local function canSee(character: Model): boolean

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

		local origin =
			Head.Position

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
-- 360 TARGET SEARCH
---------------------------------------------------------------------

local function findTarget(): Player?

	local best: Player? = nil
	local bestDistance = math.huge

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

		if distance
			> CONFIG.DetectionRadius then

			continue
		end

		if distance >= bestDistance then
			continue
		end

		if not canSee(character) then
			continue
		end

		best = player
		bestDistance = distance
	end

	return best
end

---------------------------------------------------------------------
-- PATHFINDING
---------------------------------------------------------------------

local function computePath(
	destination: Vector3
): boolean

	local path =
		PathfindingService:CreatePath({

			AgentRadius =
				CONFIG.AgentRadius,

			AgentHeight =
				CONFIG.AgentHeight,

			AgentCanJump =
				CONFIG.AgentCanJump,
		})

	local ok =
		pcall(function()

			path:ComputeAsync(
				Root.Position,
				destination
			)
		end)

	if not ok
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

local function needsRepath(
	destination: Vector3,
	movingTarget: boolean
)

	if #Waypoints == 0 then
		return true
	end

	if movingTarget
		and os.clock() - LastPathTime
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
-- FOLLOW PATH
---------------------------------------------------------------------

local function followPath()

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
	destination: Vector3,
	movingTarget: boolean
)

	if needsRepath(
		destination,
		movingTarget
	) then

		if not computePath(destination) then

			-- fallback
			Humanoid:MoveTo(destination)

			return
		end
	end

	followPath()
end

---------------------------------------------------------------------
-- RANDOM PATROL POSITION
---------------------------------------------------------------------

local function makePatrolDestination(): Vector3?

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

				rayParams()
			)

		if not result then
			continue
		end

		local destination =
			result.Position
			+ Vector3.new(
				0,
				2,
				0
			)

		if computePath(destination) then
			return destination
		end
	end

	return nil
end

---------------------------------------------------------------------
-- PATROL
---------------------------------------------------------------------

local function patrol()

	local needsNew =
		PatrolDestination == nil

	if PatrolDestination
		and (
			Root.Position
			- PatrolDestination
		).Magnitude <= 6 then

		needsNew = true
	end

	if PatrolDestination
		and os.clock()
			- PatrolCreated
			>= CONFIG.PatrolTimeout then

		needsNew = true
	end

	if needsNew then

		PatrolDestination =
			makePatrolDestination()

		PatrolCreated =
			os.clock()

		Waypoints = {}
	end

	if PatrolDestination then

		moveTo(
			PatrolDestination,
			false
		)
	end
end

---------------------------------------------------------------------
-- AIM POSITION
---------------------------------------------------------------------

local function getAimPosition(
	character: Model,
	targetRoot: BasePart
): Vector3

	local part: BasePart =
		targetRoot

	local head =
		character:FindFirstChild("Head")

	if CONFIG.PreferHead
		and head
		and head:IsA("BasePart")
		and RNG:NextNumber()
			<= CONFIG.HeadChance then

		part = head
	end

	return part.Position
end

---------------------------------------------------------------------
-- SPREAD
---------------------------------------------------------------------

local function applySpread(
	direction: Vector3
): Vector3

	local spread =
		math.rad(
			CONFIG.SpreadDegrees
		)

	if spread <= 0 then
		return direction.Unit
	end

	local yaw =
		RNG:NextNumber(
			-spread,
			spread
		)

	local pitch =
		RNG:NextNumber(
			-spread,
			spread
		)

	local base =
		CFrame.lookAt(
			Vector3.zero,
			direction.Unit
		)

	return (
		base
		* CFrame.Angles(
			pitch,
			yaw,
			0
		)
	).LookVector
end

---------------------------------------------------------------------
-- FIND HUMANOID
---------------------------------------------------------------------

local function humanoidFromHit(
	instance: Instance
)

	local current: Instance? =
		instance

	while current
		and current ~= Workspace do

		if current:IsA("Model") then

			local humanoid =
				current:
					FindFirstChildOfClass(
						"Humanoid"
					)

			if humanoid then
				return humanoid, current
			end
		end

		current = current.Parent
	end

	return nil
end

---------------------------------------------------------------------
-- FRIENDLY CHARACTER
---------------------------------------------------------------------

local function friendlyCharacter(
	character: Model
): boolean

	local player =
		Players:GetPlayerFromCharacter(
			character
		)

	if not player then
		return false
	end

	return not isEnemy(player)
end

---------------------------------------------------------------------
-- BULLET HIT
---------------------------------------------------------------------

local function bulletHit(
	result: RaycastResult
)

	local humanoid,
		character =
		humanoidFromHit(
			result.Instance
		)

	if not humanoid
		or not character then

		-- wall / floor
		return
	end

	if character == NPC then
		return
	end

	if friendlyCharacter(
		character
	) then

		return
	end

	if humanoid.Health <= 0 then
		return
	end

	local damage =
		CONFIG.BodyDamage

	if result.Instance.Name
		== "Head" then

		damage =
			CONFIG.HeadDamage
	end

	-------------------------------------------------------------
	-- Урон ТОЛЬКО после фактического попадания.
	-------------------------------------------------------------

	humanoid:TakeDamage(
		damage
	)
end

---------------------------------------------------------------------
-- SPAWN BULLET
---------------------------------------------------------------------

local function spawnBullet(
	origin: Vector3,
	direction: Vector3
)

	local part =
		Instance.new("Part")

	part.Name = "BotBullet"

	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false

	part.CastShadow = false

	part.Material =
		Enum.Material.Neon

	part.Size =
		CONFIG.BulletSize

	part.CFrame =
		CFrame.lookAt(
			origin,
			origin + direction
		)

	part.Parent =
		ProjectileFolder

	table.insert(
		Bullets,
		{
			Part = part,

			Position = origin,

			Velocity =
				direction.Unit
				* CONFIG.BulletSpeed,

			Distance = 0,

			Params =
				rayParams(),
		}
	)
end

---------------------------------------------------------------------
-- BULLET SIMULATION
---------------------------------------------------------------------

RunService.Heartbeat:
	Connect(function(dt)

		for index = #Bullets, 1, -1 do

			local bullet =
				Bullets[index]

			local part =
				bullet.Part

			if not part.Parent then

				table.remove(
					Bullets,
					index
				)

				continue
			end

			local movement =
				bullet.Velocity
				* dt

			---------------------------------------------------------
			-- Каждый кадр raycast между старой и новой позицией.
			---------------------------------------------------------

			local result =
				Workspace:Raycast(

					bullet.Position,

					movement,

					bullet.Params
				)

			if result then

				part.Position =
					result.Position

				bulletHit(
					result
				)

				part:Destroy()

				table.remove(
					Bullets,
					index
				)

				continue
			end

			bullet.Position +=
				movement

			bullet.Distance +=
				movement.Magnitude

			if bullet.Distance
				>= CONFIG.BulletRange then

				part:Destroy()

				table.remove(
					Bullets,
					index
				)

				continue
			end

			part.CFrame =
				CFrame.lookAt(

					bullet.Position,

					bullet.Position
						+ bullet.Velocity.Unit
				)
		end
	end)

---------------------------------------------------------------------
-- RELOAD
---------------------------------------------------------------------

local function startReload()

	if Reloading
		or ReserveAmmo <= 0 then

		return
	end

	Reloading = true

	ReloadFinished =
		os.clock()
		+ CONFIG.ReloadTime
end

local function updateReload()

	if not Reloading then
		return
	end

	if os.clock()
		< ReloadFinished then

		return
	end

	local missing =
		CONFIG.MagazineSize
		- Magazine

	local amount =
		math.min(
			missing,
			ReserveAmmo
		)

	Magazine += amount
	ReserveAmmo -= amount

	Reloading = false
end

---------------------------------------------------------------------
-- SHOOT
---------------------------------------------------------------------

local function shoot(
	targetPosition: Vector3
)

	if Reloading then
		return
	end

	if Magazine <= 0 then

		startReload()

		return
	end

	if os.clock() - LastShot
		< CONFIG.FireDelay then

		return
	end

	local origin =
		Head.Position
		+ Head.CFrame.LookVector
			* 1.2

	local direction =
		targetPosition - origin

	if direction.Magnitude
		> CONFIG.BulletRange then

		return
	end

	LastShot =
		os.clock()

	Magazine -= 1

	spawnBullet(
		origin,
		applySpread(direction)
	)

	if Magazine <= 0 then
		startReload()
	end
end

---------------------------------------------------------------------
-- PROCESS TARGET
---------------------------------------------------------------------

local function processTarget(
	player: Player
): boolean

	if not isEnemy(player) then

		Target = nil

		return false
	end

	local character,
		_,
		targetRoot =
		getPlayerCharacter(player)

	if not character then

		Target = nil

		return false
	end

	local distance =
		(
			targetRoot.Position
			- Root.Position
		).Magnitude

	-------------------------------------------------------------
	-- VISIBLE
	-------------------------------------------------------------

	if canSee(character) then

		LastSeenPosition =
			targetRoot.Position

		LastSeenTime =
			os.clock()

		local aim =
			getAimPosition(
				character,
				targetRoot
			)

		---------------------------------------------------------
		-- FAR
		---------------------------------------------------------

		if distance
			> CONFIG.ShootingRange then

			moveTo(
				targetRoot.Position,
				true
			)

			return true
		end

		---------------------------------------------------------
		-- COMBAT MOVEMENT
		---------------------------------------------------------

		if distance
			> CONFIG.StopDistance then

			moveTo(
				targetRoot.Position,
				true
			)

		else

			Humanoid:MoveTo(
				Root.Position
			)
		end

		---------------------------------------------------------
		-- FIRE
		---------------------------------------------------------

		shoot(aim)

		return true
	end

	-------------------------------------------------------------
	-- LOST TARGET
	-------------------------------------------------------------

	if LastSeenPosition
		and os.clock()
			- LastSeenTime
			<= CONFIG.LostTargetTime then

		moveTo(
			LastSeenPosition,
			false
		)

		return true
	end

	Target = nil

	return false
end

---------------------------------------------------------------------
-- DETECTION
---------------------------------------------------------------------

local function updateDetection()

	if os.clock() - LastDetection
		< CONFIG.DetectionInterval then

		return
	end

	LastDetection =
		os.clock()

	-------------------------------------------------------------
	-- Сначала валидируем текущую.
	-------------------------------------------------------------

	if Target then

		local character,
			humanoid =
			getPlayerCharacter(Target)

		if character
			and humanoid
			and humanoid.Health > 0
			and isEnemy(Target) then

			return
		end
	end

	Target =
		findTarget()
end

---------------------------------------------------------------------
-- MAIN LOOP
---------------------------------------------------------------------

task.spawn(function()

	while NPC.Parent
		and Humanoid.Health > 0 do

		updateReload()

		updateDetection()

		if Target then

			if processTarget(Target) then

				task.wait(
					CONFIG.ThinkInterval
				)

				continue
			end
		end

		---------------------------------------------------------
		-- Ни одного врага:
		-- сам гуляет по карте.
		---------------------------------------------------------

		patrol()

		task.wait(
			CONFIG.ThinkInterval
		)
	end
end)

print("[AutoBot] running")
