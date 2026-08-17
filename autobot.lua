--!strict
-- AutoBot.client.lua
--
-- StarterPlayer
-- └── StarterPlayerScripts
--     └── AutoBot.client.lua
--
-- НЕ использует:
--   Root.CFrame = ...
--   Character:PivotTo(...)
--   getgenv()
--   firesignal()
--   executor APIs
--
-- AI:
--   patrol
--   pathfinding
--   LOS
--   FOV target detection
--   chase
--   smooth camera aim
--   Tool:Activate()
--   weapon selection
--   optional Buy/Rewards/Replay adapters


---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer


---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local CONFIG = {

	-----------------------------------------------------------------
	-- MOVEMENT
	-----------------------------------------------------------------

	WalkSpeed = 24,

	ThinkInterval = 0.05,

	-----------------------------------------------------------------
	-- DETECTION
	-----------------------------------------------------------------

	DetectionRadius = 500,

	DetectionInterval = 0.08,

	IgnoreSameTeam = true,

	LostTargetTime = 4,

	-----------------------------------------------------------------
	-- AIM
	-----------------------------------------------------------------

	-- Реальный FOV камеры.
	CameraFieldOfView = 95,

	-- УГОЛ, внутри которого бот может выбрать цель.
	--
	-- 180 = почти вся передняя полусфера.
	-- 120 = уже.
	-- 60 = маленький aim FOV.
	AimFOVDegrees = 160,

	-- Чем больше — тем быстрее камера доворачивается.
	AimSpeed = 22,

	PreferHead = true,

	HeadAimChance = 0.90,

	-- Упреждение.
	Prediction = false,

	EstimatedBulletSpeed = 900,

	-----------------------------------------------------------------
	-- COMBAT
	-----------------------------------------------------------------

	AttackRange = 180,

	-- Если ближе — прекращаем идти вперёд.
	StopDistance = 35,

	FireDelay = 0.09,

	-----------------------------------------------------------------
	-- PATHFINDING
	-----------------------------------------------------------------

	RepathInterval = 0.30,

	RepathDistance = 5,

	WaypointDistance = 4,

	AgentRadius = 2,

	AgentHeight = 5,

	AgentCanJump = true,

	AgentCanClimb = false,

	-----------------------------------------------------------------
	-- PATROL
	-----------------------------------------------------------------

	-- Если Workspace.PatrolPoints существует,
	-- ходит между Parts.

	PatrolFolder = "PatrolPoints",

	-- Иначе сам выбирает случайные места.
	RandomPatrolRadius = 250,

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
	-- BUY
	-----------------------------------------------------------------

	AutoBuy = true,

	BuyDelayAfterSpawn = 1.5,

	BuyPriority = {
		"AWP",
		"AK47",
		"AK-47",
		"M4A1",
		"M4A4",
		"Galil",
		"Famas",
		"P90",
		"MP5",
		"Deagle",
	},

	-----------------------------------------------------------------
	-- REWARDS
	-----------------------------------------------------------------

	AutoRewards = true,

	FirstRewardCheck = 10,

	RewardInterval = 300,

	Rewards = {
		"Hourly",
		"Daily",
		"Weekly",
		"Monthly",
	},

	-----------------------------------------------------------------
	-- MATCH
	-----------------------------------------------------------------

	AutoReplay = true,

	ReplayDelay = 60,

	PreferredSide = "T",

	ResultTexts = {
		"Victory",
		"Defeat",
		"Results",
		"Match Results",
		"Winner",
	},
}


---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local Character: Model? = nil
local Humanoid: Humanoid? = nil
local Root: BasePart? = nil
local Head: BasePart? = nil

local TargetPlayer: Player? = nil

local LastSeenPosition: Vector3? = nil
local LastSeenTime = 0

local LastDetection = 0
local LastShot = 0

local CurrentAimPosition: Vector3? = nil

local PathWaypoints = {}
local PathIndex = 1

local LastPathPosition: Vector3? = nil
local LastPathTime = 0

local SpawnPosition: Vector3? = nil

local PatrolPoints = {}
local PatrolIndex = 1

local RandomDestination: Vector3? = nil
local NextPatrolTime = 0

local HandlingMatchEnd = false


---------------------------------------------------------------------
-- SMALL UTIL
---------------------------------------------------------------------

local function normalize(value: any): string

	return string.lower(
		tostring(value or "")
	)
end


---------------------------------------------------------------------
-- OPTIONAL GAME ACTION ADAPTER
---------------------------------------------------------------------
--
-- Здесь НЕТ эмуляции клавиш/кликов.
--
-- Скрипт ищет BindableFunction / BindableEvent с названием:
--
-- BuyWeapon
-- ReloadWeapon
-- ClaimReward
-- CloseResults
-- PlayAgain
-- SelectTeam
--
-- Их можно положить, например, в PlayerGui или ReplicatedStorage.
--
-- Или заменить эту функцию вызовами твоих настоящих
-- ShopController / RewardsController / MatchController.
---------------------------------------------------------------------

local function findLocalAction(name: string): Instance?

	local places = {
		LocalPlayer:FindFirstChild("PlayerGui"),
		Character,
		LocalPlayer:FindFirstChild("Backpack"),
		ReplicatedStorage,
	}

	for _, parent in ipairs(places) do

		if not parent then
			continue
		end

		local result =
			parent:FindFirstChild(
				name,
				true
			)

		if result
			and (
				result:IsA("BindableFunction")
				or result:IsA("BindableEvent")
			) then

			return result
		end
	end

	return nil
end


local function runAction(
	name: string,
	...: any
): (boolean, any)

	local action =
		findLocalAction(name)

	if not action then
		return false, nil
	end

	if action:IsA("BindableFunction") then

		local success, result =
			pcall(function()

				return action:Invoke(...)

			end)

		return success, result
	end

	if action:IsA("BindableEvent") then

		action:Fire(...)

		return true, nil
	end

	return false, nil
end


---------------------------------------------------------------------
-- CHARACTER
---------------------------------------------------------------------

local function setupCharacter(
	character: Model
)

	Character = character

	Humanoid =
		character:WaitForChild(
			"Humanoid"
		) :: Humanoid

	Root =
		character:WaitForChild(
			"HumanoidRootPart"
		) :: BasePart

	Head =
		character:FindFirstChild(
			"Head"
		) :: BasePart?

	Humanoid.AutoRotate = true

	Humanoid.WalkSpeed =
		CONFIG.WalkSpeed

	SpawnPosition =
		Root.Position

	TargetPlayer = nil

	LastSeenPosition = nil

	CurrentAimPosition = nil

	PathWaypoints = {}

	RandomDestination = nil

	LastShot = 0

	---------------------------------------------------------------
	-- CAMERA
	---------------------------------------------------------------

	local camera =
		Workspace.CurrentCamera

	if camera then

		camera.FieldOfView =
			CONFIG.CameraFieldOfView
	end

	print(
		"[AutoBot] character ready"
	)
end


---------------------------------------------------------------------
-- PLAYER CHARACTER
---------------------------------------------------------------------

local function getCharacterData(
	player: Player
)

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
		character:FindFirstChild(
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

	return character, humanoid, root
end


---------------------------------------------------------------------
-- ENEMY CHECK
---------------------------------------------------------------------

local function isEnemy(
	player: Player
): boolean

	if player == LocalPlayer then
		return false
	end

	if not CONFIG.IgnoreSameTeam then
		return true
	end

	if LocalPlayer.Team
		and player.Team
		and LocalPlayer.Team
			== player.Team then

		return false
	end

	return true
end


---------------------------------------------------------------------
-- RAYCAST PARAMS
---------------------------------------------------------------------

local function createRaycastParams()

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

local function canSee(
	character: Model
): boolean

	local eye =
		getEyePosition()

	if not eye then
		return false
	end

	local target =
		character:FindFirstChild(
			"Head"
		)
		or character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not target
		or not target:IsA("BasePart") then

		return false
	end

	local direction =
		target.Position - eye

	local result =
		Workspace:Raycast(
			eye,
			direction,
			createRaycastParams()
		)

	if not result then
		return false
	end

	return result.Instance:
		IsDescendantOf(
			character
		)
end


---------------------------------------------------------------------
-- AIM FOV
---------------------------------------------------------------------

local function getAimAngle(
	targetPosition: Vector3
): number

	local camera =
		Workspace.CurrentCamera

	if not camera then
		return math.huge
	end

	local offset =
		targetPosition
		- camera.CFrame.Position

	if offset.Magnitude <= 0.01 then
		return 0
	end

	local direction =
		offset.Unit

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
-- FIND TARGET
---------------------------------------------------------------------

local function findTarget(): Player?

	if not Root then
		return nil
	end

	local bestPlayer = nil

	local bestScore =
		math.huge

	local maxAimAngle =
		CONFIG.AimFOVDegrees / 2

	for _, player
		in ipairs(
			Players:GetPlayers()
		) do

		if not isEnemy(player) then
			continue
		end

		local character,
			humanoid,
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

		if distance
			> CONFIG.DetectionRadius then

			continue
		end

		local targetPart =
			character:
				FindFirstChild("Head")
				or targetRoot

		if not targetPart
			or not targetPart:IsA(
				"BasePart"
			) then

			continue
		end

		-------------------------------------------------------------
		-- AIM FOV
		-------------------------------------------------------------

		local angle =
			getAimAngle(
				targetPart.Position
			)

		if angle > maxAimAngle then
			continue
		end

		-------------------------------------------------------------
		-- LOS
		-------------------------------------------------------------

		if not canSee(character) then
			continue
		end

		-------------------------------------------------------------
		-- SCORE
		--
		-- Предпочитаем цель ближе к центру камеры,
		-- но расстояние тоже учитываем.
		-------------------------------------------------------------

		local score =
			angle * 3
			+ distance * 0.02

		if score < bestScore then

			bestScore =
				score

			bestPlayer =
				player
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
		character:FindFirstChild(
			"Head"
		)

	if CONFIG.PreferHead
		and head
		and head:IsA("BasePart")
		and math.random()
			<= CONFIG.HeadAimChance then

		targetPart =
			head
	end

	local position =
		targetPart.Position

	---------------------------------------------------------------
	-- PREDICTION
	---------------------------------------------------------------

	if CONFIG.Prediction then

		local eye =
			getEyePosition()

		if eye then

			local distance =
				(
					position - eye
				).Magnitude

			local travelTime =
				distance
				/ CONFIG.EstimatedBulletSpeed

			position +=
				targetRoot.AssemblyLinearVelocity
				* travelTime
		end
	end

	return position
end


---------------------------------------------------------------------
-- CAMERA AIM
---------------------------------------------------------------------
--
-- НИКАКОГО Root.CFrame.
--
-- Camera вращается отдельно.
---------------------------------------------------------------------

RunService.RenderStepped:
	Connect(function(dt)

		if not CurrentAimPosition then
			return
		end

		local camera =
			Workspace.CurrentCamera

		if not camera then
			return
		end

		local current =
			camera.CFrame

		local desired =
			CFrame.lookAt(
				current.Position,
				CurrentAimPosition
			)

		-------------------------------------------------------------
		-- Framerate-independent smoothing
		-------------------------------------------------------------

		local alpha =
			1
			- math.exp(
				-CONFIG.AimSpeed * dt
			)

		camera.CFrame =
			current:Lerp(
				desired,
				alpha
			)
	end)


---------------------------------------------------------------------
-- PATH
---------------------------------------------------------------------

local function computePath(
	destination: Vector3
): boolean

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

		PathWaypoints = {}

		return false
	end

	PathWaypoints =
		path:GetWaypoints()

	PathIndex =
		#PathWaypoints >= 2
		and 2
		or 1

	LastPathPosition =
		destination

	LastPathTime =
		os.clock()

	return true
end


---------------------------------------------------------------------
-- NEED REPATH
---------------------------------------------------------------------

local function needsRepath(
	destination: Vector3
): boolean

	if #PathWaypoints == 0 then
		return true
	end

	if os.clock()
		- LastPathTime
		>= CONFIG.RepathInterval then

		return true
	end

	if LastPathPosition
		and (
			LastPathPosition
			- destination
		).Magnitude
			>= CONFIG.RepathDistance then

		return true
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
		PathWaypoints[
			PathIndex
		]

	if not waypoint then
		return false
	end

	if (
		Root.Position
		- waypoint.Position
	).Magnitude
		<= CONFIG.WaypointDistance then

		PathIndex += 1

		waypoint =
			PathWaypoints[
				PathIndex
			]

		if not waypoint then
			return false
		end
	end

	if waypoint.Action
		== Enum.PathWaypointAction.Jump then

		Humanoid.Jump =
			true
	end

	Humanoid.AutoRotate =
		true

	Humanoid:MoveTo(
		waypoint.Position
	)

	return true
end


---------------------------------------------------------------------
-- MOVE
---------------------------------------------------------------------

local function moveTowards(
	destination: Vector3
)

	if not Humanoid
		or not Root then

		return
	end

	Humanoid.AutoRotate =
		true

	Humanoid.WalkSpeed =
		CONFIG.WalkSpeed

	if needsRepath(destination) then

		if not computePath(
			destination
		) then

			---------------------------------------------------------
			-- fallback
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
-- LOAD PATROL POINTS
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

	for _, object
		in ipairs(
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
-- RANDOM PATROL
---------------------------------------------------------------------

local function getRandomPatrolPoint(): Vector3?

	if not Root then
		return nil
	end

	local originPosition =
		SpawnPosition
		or Root.Position

	local radius =
		CONFIG.RandomPatrolRadius

	for _ = 1, 5 do

		local candidate =
			originPosition
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
		-- ищем землю
		-------------------------------------------------------------

		local rayOrigin =
			candidate
			+ Vector3.new(
				0,
				150,
				0
			)

		local result =
			Workspace:Raycast(

				rayOrigin,

				Vector3.new(
					0,
					-400,
					0
				),

				createRaycastParams()
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
	-- FIXED POINTS
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

			PathWaypoints = {}

			NextPatrolTime =
				os.clock()
				+ CONFIG.PatrolPause

			return
		end

		moveTowards(
			point.Position
		)

		return
	end

	---------------------------------------------------------------
	-- RANDOM
	---------------------------------------------------------------

	if not RandomDestination then

		RandomDestination =
			getRandomPatrolPoint()

		PathWaypoints = {}
	end

	if not RandomDestination then
		return
	end

	if (
		Root.Position
		- RandomDestination
	).Magnitude <= 6 then

		RandomDestination = nil

		PathWaypoints = {}

		NextPatrolTime =
			os.clock()
			+ CONFIG.PatrolPause

		return
	end

	moveTowards(
		RandomDestination
	)
end


---------------------------------------------------------------------
-- TOOL FIND
---------------------------------------------------------------------

local function findTool(
	name: string
): Tool?

	local wanted =
		normalize(name)

	local places = {
		Character,

		LocalPlayer:
			FindFirstChildOfClass(
				"Backpack"
			),
	}

	for _, parent in ipairs(places) do

		if not parent then
			continue
		end

		for _, child
			in ipairs(
				parent:GetChildren()
			) do

			if not child:IsA("Tool") then
				continue
			end

			local toolName =
				normalize(
					child.Name
				)

			if toolName == wanted
				or string.find(
					toolName,
					wanted,
					1,
					true
				) then

				return child
			end
		end
	end

	return nil
end


---------------------------------------------------------------------
-- CURRENT TOOL
---------------------------------------------------------------------

local function getCurrentTool(): Tool?

	if not Character then
		return nil
	end

	return Character:
		FindFirstChildOfClass(
			"Tool"
		)
end


---------------------------------------------------------------------
-- EQUIP BEST
---------------------------------------------------------------------

local function equipBestWeapon(): Tool?

	if not Humanoid then
		return nil
	end

	for _, name
		in ipairs(
			CONFIG.WeaponPriority
		) do

		local tool =
			findTool(name)

		if tool then

			if tool.Parent
				~= Character then

				Humanoid:
					EquipTool(tool)
			end

			return tool
		end
	end

	---------------------------------------------------------------
	-- fallback любой Tool
	---------------------------------------------------------------

	local current =
		getCurrentTool()

	if current then
		return current
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
				EquipTool(tool)

			return tool
		end
	end

	return nil
end


---------------------------------------------------------------------
-- FIRE
---------------------------------------------------------------------

local function fireWeapon()

	if os.clock()
		- LastShot
		< CONFIG.FireDelay then

		return
	end

	local tool =
		getCurrentTool()
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
	-- Используем штатный Tool.
	---------------------------------------------------------------

	tool:Activate()
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

		-------------------------------------------------------------
		-- Уже есть.
		-------------------------------------------------------------

		if findTool(weapon) then
			continue
		end

		-------------------------------------------------------------
		-- Вызывает локальный ShopController adapter.
		-------------------------------------------------------------

		local success, result =
			runAction(
				"BuyWeapon",
				weapon
			)

		if success
			and result ~= false then

			task.wait(0.15)

			if findTool(weapon) then

				print(
					"[AutoBot] bought",
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

	TargetPlayer = nil

	LastSeenPosition = nil

	CurrentAimPosition = nil

	PathWaypoints = {}
end


---------------------------------------------------------------------
-- TARGET PROCESSING
---------------------------------------------------------------------

local function processTarget(
	player: Player
): boolean

	if not Root
		or not Humanoid then

		return false
	end

	local character,
		targetHumanoid,
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
	-- TARGET VISIBLE
	---------------------------------------------------------------

	if canSee(character) then

		LastSeenTime =
			os.clock()

		LastSeenPosition =
			targetRoot.Position

		CurrentAimPosition =
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

				-----------------------------------------------------
				-- Продолжаем двигаться во время стрельбы.
				-----------------------------------------------------

				moveTowards(
					targetRoot.Position
				)

			else

				stopMovement()
			end

			fireWeapon()

			return true
		end

		-------------------------------------------------------------
		-- CHASE
		-------------------------------------------------------------

		moveTowards(
			targetRoot.Position
		)

		return true
	end

	---------------------------------------------------------------
	-- ЦЕЛЬ СКРЫЛАСЬ
	---------------------------------------------------------------

	CurrentAimPosition =
		nil

	if LastSeenPosition
		and os.clock()
			- LastSeenTime
			<= CONFIG.LostTargetTime then

		moveTowards(
			LastSeenPosition
		)

		return true
	end

	clearTarget()

	return false
end


---------------------------------------------------------------------
-- RESULT TEXT DETECTION
---------------------------------------------------------------------

local function resultScreenVisible(): boolean

	local playerGui =
		LocalPlayer:
			FindFirstChildOfClass(
				"PlayerGui"
			)

	if not playerGui then
		return false
	end

	for _, object
		in ipairs(
			playerGui:GetDescendants()
		) do

		if not (
			object:IsA("TextLabel")
			or object:IsA("TextButton")
		) then

			continue
		end

		if not object.Visible then
			continue
		end

		local text =
			normalize(
				object.Text
			)

		for _, wanted
			in ipairs(
				CONFIG.ResultTexts
			) do

			if string.find(
				text,
				normalize(wanted),
				1,
				true
			) then

				return true
			end
		end
	end

	return false
end


---------------------------------------------------------------------
-- HANDLE MATCH END
---------------------------------------------------------------------

local function handleMatchEnd()

	if HandlingMatchEnd
		or not CONFIG.AutoReplay then

		return
	end

	HandlingMatchEnd =
		true

	clearTarget()

	stopMovement()

	print(
		"[AutoBot] match ended"
	)

	---------------------------------------------------------------
	-- Штатный MatchController должен закрыть результаты.
	---------------------------------------------------------------

	runAction(
		"CloseResults"
	)

	---------------------------------------------------------------
	-- Ждём минуту.
	---------------------------------------------------------------

	task.wait(
		CONFIG.ReplayDelay
	)

	runAction(
		"PlayAgain"
	)

	task.wait(0.5)

	runAction(
		"SelectTeam",
		CONFIG.PreferredSide
	)

	HandlingMatchEnd =
		false
end


---------------------------------------------------------------------
-- REWARDS
---------------------------------------------------------------------

local function claimRewards()

	if not CONFIG.AutoRewards
		or HandlingMatchEnd then

		return
	end

	for _, reward
		in ipairs(
			CONFIG.Rewards
		) do

		local success =
			runAction(
				"ClaimReward",
				reward
			)

		if success then

			print(
				"[AutoBot] reward checked:",
				reward
			)
		end

		task.wait(0.1)
	end
end


---------------------------------------------------------------------
-- DETECTION UPDATE
---------------------------------------------------------------------

local function updateDetection()

	if os.clock()
		- LastDetection
		< CONFIG.DetectionInterval then

		return
	end

	LastDetection =
		os.clock()

	local target =
		findTarget()

	if target then
		TargetPlayer = target
	end
end


---------------------------------------------------------------------
-- MAIN UPDATE
---------------------------------------------------------------------

local function updateAI()

	if HandlingMatchEnd then
		return
	end

	if not Character
		or not Character.Parent
		or not Humanoid
		or not Root then

		return
	end

	if Humanoid.Health <= 0 then

		CurrentAimPosition =
			nil

		return
	end

	---------------------------------------------------------------
	-- гарантируем скорость
	---------------------------------------------------------------

	if Humanoid.WalkSpeed
		~= CONFIG.WalkSpeed then

		Humanoid.WalkSpeed =
			CONFIG.WalkSpeed
	end

	updateDetection()

	---------------------------------------------------------------
	-- TARGET
	---------------------------------------------------------------

	if TargetPlayer then

		if processTarget(
			TargetPlayer
		) then

			return
		end
	end

	---------------------------------------------------------------
	-- NO TARGET -> PATROL
	---------------------------------------------------------------

	CurrentAimPosition =
		nil

	patrol()
end


---------------------------------------------------------------------
-- RESPAWN
---------------------------------------------------------------------

local function onCharacterAdded(
	character: Model
)

	setupCharacter(
		character
	)

	loadPatrolPoints()

	task.delay(
		CONFIG.BuyDelayAfterSpawn,

		function()

			if Humanoid
				and Humanoid.Health > 0 then

				autoBuy()
			end
		end
	)
end


---------------------------------------------------------------------
-- CHARACTER EVENTS
---------------------------------------------------------------------

LocalPlayer.CharacterAdded:
	Connect(onCharacterAdded)

if LocalPlayer.Character then

	task.spawn(
		onCharacterAdded,
		LocalPlayer.Character
	)
end


---------------------------------------------------------------------
-- REWARD LOOP
---------------------------------------------------------------------

task.spawn(function()

	task.wait(
		CONFIG.FirstRewardCheck
	)

	while true do

		claimRewards()

		task.wait(
			CONFIG.RewardInterval
		)
	end
end)


---------------------------------------------------------------------
-- RESULT MONITOR
---------------------------------------------------------------------

task.spawn(function()

	local previousResult =
		false

	while true do

		local visible =
			resultScreenVisible()

		if visible
			and not previousResult then

			task.spawn(
				handleMatchEnd
			)
		end

		previousResult =
			visible

		task.wait(0.5)
	end
end)


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


print(
	"[AutoBot] loaded"
)
