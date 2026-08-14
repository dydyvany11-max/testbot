local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local Player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Bot = {
    Enabled = true,

    -- поиск противников
    MaxTargetDistance = 300,

    -- на каком расстоянии останавливаемся
    StopDistance = 25,

    -- дальше этого расстояния не стреляем
    ShootDistance = 140,

    -- задержка между выстрелами
    FireDelay = 0.12,

    -- как часто ищем новую цель
    TargetUpdate = 0.15,

    -- если противников нет, бот будет ходить вокруг
    Wander = true,

    -- насколько далеко выбираем случайную точку
    WanderRadius = 60,

    -- проверяем стены
    VisibilityCheck = true,
}

--------------------------------------------------
-- STATE
--------------------------------------------------

local currentTarget = nil
local lastShot = 0
local lastWander = 0
local wanderPoint = nil

--------------------------------------------------
-- CHARACTER
--------------------------------------------------

local function getCharacter()
    local character = Player.Character

    if not character then
        return nil
    end

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")

    local root =
        character:FindFirstChild("HumanoidRootPart")

    if not humanoid
        or not root
        or humanoid.Health <= 0
    then
        return nil
    end

    return character, humanoid, root
end

--------------------------------------------------
-- IS ALIVE
--------------------------------------------------

local function isAlive(other)
    if not other.Character then
        return false
    end

    local humanoid =
        other.Character:FindFirstChildOfClass("Humanoid")

    if not humanoid then
        return false
    end

    if humanoid.Health <= 0 then
        return false
    end

    if other.Character:GetAttribute("Dead") == true then
        return false
    end

    return true
end

--------------------------------------------------
-- TEAM
--------------------------------------------------

local function isEnemy(other)
    if other == Player then
        return false
    end

    if not isAlive(other) then
        return false
    end

    -- BloxStrike Deathmatch
    if Workspace:GetAttribute("Gamemode") == "Deathmatch" then
        return true
    end

    local myTeam = Player:GetAttribute("Team")
    local theirTeam = other:GetAttribute("Team")

    -- если команды неизвестны
    if myTeam == nil or theirTeam == nil then
        return true
    end

    return myTeam ~= theirTeam
end

--------------------------------------------------
-- TARGET PART
--------------------------------------------------

local function getTargetPart(other)
    local character = other.Character

    if not character then
        return nil
    end

    -- Не обязательно Head.
    -- Ведём прицел примерно в центр тела.
    return character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Head")
end

--------------------------------------------------
-- LINE OF SIGHT
--------------------------------------------------

local function canSee(other, part)
    if not Bot.VisibilityCheck then
        return true
    end

    local character = Player.Character

    if not character then
        return false
    end

    Camera = Workspace.CurrentCamera

    local origin = Camera.CFrame.Position
    local direction = part.Position - origin

    local params = RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {
        character,
        Camera
    }

    params.IgnoreWater = true

    local result =
        Workspace:Raycast(
            origin,
            direction,
            params
        )

    if not result then
        return true
    end

    return result.Instance:IsDescendantOf(
        other.Character
    )
end

--
Buy humanoid.health | Spaceship
Buy humanoid.health | Spaceship
humanoid.Health


-----------------------------------------------
-- FIND NEAREST VISIBLE ENEMY
--------------------------------------------------

local function findTarget()
    local _, _, root = getCharacter()

    if not root then
        return nil
    end

    local best = nil
    local bestPart = nil
    local bestDistance = Bot.MaxTargetDistance

    for _, other in ipairs(Players:GetPlayers()) do

        if isEnemy(other) then

            local part = getTargetPart(other)

            if part then

                local distance =
                    (
                        root.Position
                        - part.Position
                    ).Magnitude

                if distance < bestDistance then

                    if canSee(other, part) then

                        best = other
                        bestPart = part
                        bestDistance = distance
                    end
                end
            end
        end
    end

    return best, bestPart, bestDistance
end

--------------------------------------------------
-- AIM
--------------------------------------------------

local function lookAt(part)
    if not part then
        return
    end

    Camera = Workspace.CurrentCamera

    -- Просто смотрим в сторону противника.
    -- Никакого silent aim / raycast hook.
    Camera.CFrame =
        CFrame.lookAt(
            Camera.CFrame.Position,
            part.Position
        )
end

--------------------------------------------------
-- SHOOT
--------------------------------------------------

local function shoot()
    if os.clock() - lastShot < Bot.FireDelay then
        return
    end

    lastShot = os.clock()

    Camera = Workspace.CurrentCamera

    local x =
        Camera.ViewportSize.X / 2

    local y =
        Camera.ViewportSize.Y / 2

    --------------------------------------------------
    -- Executor mouse functions
    --------------------------------------------------

    if mouse1click then
        mouse1click()
        return
    end

    if mouse1press and mouse1release then

        mouse1press()

        task.wait(0.03)

        mouse1release()

        return
    end

    --------------------------------------------------
    -- fallback
    --------------------------------------------------

    pcall(function()

        VirtualInputManager:SendMouseButtonEvent(
            x,
            y,
            0,
            true,
            game,
            0
        )

        task.wait(0.03)

        VirtualInputManager:SendMouseButtonEvent(
            x,
            y,
            0,
            false,
            game,
            0
        )
    end)
end

--------------------------------------------------
-- MOVE TO ENEMY
--------------------------------------------------

local function moveToEnemy(part, distance)
    local _, humanoid, root = getCharacter()

    if not humanoid
        or not root
        or not part
    then
        return
    end

    --------------------------------------------------
    -- already close
    --------------------------------------------------

    if distance <= Bot.StopDistance then

        -- небольшое движение в сторону,
        -- чтобы бот не стоял как столб

        local delta =
            part.Position - root.Position

        if delta.Magnitude > 0.1 then

            local dir = delta.Unit

            local side =
                Vector3.new(
                    -dir.Z,
                    0,
                    dir.X
                )

            humanoid:MoveTo(
                root.Position
                + side * 6
            )
        end

        return
    end

    --------------------------------------------------
    -- normal movement
    --------------------------------------------------

    local delta =
        part.Position - root.Position

    if delta.Magnitude <= 0.1 then
        return
    end

    local direction = delta.Unit

    local destination =
        part.Position
        - direction
        * Bot.StopDistance

    humanoid:MoveTo(destination)
end

-----------------------------


---------------------
-- WANDER
--------------------------------------------------

local function chooseWanderPoint()
    local _, _, root = getCharacter()

    if not root then
        return
    end

    local angle =
        math.random() * math.pi * 2

    local distance =
        math.random(
            math.floor(Bot.WanderRadius * 0.4),
            Bot.WanderRadius
        )

    local offset =
        Vector3.new(
            math.cos(angle) * distance,
            0,
            math.sin(angle) * distance
        )

    wanderPoint =
        root.Position + offset
end

local function wander()
    if not Bot.Wander then
        return
    end

    local _, humanoid, root =
        getCharacter()

    if not humanoid or not root then
        return
    end

    if not wanderPoint
        or (root.Position - wanderPoint).Magnitude < 8
        or os.clock() - lastWander > 7
    then

        chooseWanderPoint()

        lastWander =
            os.clock()
    end

    if wanderPoint then
        humanoid:MoveTo(wanderPoint)
    end
end

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

task.spawn(function()

    print("[AutoBot] started")

    while Bot.Enabled do

        local character,
            humanoid,
            root =
            getCharacter()

        if not character
            or not humanoid
            or not root
        then

            task.wait(1)
            continue
        end

        ------------------------------------------------
        -- LOOK FOR ENEMY
        ------------------------------------------------

        local target,
            part,
            distance =
            findTarget()

        currentTarget = target

        ------------------------------------------------
        -- COMBAT
        ------------------------------------------------

        if target and part then

            moveToEnemy(
                part,
                distance
            )

            -- смотрим на противника
            lookAt(part)

            -- стреляем только если реально видим его
            if distance <= Bot.ShootDistance
                and canSee(target, part)
            then

                shoot()
            end

        ------------------------------------------------
        -- NO ENEMIES
        ------------------------------------------------

        else

            currentTarget = nil

            wander()
        end

        task.wait(
            Bot.TargetUpdate
        )
    end

    print("[AutoBot] stopped")
end)

--------------------------------------------------
-- RESPAWN
--------------------------------------------------

Player.CharacterAdded:Connect(function()

    currentTarget = nil
    wanderPoint = nil

    task.wait(2)

    Camera =
        Workspace.CurrentCamera

    print("[AutoBot] respawned")
end)

--------------------------------------------------
-- CONTROLS
--------------------------------------------------

_G.AutoBot = Bot

_G.StopAutoBot = function()
    Bot.Enabled = false
end

print([[
===============================
 AUTOBOT LOADED

 He will:
 - wander around
 - find visible enemies
 - run toward enemies
 - aim normally
 - shoot automatically
 - ignore enemies behind walls

 Stop:
 _G.StopAutoBot()
===============================
]])-




