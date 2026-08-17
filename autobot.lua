-- StarterPlayerScripts/AutoBot.client.lua

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local CONFIG = {
	DetectionRadius = 250,
	AttackRange = 120,
	RepathInterval = 0.5,
	ThinkInterval = 0.08,

	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
}

local character
local humanoid
local root

local targetPlayer

local waypoints = {}
local waypointIndex = 1
local lastPathTime = 0
local lastPathTarget

local function updateCharacter()
	character = player.Character or player.CharacterAdded:Wait()

	humanoid = character:WaitForChild("Humanoid")
	root = character:WaitForChild("HumanoidRootPart")

	-- Важно: никакого Root.CFrame.
	humanoid.AutoRotate = true
end

local function raycastParams()
	local params = RaycastParams.new()

	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	return params
end

local function canSee(otherCharacter)
	local otherRoot =
		otherCharacter:FindFirstChild("HumanoidRootPart")

	local head =
		otherCharacter:FindFirstChild("Head")

	local targetPart = head or otherRoot

	if not targetPart then
		return false
	end

	local origin =
		(character:FindFirstChild("Head") or root).Position

	local direction =
		targetPart.Position - origin

	local result = Workspace:Raycast(
		origin,
		direction,
		raycastParams()
	)

	return result ~= nil
		and result.Instance:IsDescendantOf(otherCharacter)
end

local function findTarget()
	local best
	local bestDistance = math.huge

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player then
			continue
		end

		if player.Team
			and otherPlayer.Team == player.Team then
			continue
		end

		local otherCharacter = otherPlayer.Character

		if not otherCharacter then
			continue
		end

		local otherHumanoid =
			otherCharacter:FindFirstChildOfClass("Humanoid")

		local otherRoot =
			otherCharacter:FindFirstChild("HumanoidRootPart")

		if not otherHumanoid
			or not otherRoot
			or otherHumanoid.Health <= 0 then
			continue
		end

		local distance =
			(otherRoot.Position - root.Position).Magnitude

		if distance > CONFIG.DetectionRadius then
			continue
		end

		if distance >= bestDistance then
			continue
		end

		if not canSee(otherCharacter) then
			continue
		end

		best = otherPlayer
		bestDistance = distance
	end

	return best
end

local function computePath(destination)
	local path = PathfindingService:CreatePath({
		AgentRadius = CONFIG.AgentRadius,
		AgentHeight = CONFIG.AgentHeight,
		AgentCanJump = CONFIG.AgentCanJump,
	})

	local success = pcall(function()
		path:ComputeAsync(
			root.Position,
			destination
		)
	end)

	if not success
		or path.Status ~= Enum.PathStatus.Success then

		waypoints = {}
		return false
	end

	waypoints = path:GetWaypoints()

	waypointIndex =
		#waypoints >= 2 and 2 or 1

	lastPathTarget = destination
	lastPathTime = os.clock()

	return true
end

local function moveTowards(destination)
	humanoid.AutoRotate = true

	local needsPath =
		#waypoints == 0
		or os.clock() - lastPathTime
			>= CONFIG.RepathInterval

	if lastPathTarget
		and (
			lastPathTarget - destination
		).Magnitude >= 5 then

		needsPath = true
	end

	if needsPath then
		if not computePath(destination) then
			humanoid:MoveTo(destination)
			return
		end
	end

	local waypoint =
		waypoints[waypointIndex]

	if not waypoint then
		return
	end

	if (
		root.Position - waypoint.Position
	).Magnitude < 4 then

		waypointIndex += 1
		waypoint = waypoints[waypointIndex]

		if not waypoint then
			return
		end
	end

	if waypoint.Action ==
		Enum.PathWaypointAction.Jump then

		humanoid.Jump = true
	end

	humanoid:MoveTo(
		waypoint.Position
	)
end

local function stopMoving()
	humanoid.AutoRotate = true

	humanoid:MoveTo(
		root.Position
	)
end

local function update()
	if humanoid.Health <= 0 then
		return
	end

	targetPlayer = findTarget()

	if not targetPlayer then
		return
	end

	local enemy =
		targetPlayer.Character

	if not enemy then
		return
	end

	local enemyRoot =
		enemy:FindFirstChild("HumanoidRootPart")

	if not enemyRoot then
		return
	end

	local distance =
		(enemyRoot.Position - root.Position).Magnitude

	if distance > CONFIG.AttackRange then
		moveTowards(enemyRoot.Position)
	else
		stopMoving()

		-- Здесь вызывай штатный WeaponController
		-- СВОЕГО place, например:
		--
		-- WeaponController:Fire(enemy.Head.Position)
		--
		-- Не меняем Root.CFrame.
	end
end

updateCharacter()

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	updateCharacter()
end)

while true do
	local ok, err = pcall(update)

	if not ok then
		warn("[AutoBot]", err)
	end

	task.wait(CONFIG.ThinkInterval)
end
