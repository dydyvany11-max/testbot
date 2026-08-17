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

	-----------------------------------------------------------------
	-- AI
	-----------------------------------------------------------------

	ThinkInterval = 0.025,
	DetectionInterval = 0.035,

	TeamCheck = true,

	-- Практически вся карта.
	GlobalChaseRadius = 8000,

	-- Любой видимый враг в этом радиусе может прервать погоню.
	InterruptRadius = 450,

	-- Чтобы камера не прыгала между двумя почти одинаковыми целями.
	ThreatSwitchMargin = 15,
	ThreatSwitchCooldown = 0.20,

	-----------------------------------------------------------------
	-- AIM
	-----------------------------------------------------------------

	-- Быстрое доведение.
	AimSpeed = 48,

	-- Быстро следит за перемещением цели.
	AimPositionSpeed = 38,

	-- Когда цели нет, камера следует направлению тела.
	BodyCameraSpeed = 12,

	AimHead = true,

	-- Стабильная точка головы относительно Root.
	HeadOffsetY = 1.55,

	-- Очень точное наведение.
	FireAimTolerance = 1.25,

	-----------------------------------------------------------------
	-- COMBAT
	-----------------------------------------------------------------

	AttackRange = 300,

	-- Подходит до этой дистанции.
	StopToShootDistance = 70,

	-- Если уже остановился, снова начинает погоню только после 85.
	-- Это убирает дёргание туда-сюда около границы.
	ResumeChaseDistance = 85,

	-- Очень короткая стабилизация.
	AimSettleTime = 0.04,

	-- ~13 выстрелов/сек максимум для автоматического оружия.
	FireDelay = 0.075,

	-----------------------------------------------------------------
	-- PATH
	-----------------------------------------------------------------

	AgentRadius = 2,
	AgentHeight = 5,

	AgentCanJump = true,
	AgentCanClimb = false,

	WaypointReachDistance = 4,

	-- Быстро перестраиваем путь за движущимся игроком.
	RepathInterval = 0.28,

	RepathDistance = 5,

	-----------------------------------------------------------------
	-- PATROL
	-----------------------------------------------------------------

	PatrolMinDistance = 70,
	PatrolMaxDistance = 180,

	PatrolTimeout = 8,

	-----------------------------------------------------------------
	-- BUY
	-----------------------------------------------------------------

	AutoBuy = true,
	BuyDelay = 1.0,

	-----------------------------------------------------------------
	-- DEBUG
	-----------------------------------------------------------------

	Debug = true,
}

---------------------------------------------------------------------
-- CHARACTER STATE
---------------------------------------------------------------------

local Character = nil
local Humanoid = nil
local Root = nil
local Head = nil

---------------------------------------------------------------------
-- TARGET STATE
---------------------------------------------------------------------

-- Цель, к которой бот идёт через всю карту.
local ChaseTarget = nil

-- Цель, с которой бот прямо сейчас дерётся.
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
-- PATROL STATE
---------------------------------------------------------------------

local PatrolDestination = nil
local PatrolCreated = 0

local RNG = Random.new()

---------------------------------------------------------------------
-- PLAYER CONTROLS
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

		Controls = playerModule:GetControls()

		Controls:Disable()

		if CONFIG.Debug then
			print("[BOT] PlayerModule controls disabled")
		end
	end)
end

---------------------------------------------------------------------
-- CAMERA OWNERSHIP
---------------------------------------------------------------------

local function takeCameraControl()

	local camera = Workspace.CurrentCamera

	if not camera then
		return
	end

	if camera.CFrame.LookVector.Magnitude > 0.01 then

		CameraForward =
			camera.CFrame.LookVector.Unit
	end

	camera.CameraType =
		Enum.CameraType.Scriptable
end

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

	-------------------------------------------------------------
	-- Скорость игры не трогаем.
	-------------------------------------------------------------

	Humanoid.AutoRotate = true

	ChaseTarget = nil
	CombatTarget = nil

	AimPosition = nil
	SmoothedAimPosition = nil

	AimSettlingSince = nil
	FiringStance = false

	Waypoints = {}

	LastPathDestination = nil

	PatrolDestination = nil

	disableControls()

	task.defer(function()

		task.wait(0.1)

		takeCameraControl()
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

	local character = player.Character

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

	if not player
		or player == LocalPlayer then

		return false
	end

	if not CONFIG.TeamCheck then
		return true
	end

	-------------------------------------------------------------
	-- Standard Teams.
	-------------------------------------------------------------

	if LocalPlayer.Team
		and player.Team
		and LocalPlayer.Team == player.Team then

		return false
	end

	-------------------------------------------------------------
	-- Team attribute.
	-------------------------------------------------------------

	local myTeam =
		LocalPlayer:GetAttribute("Team")

	local enemyTeam =
		player:GetAttribute("Team")

	if myTeam ~= nil
		and enemyTeam ~= nil
		and myTeam == enemyTeam then

		return false
	end

	-------------------------------------------------------------
	-- Side attribute.
	-------------------------------------------------------------

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
-- LINE OF SIGHT
---------------------------------------------------------------------

local function canSee(character)

	if not character or not Head then
		return false
	end

	local targetParts = {

		character:FindFirstChild("Head"),

		character:FindFirstChild(
			"HumanoidRootPart"
		),
	}

	for _, part in ipairs(
		targetParts
	) do

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
-- FIND NEAREST ENEMY
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
-- FIND VISIBLE THREAT
---------------------------------------------------------------------

local function findVisibleThreat()

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

			bestDistance = distance
			best = player
		end
	end

	return best,
		bestDistance
end

---------------------------------------------------------------------
-- STABLE HEAD AIM
---------------------------------------------------------------------
--
-- НЕ используем Head.Position напрямую.
--
-- Голова качается от running animation.
-- Поэтому используем стабильную точку над HumanoidRootPart.
---------------------------------------------------------------------

local function getAimPosition(
	character,
	targetRoot
)

	if CONFIG.AimHead then

		return targetRoot.Position
			+ Vector3.new(
				0,
				CONFIG.HeadOffsetY,
				0
			)
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
-- CAMERA LOOP
---------------------------------------------------------------------
--
-- Scriptable:
--
-- стандартный CameraModule больше не пытается
-- отвернуть нас обратно.
--
-- AimPosition есть:
--      камера -> враг
--
-- AimPosition нет:
--      камера -> направление тела
---------------------------------------------------------------------

local CAMERA_BIND =
	"AutoBotCamera"

RunService:UnbindFromRenderStep(
	CAMERA_BIND
)

RunService:BindToRenderStep(

	CAMERA_BIND,

	Enum.RenderPriority.Last.Value,

	function(dt)

		if not Character
			or not Root
			or not Head
			or not Humanoid
			or Humanoid.Health <= 0 then

			return
		end

		local camera =
			Workspace.CurrentCamera

		if not camera then
			return
		end

		if camera.CameraType
			~= Enum.CameraType.Scriptable then

			camera.CameraType =
				Enum.CameraType.Scriptable
		end

		---------------------------------------------------------
		-- Camera origin.
		---------------------------------------------------------

		local cameraPosition =
			Head.Position
			+ Vector3.new(
				0,
				0.12,
				0
			)

		---------------------------------------------------------
		-- AIM TARGET
		---------------------------------------------------------

		if AimPosition then

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
					SmoothedAimPosition:Lerp(
						AimPosition,
						targetAlpha
					)
			end

			local desired =
				SmoothedAimPosition
				- cameraPosition

			if desired.Magnitude > 0.01 then

				local aimAlpha =
					1
					- math.exp(
						-CONFIG.AimSpeed
						* dt
					)

				CameraForward =
					CameraForward:Lerp(
						desired.Unit,
						aimAlpha
					)

				if CameraForward.Magnitude
					> 0.01 then

					CameraForward =
						CameraForward.Unit
				end
			end

		else

			-----------------------------------------------------
			-- No visible enemy.
			--
			-- Camera follows where character is running.
			-----------------------------------------------------

			SmoothedAimPosition = nil

			local bodyDirection =
				Root.CFrame.LookVector

			if bodyDirection.Magnitude > 0.01 then

				local bodyAlpha =
					1
					- math.exp(
						-CONFIG.BodyCameraSpeed
						* dt
					)

				CameraForward =
					CameraForward:Lerp(
						bodyDirection.Unit,
						bodyAlpha
					)

				if CameraForward.Magnitude
					> 0.01 then

					CameraForward =
						CameraForward.Unit
				end
			end
		end

		---------------------------------------------------------
		-- ONE camera write per frame.
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
			warn("[PATH]", err)
		end

		Waypoints = {}

		return false
	end

	if path.Status
		~= Enum.PathStatus.Success then

		if CONFIG.Debug then

			warn(
				"[PATH STATUS]",
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

	-------------------------------------------------------------
	-- WAYPOINT REACHED
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
	-- Pathfinding jump only.
	-------------------------------------------------------------

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

	if not Root
		or not Humanoid then

		return
	end

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
-- WEAPON HELPERS
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

	scan(
		LocalPlayer:
			FindFirstChildOfClass(
				"Backpack"
			)
	)

	return tools
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
		string.lower(tool.Name)

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
					"[WEAPON]",
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
-- FIRE WEAPON
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
		return false
	end

	-------------------------------------------------------------
	-- Custom local weapon handler.
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
			"[FIRE]",
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

local BUY_NAMES = {

	"BuyWeapon",
	"PurchaseWeapon",

	"BuyItem",
	"PurchaseItem",
}

local function tryBuyObject(
	object,
	weaponName
)

	if object:IsA(
		"BindableEvent"
	) then

		object:Fire(
			weaponName
		)

		return true
	end

	if object:IsA(
		"BindableFunction"
	) then

		local success, result =
			pcall(function()

				return object:
					Invoke(
						weaponName
					)
			end)

		return success
			and result ~= false
	end

	return false
end

---------------------------------------------------------------------
-- MODULE SHOP ADAPTER
---------------------------------------------------------------------

local SHOP_METHOD_NAMES = {

	"BuyWeapon",
	"PurchaseWeapon",

	"BuyItem",
	"PurchaseItem",

	"Buy",
	"Purchase",
}

local function tryShopModules(
	weaponName
)

	local roots = {

		ReplicatedStorage,

		LocalPlayer:
			FindFirstChild(
				"PlayerScripts"
			),
	}

	for _, rootObject in ipairs(
		roots
	) do

		if not rootObject then
			continue
		end

		for _, object in ipairs(
			rootObject:GetDescendants()
		) do

			if not object:IsA(
				"ModuleScript"
			) then

				continue
			end

			local lower =
				string.lower(
					object.Name
				)

			if not string.find(
				lower,
				"shop",
				1,
				true
			)
				and not string.find(
					lower,
					"buy",
					1,
					true
				) then

				continue
			end

			local success,
				module =
				pcall(
					require,
					object
				)

			if not success
				or type(module)
					~= "table" then

				continue
			end

			for _, methodName in ipairs(
				SHOP_METHOD_NAMES
			) do

				local method =
					module[
						methodName
					]

				if type(method)
					== "function" then

					local called =
						pcall(function()

							method(
								module,
								weaponName
							)
						end)

					if called then

						if CONFIG.Debug then

							print(
								"[BUY MODULE]",
								object.Name,
								methodName,
								weaponName
							)
						end

						return true
					end
				end
			end
		end
	end

	return false
end

---------------------------------------------------------------------
-- BUY WEAPON
---------------------------------------------------------------------

local function buyWeapon(
	weaponName
)

	local roots = {

		ReplicatedStorage,

		LocalPlayer:
			FindFirstChild(
				"PlayerGui"
			),

		LocalPlayer:
			FindFirstChild(
				"PlayerScripts"
			),
	}

	-------------------------------------------------------------
	-- Bindable adapters first.
	-------------------------------------------------------------

	for _, rootObject in ipairs(
		roots
	) do

		if rootObject then

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

					if tryBuyObject(
						object,
						weaponName
					) then

						if CONFIG.Debug then

							print(
								"[BUY]",
								weaponName
							)
						end

						return true
					end
				end
			end
		end
	end

	-------------------------------------------------------------
	-- Then ShopController-style modules.
	-------------------------------------------------------------

	return tryShopModules(
		weaponName
	)
end

---------------------------------------------------------------------
-- AUTO BUY
---------------------------------------------------------------------

local function autoBuy()

	if not CONFIG.AutoBuy then
		return
	end

	-------------------------------------------------------------
	-- DEAGLE
	-------------------------------------------------------------

	for _, weapon in ipairs({

		"Deagle",
		"Desert Eagle",

	}) do

		if buyWeapon(weapon) then
			break
		end
	end

	task.wait(0.08)

	-------------------------------------------------------------
	-- AK / M4
	-------------------------------------------------------------

	for _, weapon in ipairs({

		"AK47",
		"AK-47",

		"M4A1",
		"M4A4",
		"M4",

	}) do

		if buyWeapon(weapon) then
			break
		end
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

	-------------------------------------------------------------
	-- CHASE TARGET
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
	-- Is current CombatTarget still visible?
	-------------------------------------------------------------

	local currentCombatVisible =
		false

	local currentCombatDistance =
		math.huge

	if targetValid(
		CombatTarget
	) then

		local character =
			CombatTarget.Character

		if character
			and canSee(character) then

			currentCombatVisible =
				true

			currentCombatDistance =
				distanceTo(
					CombatTarget
				)
		end
	end

	-------------------------------------------------------------
	-- Find another direct-contact enemy.
	-------------------------------------------------------------

	local threat,
		threatDistance =
		findVisibleThreat()

	if threat then

		local shouldSwitch =
			false

		if not currentCombatVisible then

			shouldSwitch = true

		elseif threat
			== CombatTarget then

			shouldSwitch = false

		elseif now
			- LastThreatSwitch
			>= CONFIG.ThreatSwitchCooldown
			and threatDistance
				+ CONFIG.ThreatSwitchMargin
				< currentCombatDistance then

			-----------------------------------------------------
			-- Новый враг должен быть реально заметно ближе,
			-- иначе не прыгаем между двумя головами.
			-----------------------------------------------------

			shouldSwitch = true
		end

		if shouldSwitch then

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

			if CONFIG.Debug then

				print(
					"[COMBAT]",
					threat.Name
				)
			end
		end
	end

	-------------------------------------------------------------
	-- Current combat target gone?
	-------------------------------------------------------------

	if not currentCombatVisible
		and not threat then

		CombatTarget =
			nil
	end

	-------------------------------------------------------------
	-- Chase target itself visible?
	-------------------------------------------------------------

	if not CombatTarget
		and targetValid(
			ChaseTarget
		) then

		local chaseCharacter =
			ChaseTarget.Character

		if chaseCharacter
			and canSee(
				chaseCharacter
			) then

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

---------------------------------------------------------------------
-- PROCESS COMBAT
---------------------------------------------------------------------

local function processCombatTarget(
	player
)

	if not targetValid(
		player
	) then

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

	-------------------------------------------------------------
	-- Lost LOS.
	-------------------------------------------------------------

	if not canSee(character) then

		AimPosition =
			nil

		SmoothedAimPosition =
			nil

		AimSettlingSince =
			nil

		FiringStance =
			false

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
	-- ALWAYS TRACK HEAD WHILE VISIBLE.
	-------------------------------------------------------------

	AimPosition =
		headPosition

	-------------------------------------------------------------
	-- Enter firing stance.
	-------------------------------------------------------------

	if not FiringStance
		and distance
			<= CONFIG.StopToShootDistance then

		FiringStance =
			true

		AimSettlingSince =
			os.clock()
	end

	-------------------------------------------------------------
	-- Leave firing stance only when target moved well away.
	-------------------------------------------------------------

	if FiringStance
		and distance
			> CONFIG.ResumeChaseDistance then

		FiringStance =
			false

		AimSettlingSince =
			nil
	end

	-------------------------------------------------------------
	-- RUN + AIM
	-------------------------------------------------------------

	if not FiringStance then

		AimSettlingSince =
			nil

		moveTo(
			targetRoot.Position
		)

		return true
	end

	-------------------------------------------------------------
	-- STOP + AIM + FIRE
	-------------------------------------------------------------

	stopMovement()

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
	-- Already aiming accurately?
	-------------------------------------------------------------

	if cameraAngleTo(
		headPosition
	) > CONFIG.FireAimTolerance then

		return true
	end

	-------------------------------------------------------------
	-- Final LOS.
	-------------------------------------------------------------

	if not canSee(character) then

		AimSettlingSince =
			nil

		return false
	end

	-------------------------------------------------------------
	-- FIRE
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
-- PROCESS CHASE
---------------------------------------------------------------------

local function processChaseTarget(
	player
)

	if not targetValid(
		player
	) then

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

	-------------------------------------------------------------
	-- Если виден, updateTargets сам сделает его CombatTarget.
	--
	-- Пока скрыт — просто Pathfinding.
	-------------------------------------------------------------

	AimPosition = nil
	SmoothedAimPosition = nil

	AimSettlingSince = nil
	FiringStance = false

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
					-- VISIBLE COMBAT TARGET
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

							AimSettlingSince =
								nil

							FiringStance =
								false
						end
					end

					-------------------------------------------------
					-- GLOBAL CHASE
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

print("[AutoBot] AGGRESSIVE CLIENT BOT RUNNING")
