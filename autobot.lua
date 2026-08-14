-- autobot.lua
-- Autonomous test bot for your Roblox test place
-- Move -> aim at head -> shoot -> plant -> collect rewards

if getgenv().TestAutoBot then
    getgenv().TestAutoBot.Enabled = false
    task.wait(0.2)
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Bot = {
    Enabled = true,

    TeamCheck = true,

    MaxTargetDistance = 600,
    ShootDistance = 220,
    StopDistance = 16,

    MoveUpdate = 0.06,
    FireInterval = 0.07,

    Strafe = true,
    StrafeDistance = 8,

    AutoPlant = true,
    AutoReward = true,
    InteractionDistance = 12,

    Debug = true,
}

getgenv().TestAutoBot = Bot

--------------------------------------------------
-- DEBUG
--------------------------------------------------

local function log(...)
    if Bot.Debug then
        print("[TEST BOT]", ...)
    end
end

--------------------------------------------------
-- CHARACTER
--------------------------------------------------

local function getCharacter()
    local char = LocalPlayer.Character

    if not char then
        return nil
    end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root then
        return nil
    end

    return char, humanoid, root
end

--------------------------------------------------
-- PLAYER STATE
--------------------------------------------------

local function isAlive(player)
    local char = player.Character

    if not char then
        return false
    end

    local humanoid = char:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    if char:GetAttribute("Dead") == true then
        return false
    end

    return true
end

local function isEnemy(player)
    if player == LocalPlayer then
        return false
    end

    if not Bot.TeamCheck then
        return true
    end

    if Workspace:GetAttribute("Gamemode") == "Deathmatch" then
        return true
    end

    local myTeam = LocalPlayer:GetAttribute("Team")
    local theirTeam = player:GetAttribute("Team")

    if myTeam == nil or theirTeam == nil then
        return true
    end

    return myTeam ~= theirTeam
end

--------------------------------------------------
-- TARGET PART
--------------------------------------------------

local function getHead(player)
    local char = player.Character

    if not char then
        return nil
    end

    return char:FindFirstChild("Head")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("HumanoidRootPart")
end

--------------------------------------------------
-- VISIBILITY
--------------------------------------------------

local function canSee(targetCharacter, targetPart)
    local myCharacter = LocalPlayer.Character

    if not myCharacter then
        return false
    end

    Camera = Workspace.CurrentCamera

    local params = RaycastParams.new()

    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        myCharacter,
        Camera,
    }

    params.IgnoreWater = true

    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin

    local result = Workspace:Raycast(
        origin,
        direction,
        params
    )

    if not result then
        return true
    end

    return result.Instance:IsDescendantOf(targetCharacter)
end

--------------------------------------------------
-- FIND TARGET
--------------------------------------------------

local function findTarget()
    local _, _, myRoot = getCharacter()

    if not myRoot then
        return nil
    end

    local bestPlayer = nil
    local bestHead = nil
    local bestDistance = Bot.MaxTargetDistance

    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemy(player) and isAlive(player) then

            local head = getHead(player)
Buy humanoid.health | Spaceship
Buy humanoid.health | Spaceship
humanoid.Health


if head then
                local distance =
                    (myRoot.Position - head.Position).Magnitude

                if distance < bestDistance then

                    if canSee(player.Character, head) then
                        bestDistance = distance
                        bestPlayer = player
                        bestHead = head
                    end
                end
            end
        end
    end

    return bestPlayer, bestHead, bestDistance
end

--------------------------------------------------
-- AIM
--------------------------------------------------

local function aimAt(part)
    if not part then
        return
    end

    Camera = Workspace.CurrentCamera

    Camera.CFrame = CFrame.lookAt(
        Camera.CFrame.Position,
        part.Position
    )
end

--------------------------------------------------
-- SHOOT
--------------------------------------------------

local function shoot()
    Camera = Workspace.CurrentCamera

    local x = Camera.ViewportSize.X / 2
    local y = Camera.ViewportSize.Y / 2

    if mouse1press and mouse1release then
        mouse1press()
        task.wait(0.025)
        mouse1release()
        return
    end

    VirtualInputManager:SendMouseButtonEvent(
        x,
        y,
        0,
        true,
        game,
        0
    )

    task.wait(0.025)

    VirtualInputManager:SendMouseButtonEvent(
        x,
        y,
        0,
        false,
        game,
        0
    )
end

--------------------------------------------------
-- COMBAT MOVEMENT
--------------------------------------------------

local strafeDirection = 1
local lastStrafeSwitch = 0

local function moveAgainstTarget(targetPart, distance)
    local _, humanoid, root = getCharacter()

    if not humanoid or not root or not targetPart then
        return
    end

    local offset =
        targetPart.Position - root.Position

    if offset.Magnitude <= 0 then
        return
    end

    local direction = offset.Unit

    if distance > Bot.StopDistance then

        local destination =
            targetPart.Position
            - direction * Bot.StopDistance

        if Bot.Strafe then

            if os.clock() - lastStrafeSwitch > 0.8 then
                strafeDirection *= -1
                lastStrafeSwitch = os.clock()
            end

            local side = Vector3.new(
                -direction.Z,
                0,
                direction.X
            )

            destination +=
                side
                * Bot.StrafeDistance
                * strafeDirection
        end

        humanoid:MoveTo(destination)

    elseif Bot.Strafe then

        local side = Vector3.new(
            -direction.Z,
            0,
            direction.X
        )

        humanoid:MoveTo(
            root.Position
            + side
            * Bot.StrafeDistance
            * strafeDirection
        )
    end
end

--------------------------------------------------
-- PROMPT HELPERS
--------------------------------------------------

local function getPromptText(prompt)
    local parentName = ""

    if prompt.Parent then
        parentName = prompt.Parent.Name
    end

    return string.lower(
        prompt.Name
        .. " "
        .. parentName
        .. " "
        .. tostring(prompt.ActionText)
        .. " "
        .. tostring(prompt.ObjectText)
    )
end

local function getObjectPosition(object)
    if not object then
        return nil
    end

    if object:IsA("BasePart") then
        return object.Position
    end

    if object:IsA("Model") then
        return object:GetPivot().Position
    end

    if object.Parent then
        return getObjectPosition(object.Parent)
    end

    return nil
end

local function findPrompt(words)
    local _, _, root = getCharacter()

    if not root then
        return nil
    end

    local closestPrompt = nil
    local closestDistance = math.huge

    for _, object in ipairs(Workspace:GetDescendants()) do

        if object:IsA("ProximityPrompt")
            and object.Enabled
        then

            local text = getPr


omptText(object)

            local matches = false

            for _, word in ipairs(words) do
                if string.find(
                    text,
                    string.lower(word),
                    1,
                    true
                ) then
                    matches = true
                    break
                end
            end

            if matches then

                local position =
                    getObjectPosition(object.Parent)

                if position then

                    local distance =
                        (root.Position - position).Magnitude

                    if distance < closestDistance then
                        closestDistance = distance
                        closestPrompt = object
                    end
                end
            end
        end
    end

    return closestPrompt, closestDistance
end

--------------------------------------------------
-- MOVE TO PROMPT
--------------------------------------------------

local function moveToPrompt(prompt)
    local _, humanoid, root = getCharacter()

    if not humanoid or not root then
        return false
    end

    local position =
        getObjectPosition(prompt.Parent)

    if not position then
        return false
    end

    local distance =
        (root.Position - position).Magnitude

    if distance > Bot.InteractionDistance then
        humanoid:MoveTo(position)
        return false
    end

    return true
end

--------------------------------------------------
-- INTERACT
--------------------------------------------------

local function activatePrompt(prompt)
    if not prompt then
        return false
    end

    if fireproximityprompt then
        local ok = pcall(function()
            fireproximityprompt(prompt)
        end)

        return ok
    end

    return false
end

--------------------------------------------------
-- PLANT
--------------------------------------------------

local PlantWords = {
    "plant",
    "bomb",
    "site",
    "plant bomb",
    "установ",
    "бомб",
}

local function handlePlant()
    if not Bot.AutoPlant then
        return false
    end

    local prompt, distance =
        findPrompt(PlantWords)

    if not prompt then
        return false
    end

    log(
        "Plant:",
        prompt:GetFullName(),
        math.floor(distance)
    )

    if moveToPrompt(prompt) then

        activatePrompt(prompt)

        task.wait(
            math.max(
                tonumber(prompt.HoldDuration) or 0,
                0.25
            ) + 0.1
        )
    end

    return true
end

--------------------------------------------------
-- REWARD
--------------------------------------------------

local RewardWords = {
    "reward",
    "claim",
    "collect",
    "pickup",
    "loot",
    "drop",
    "награ",
    "забрать",
    "получ",
}

local function handleReward()
    if not Bot.AutoReward then
        return false
    end

    local prompt, distance =
        findPrompt(RewardWords)

    if not prompt then
        return false
    end

    log(
        "Reward:",
        prompt:GetFullName(),
        math.floor(distance)
    )

    if moveToPrompt(prompt) then
        activatePrompt(prompt)
        task.wait(0.15)
    end

    return true
end

--------------------------------------------------
-- RESPAWN
--------------------------------------------------

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(2)

    Camera = Workspace.CurrentCamera

    log("Respawned")
end)

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

log("Bot loaded")

task.spawn(function()

    local lastShot = 0

    while Bot.Enabled do

        local char, humanoid, root =
            getCharacter()

        if not char
            or not humanoid
            or not root
            or humanoid.Health <= 0
        then
            task.wait(0.5)
            continue
        end

        ------------------------------------------
        -- COMBAT
        --------------------------------
Buy humanoid.health | Spaceship
Buy humanoid.health | Spaceship
humanoid.Health


----------

        local targetPlayer,
            targetHead,
            distance =
            findTarget()

        if targetPlayer
            and targetHead
            and isAlive(targetPlayer)
        then

            moveAgainstTarget(
                targetHead,
                distance
            )

            -- continuously lock camera to head
            aimAt(targetHead)

            if distance <= Bot.ShootDistance then

                if os.clock() - lastShot
                    >= Bot.FireInterval
                then

                    -- re-aim immediately before firing
                    aimAt(targetHead)

                    shoot()

                    lastShot = os.clock()
                end
            end

        else

            --------------------------------------
            -- NO ENEMIES -> OBJECTIVES
            --------------------------------------

            local busy = false

            if Bot.AutoPlant then
                busy = handlePlant()
            end

            if not busy
                and Bot.AutoReward
            then
                busy = handleReward()
            end

            if not busy then
                humanoid:MoveTo(root.Position)
            end
        end

        task.wait(Bot.MoveUpdate)
    end

    log("Bot stopped")
end)

--------------------------------------------------
-- CONTROLS
--------------------------------------------------

getgenv().StopTestAutoBot = function()
    Bot.Enabled = false
end

getgenv().StartTestAutoBot = function()
    Bot.Enabled = true
end

print([[
====================================
 TEST AUTOBOT LOADED
====================================

Stop:
getgenv().StopTestAutoBot()

Settings:

getgenv().TestAutoBot.AutoPlant = true
getgenv().TestAutoBot.AutoReward = true
getgenv().TestAutoBot.TeamCheck = true

====================================
]])