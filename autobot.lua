--!strict

--[[
    Bot.server.lua

    ПОЛНЫЙ СЕРВЕРНЫЙ NPC BOT

    Возможности:

    - сам бегает по карте
    - случайный patrol
    - PathfindingService
    - поиск игроков на 360°
    - игнорирует свою команду
    - Line Of Sight через Raycast
    - преследует противника
    - идёт к последней известной позиции
    - плавно разворачивается через AlignOrientation
    - НЕ меняет HumanoidRootPart.CFrame
    - физически летящие визуальные пули
    - swept Raycast между кадрами
    - стены блокируют пулю
    - Body Damage
    - Headshot Damage
    - Fire Rate
    - Spread
    - Projectile Speed
    - Magazine
    - Reload

    Модель:

    EnemyBot
    ├── Humanoid
    ├── HumanoidRootPart
    ├── Head
    └── Bot.server.lua

    Опционально можно добавить:

    EnemyBot
    └── Gun
        └── Muzzle (Attachment)

    Тогда пуля будет появляться из Muzzle.

    Для команды NPC:

    NPC:SetAttribute("BotTeam", "T")

    или

    NPC:SetAttribute("BotTeam", "CT")

    Если BotTeam не задан — бот атакует всех игроков.
]]

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")

local PathfindingService =
    game:GetService("PathfindingService")

local RunService =
    game:GetService("RunService")

local Workspace =
    game:GetService("Workspace")

---------------------------------------------------------------------
-- NPC
---------------------------------------------------------------------

local NPC = script.Parent

assert(
    NPC:IsA("Model"),
    "Script должен находиться внутри NPC Model"
)

local Humanoid =
    NPC:FindFirstChildOfClass("Humanoid")

assert(
    Humanoid,
    "NPC должен содержать Humanoid"
)

local Root =
    NPC:FindFirstChild("HumanoidRootPart")

assert(
    Root and Root:IsA("BasePart"),
    "NPC должен содержать HumanoidRootPart"
)

local Head =
    NPC:FindFirstChild("Head")

assert(
    Head and Head:IsA("BasePart"),
    "NPC должен содержать Head"
)

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local CONFIG = {

    -----------------------------------------------------------------
    -- MOVEMENT
    -----------------------------------------------------------------

    WalkSpeed = 20,

    ThinkInterval = 0.05,

    -----------------------------------------------------------------
    -- DETECTION
    -----------------------------------------------------------------

    -- Поиск идёт на все 360 градусов.
    DetectionRadius = 350,

    DetectionInterval = 0.12,

    LostTargetTime = 4,

    -----------------------------------------------------------------
    -- COMBAT
    -----------------------------------------------------------------

    ShootingRange = 180,

    -- Ближе этого расстояния NPC
    -- перестаёт идти прямо в игрока.
    StopDistance = 35,

    FireDelay = 0.11,

    -----------------------------------------------------------------
    -- DAMAGE
    -----------------------------------------------------------------

    BodyDamage = 24,

    HeadDamage = 95,

    -----------------------------------------------------------------
    -- BULLET
    -----------------------------------------------------------------

    BulletSpeed = 850,

    BulletMaxDistance = 220,

    BulletSize =
        Vector3.new(
            0.12,
            0.12,
            1.2
        ),

    BulletLifetime = 2,

    -----------------------------------------------------------------
    -- AIM
    -----------------------------------------------------------------

    PreferHead = true,

    HeadAimChance = 0.85,

    -- Разброс в градусах.
    SpreadDegrees = 1.2,

    -- Плавность физического разворота NPC.
    AimResponsiveness = 25,

    -----------------------------------------------------------------
    -- AMMO
    -----------------------------------------------------------------

    MagazineSize = 30,

    ReserveAmmo = 120,

    ReloadTime = 2.3,

    -----------------------------------------------------------------
    -- PATHFINDING
    -----------------------------------------------------------------

    AgentRadius = 2,

    AgentHeight = 5,

    AgentCanJump = true,

    AgentCanClimb = false,

    RepathInterval = 0.5,

    TargetRepathDistance = 6,

    WaypointReachDistance = 4,

    -----------------------------------------------------------------
    -- PATROL
    -----------------------------------------------------------------

    PatrolMinDistance = 40,

    PatrolMaxDistance = 100,

    PatrolDestinationTimeout = 8,

    PatrolPause = 0.3,
}

---------------------------------------------------------------------
-- NETWORK OWNERSHIP
---------------------------------------------------------------------
--
-- NPC рассчитывается сервером.
---------------------------------------------------------------------

pcall(function()

    Root:SetNetworkOwner(nil)

end)

---------------------------------------------------------------------
-- SPEED
---------------------------------------------------------------------

Humanoid.WalkSpeed =
    CONFIG.WalkSpeed

---------------------------------------------------------------------
-- TEAM
---------------------------------------------------------------------

local BOT_TEAM =
    NPC:GetAttribute("BotTeam")

---------------------------------------------------------------------
-- PROJECTILE FOLDER
---------------------------------------------------------------------

local ProjectileFolder =
    Workspace:FindFirstChild(
        "BotProjectiles"
    )

if not ProjectileFolder then

    ProjectileFolder =
        Instance.new("Folder")

    ProjectileFolder.Name =
        "BotProjectiles"

    ProjectileFolder.Parent =
        Workspace
end

---------------------------------------------------------------------
-- AIM ORIENTATION
---------------------------------------------------------------------
--
-- Никакого:
--
-- Root.CFrame = ...
--
-- Используем AlignOrientation.
---------------------------------------------------------------------

local AimAttachment =
    Root:FindFirstChild(
        "BotAimAttachment"
    )

if not AimAttachment then

    AimAttachment =
        Instance.new("Attachment")

    AimAttachment.Name =
        "BotAimAttachment"

    AimAttachment.Parent =
        Root
end

local AimOrientation =
    Root:FindFirstChild(
        "BotAimOrientation"
    )

if not AimOrientation then

    AimOrientation =
        Instance.new(
            "AlignOrientation"
        )

    AimOrientation.Name =
        "BotAimOrientation"

    AimOrientation.Mode =
        Enum.OrientationAlignmentMode.OneAttachment

    AimOrientation.Attachment0 =
        AimAttachment

    AimOrientation.RigidityEnabled =
        false

    AimOrientation.Responsiveness =
        CONFIG.AimResponsiveness

    AimOrientation.MaxTorque =
        math.huge

    AimOrientation.Enabled =
        false

    AimOrientation.Parent =
        Root
end

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local TargetPlayer: Player? =
    nil

local LastSeenPosition: Vector3? =
    nil

local LastSeenTime =
    0

local LastDetectionTime =
    0

---------------------------------------------------------------------
-- PATH STATE
---------------------------------------------------------------------

local Waypoints = {}

local WaypointIndex =
    1

local LastPathDestination: Vector3? =
    nil

local LastPathTime =
    0

---------------------------------------------------------------------
-- PATROL STATE
---------------------------------------------------------------------

local PatrolDestination: Vector3? =
    nil

local PatrolCreatedAt =
    0

local NextPatrolTime =
    0

---------------------------------------------------------------------
-- WEAPON STATE
---------------------------------------------------------------------

local Magazine =
    CONFIG.MagazineSize

local ReserveAmmo =
    CONFIG.ReserveAmmo

local LastShotTime =
    0

local Reloading =
    false

local ReloadFinishTime =
    0

---------------------------------------------------------------------
-- RANDOM
---------------------------------------------------------------------

local RNG =
    Random.new()

---------------------------------------------------------------------
-- ACTIVE BULLETS
---------------------------------------------------------------------

local ActiveBullets = {}

---------------------------------------------------------------------
-- PLAYER DATA
---------------------------------------------------------------------

local function getPlayerData(
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
-- IS ENEMY
---------------------------------------------------------------------

local function isEnemy(
    player: Player
): boolean

    ---------------------------------------------------------------
    -- Если команда NPC не задана,
    -- считаем всех игроков врагами.
    ---------------------------------------------------------------

    if not BOT_TEAM
        or BOT_TEAM == "" then

        return true
    end

    ---------------------------------------------------------------
    -- Roblox Team.
    ---------------------------------------------------------------

    if player.Team then

        if player.Team.Name
            == BOT_TEAM then

            return false
        end
    end

    ---------------------------------------------------------------
    -- Дополнительно поддерживаем
    -- Character Attribute Team.
    ---------------------------------------------------------------

    local character =
        player.Character

    if character then

        local characterTeam =
            character:GetAttribute(
                "Team"
            )

        if characterTeam
            == BOT_TEAM then

            return false
        end
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

    params.FilterDescendantsInstances = {
        NPC,
        ProjectileFolder,
    }

    params.IgnoreWater =
        true

    return params
end

---------------------------------------------------------------------
-- LINE OF SIGHT
---------------------------------------------------------------------

local function canSeeCharacter(
    character: Model
): boolean

    ---------------------------------------------------------------
    -- Пробуем Head.
    ---------------------------------------------------------------

    local targetParts = {
        character:
            FindFirstChild("Head"),

        character:
            FindFirstChild(
                "HumanoidRootPart"
            ),
    }

    for _, targetPart
        in ipairs(targetParts) do

        if not targetPart
            or not targetPart:IsA(
                "BasePart"
            ) then

            continue
        end

        local origin =
            Head.Position

        local direction =
            targetPart.Position
            - origin

        local result =
            Workspace:Raycast(

                origin,

                direction,

                createRaycastParams()
            )

        if result
            and result.Instance:
                IsDescendantOf(
                    character
                ) then

            return true
        end
    end

    return false
end

---------------------------------------------------------------------
-- FIND NEAREST ENEMY
---------------------------------------------------------------------
--
-- Никакого FOV ограничения.
--
-- Проверяется всё вокруг NPC на 360 градусов.
---------------------------------------------------------------------

local function findTarget(): Player?

    local bestPlayer: Player? =
        nil

    local bestDistance =
        math.huge

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

        -----------------------------------------------------------
        -- Стена.
        -----------------------------------------------------------

        if not canSeeCharacter(
            character
        ) then

            continue
        end

        bestDistance =
            distance

        bestPlayer =
            player
    end

    return bestPlayer
end

---------------------------------------------------------------------
-- AIM NPC
---------------------------------------------------------------------

local function aimAt(
    position: Vector3
)

    ---------------------------------------------------------------
    -- Не наклоняем тело вверх/вниз.
    ---------------------------------------------------------------

    local direction =
        Vector3.new(
            position.X - Root.Position.X,
            0,
            position.Z - Root.Position.Z
        )

    if direction.Magnitude
        <= 0.01 then

        return
    end

    Humanoid.AutoRotate =
        false

    AimOrientation.Enabled =
        true

    AimOrientation.CFrame =
        CFrame.lookAt(
            Vector3.zero,
            direction.Unit
        )
end

---------------------------------------------------------------------
-- RELEASE AIM
---------------------------------------------------------------------

local function releaseAim()

    AimOrientation.Enabled =
        false

    Humanoid.AutoRotate =
        true
end

---------------------------------------------------------------------
-- COMPUTE PATH
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
-- SHOULD REPATH
---------------------------------------------------------------------

local function needsRepath(
    destination: Vector3,
    movingTarget: boolean
): boolean

    if #Waypoints == 0 then
        return true
    end

    if movingTarget
        and os.clock()
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
            >= CONFIG.TargetRepathDistance then

            return true
        end
    end

    return false
end

---------------------------------------------------------------------
-- FOLLOW PATH
---------------------------------------------------------------------

local function followPath(): boolean

    local waypoint =
        Waypoints[
            WaypointIndex
        ]

    if not waypoint then
        return false
    end

    ---------------------------------------------------------------
    -- Waypoint reached.
    ---------------------------------------------------------------

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

    ---------------------------------------------------------------
    -- Jump.
    ---------------------------------------------------------------

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

local function moveTo(
    destination: Vector3,
    movingTarget: boolean
)

    if needsRepath(
        destination,
        movingTarget
    ) then

        if not computePath(
            destination
        ) then

            ---------------------------------------------------------
            -- Fallback.
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
-- STOP
---------------------------------------------------------------------

local function stopMovement()

    Humanoid:MoveTo(
        Root.Position
    )
end

---------------------------------------------------------------------
-- CREATE PATROL POINT
---------------------------------------------------------------------

local function createPatrolDestination(): Vector3?

    ---------------------------------------------------------------
    -- Выбираем новую точку относительно ТЕКУЩЕЙ позиции.
    --
    -- Поэтому NPC постепенно гуляет по всей карте,
    -- а не кружит только около spawn.
    ---------------------------------------------------------------

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

        -----------------------------------------------------------
        -- Ищем поверхность.
        -----------------------------------------------------------

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

                createRaycastParams()
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

        -----------------------------------------------------------
        -- Проверяем, можно ли туда реально пройти.
        -----------------------------------------------------------

        if computePath(
            destination
        ) then

            return destination
        end
    end

    return nil
end

---------------------------------------------------------------------
-- PATROL
---------------------------------------------------------------------

local function patrol()

    releaseAim()

    if os.clock()
        < NextPatrolTime then

        return
    end

    local newDestination =
        PatrolDestination == nil

    ---------------------------------------------------------------
    -- Уже дошли.
    ---------------------------------------------------------------

    if PatrolDestination
        and (
            Root.Position
            - PatrolDestination
        ).Magnitude <= 6 then

        newDestination =
            true
    end

    ---------------------------------------------------------------
    -- Возможно застряли.
    ---------------------------------------------------------------

    if PatrolDestination
        and os.clock()
            - PatrolCreatedAt
            >= CONFIG.PatrolDestinationTimeout then

        newDestination =
            true
    end

    if newDestination then

        PatrolDestination =
            createPatrolDestination()

        PatrolCreatedAt =
            os.clock()

        if not PatrolDestination then

            NextPatrolTime =
                os.clock() + 1

            return
        end
    end

    moveTo(
        PatrolDestination,
        false
    )

    NextPatrolTime =
        os.clock()
        + CONFIG.PatrolPause
end

---------------------------------------------------------------------
-- MUZZLE
---------------------------------------------------------------------

local function getMuzzlePosition(): Vector3

    ---------------------------------------------------------------
    -- Attachment Muzzle где угодно внутри NPC.
    ---------------------------------------------------------------

    local muzzle =
        NPC:FindFirstChild(
            "Muzzle",
            true
        )

    if muzzle
        and muzzle:IsA(
            "Attachment"
        ) then

        return muzzle.WorldPosition
    end

    ---------------------------------------------------------------
    -- Fallback от головы.
    ---------------------------------------------------------------

    return Head.Position
        + Head.CFrame.LookVector
            * 1.5
end

---------------------------------------------------------------------
-- AIM TARGET POINT
---------------------------------------------------------------------

local function getAimPosition(
    character: Model,
    targetRoot: BasePart
): Vector3

    local targetPart: BasePart =
        targetRoot

    local head =
        character:
            FindFirstChild(
                "Head"
            )

    if CONFIG.PreferHead
        and head
        and head:IsA("BasePart")
        and RNG:NextNumber()
            <= CONFIG.HeadAimChance then

        targetPart =
            head
    end

    return targetPart.Position
end

---------------------------------------------------------------------
-- SPREAD
---------------------------------------------------------------------

local function applySpread(
    direction: Vector3
): Vector3

    if CONFIG.SpreadDegrees <= 0 then

        return direction.Unit
    end

    local spread =
        math.rad(
            CONFIG.SpreadDegrees
        )

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
-- FIND HUMANOID FROM HIT
---------------------------------------------------------------------

local function findHumanoidFromPart(
    part: Instance
)

    local current: Instance? =
        part

    while current
        and current ~= Workspace do

        if current:IsA(
            "Model"
        ) then

            local humanoid =
                current:
                    FindFirstChildOfClass(
                        "Humanoid"
                    )

            if humanoid then

                return humanoid,
                    current
            end
        end

        current =
            current.Parent
    end

    return nil
end

---------------------------------------------------------------------
-- FRIENDLY HIT?
---------------------------------------------------------------------

local function isFriendlyCharacter(
    character: Model
): boolean

    local player =
        Players:
            GetPlayerFromCharacter(
                character
            )

    if not player then
        return false
    end

    return not isEnemy(
        player
    )
end

---------------------------------------------------------------------
-- BULLET HIT
---------------------------------------------------------------------

local function processBulletHit(
    bullet,
    result: RaycastResult
)

    local humanoid,
        character =
        findHumanoidFromPart(
            result.Instance
        )

    ---------------------------------------------------------------
    -- Попали просто в стену/пол.
    ---------------------------------------------------------------

    if not humanoid
        or not character then

        return
    end

    ---------------------------------------------------------------
    -- Себя не дамажим.
    ---------------------------------------------------------------

    if character == NPC then
        return
    end

    ---------------------------------------------------------------
    -- Тиммейта не дамажим.
    --
    -- Но пуля всё равно остановится на нём.
    ---------------------------------------------------------------

    if isFriendlyCharacter(
        character
    ) then

        return
    end

    if humanoid.Health <= 0 then
        return
    end

    ---------------------------------------------------------------
    -- DAMAGE
    ---------------------------------------------------------------

    local damage =
        CONFIG.BodyDamage

    ---------------------------------------------------------------
    -- HEADSHOT
    ---------------------------------------------------------------

    if result.Instance.Name
        == "Head" then

        damage =
            CONFIG.HeadDamage
    end

    ---------------------------------------------------------------
    -- ВАЖНО:
    --
    -- TakeDamage происходит ТОЛЬКО ЗДЕСЬ,
    -- после реального столкновения пули.
    ---------------------------------------------------------------

    humanoid:TakeDamage(
        damage
    )

    print(
        "[BOT HIT]",
        character.Name,
        result.Instance.Name,
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

    local bulletPart =
        Instance.new("Part")

    bulletPart.Name =
        "BotBullet"

    bulletPart.Size =
        CONFIG.BulletSize

    bulletPart.Anchored =
        true

    bulletPart.CanCollide =
        false

    bulletPart.CanTouch =
        false

    bulletPart.CanQuery =
        false

    bulletPart.CastShadow =
        false

    bulletPart.Material =
        Enum.Material.Neon

    bulletPart.CFrame =
        CFrame.lookAt(
            origin,
            origin + direction
        )

    bulletPart.Parent =
        ProjectileFolder

    local params =
        createRaycastParams()

    table.insert(
        ActiveBullets,
        {
            Part =
                bulletPart,

            Position =
                origin,

            Velocity =
                direction.Unit
                * CONFIG.BulletSpeed,

            Distance =
                0,

            Lifetime =
                CONFIG.BulletLifetime,

            RaycastParams =
                params,
        }
    )
end

---------------------------------------------------------------------
-- BULLET SIMULATION
---------------------------------------------------------------------
--
-- Swept raycast:
--
-- старая позиция
--      ↓
-- новая позиция
--
-- между ними каждый Heartbeat выполняется Raycast.
--
-- Поэтому быстрая пуля не должна "пролетать"
-- сквозь персонажа между кадрами.
---------------------------------------------------------------------

RunService.Heartbeat:
    Connect(function(dt)

        for i =
            #ActiveBullets,
            1,
            -1 do

            local bullet =
                ActiveBullets[i]

            local part =
                bullet.Part

            if not part
                or not part.Parent then

                table.remove(
                    ActiveBullets,
                    i
                )

                continue
            end

            bullet.Lifetime -=
                dt

            if bullet.Lifetime <= 0 then

                part:Destroy()

                table.remove(
                    ActiveBullets,
                    i
                )

                continue
            end

            local oldPosition =
                bullet.Position

            local movement =
                bullet.Velocity * dt

            local result =
                Workspace:Raycast(

                    oldPosition,

                    movement,

                    bullet.RaycastParams
                )

            -------------------------------------------------------
            -- HIT
            -------------------------------------------------------

            if result then

                bullet.Position =
                    result.Position

                part.Position =
                    result.Position

                processBulletHit(
                    bullet,
                    result
                )

                part:Destroy()

                table.remove(
                    ActiveBullets,
                    i
                )

                continue
            end

            -------------------------------------------------------
            -- MOVE BULLET
            -------------------------------------------------------

            local newPosition =
                oldPosition
                + movement

            bullet.Distance +=
                movement.Magnitude

            if bullet.Distance
                >= CONFIG.BulletMaxDistance then

                part:Destroy()

                table.remove(
                    ActiveBullets,
                    i
                )

                continue
            end

            bullet.Position =
                newPosition

            part.CFrame =
                CFrame.lookAt(
                    newPosition,
                    newPosition
                        + bullet.Velocity.Unit
                )
        end
    end)

---------------------------------------------------------------------
-- RELOAD
---------------------------------------------------------------------

local function startReload()

    if Reloading then
        return
    end

    if ReserveAmmo <= 0 then
        return
    end

    Reloading =
        true

    ReloadFinishTime =
        os.clock()
        + CONFIG.ReloadTime

    print("[BOT] Reloading...")
end

---------------------------------------------------------------------
-- UPDATE RELOAD
---------------------------------------------------------------------

local function updateReload()

    if not Reloading then
        return
    end

    if os.clock()
        < ReloadFinishTime then

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

    Magazine +=
        amount

    ReserveAmmo -=
        amount

    Reloading =
        false

    print(
        "[BOT] Reload completed",
        Magazine,
        ReserveAmmo
    )
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

    if os.clock()
        - LastShotTime
        < CONFIG.FireDelay then

        return
    end

    local origin =
        getMuzzlePosition()

    local rawDirection =
        targetPosition
        - origin

    if rawDirection.Magnitude
        <= 0.01 then

        return
    end

    ---------------------------------------------------------------
    -- Проверяем, что цель вообще в пределах
    -- максимальной дальности.
    ---------------------------------------------------------------

    if rawDirection.Magnitude
        > CONFIG.BulletMaxDistance then

        return
    end

    local direction =
        applySpread(
            rawDirection
        )

    Magazine -= 1

    LastShotTime =
        os.clock()

    spawnBullet(
        origin,
        direction
    )

    ---------------------------------------------------------------
    -- Magazine empty.
    ---------------------------------------------------------------

    if Magazine <= 0 then

        startReload()
    end
end

---------------------------------------------------------------------
-- CLEAR TARGET
---------------------------------------------------------------------

local function clearTarget()

    TargetPlayer =
        nil

    LastSeenPosition =
        nil

    Waypoints = {}

    releaseAim()
end

---------------------------------------------------------------------
-- PROCESS TARGET
---------------------------------------------------------------------

local function processTarget(
    player: Player
): boolean

    ---------------------------------------------------------------
    -- Игрок вдруг стал союзником.
    ---------------------------------------------------------------

    if not isEnemy(player) then

        clearTarget()

        return false
    end

    local character,
        humanoid,
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

    local visible =
        canSeeCharacter(
            character
        )

    ---------------------------------------------------------------
    -- VISIBLE
    ---------------------------------------------------------------

    if visible then

        LastSeenPosition =
            targetRoot.Position

        LastSeenTime =
            os.clock()

        local aimPosition =
            getAimPosition(
                character,
                targetRoot
            )

        -------------------------------------------------------------
        -- Разворачиваем корпус через AlignOrientation.
        -------------------------------------------------------------

        aimAt(
            aimPosition
        )

        -------------------------------------------------------------
        -- TOO FAR
        -------------------------------------------------------------

        if distance
            > CONFIG.ShootingRange then

            moveTo(
                targetRoot.Position,
                true
            )

            return true
        end

        -------------------------------------------------------------
        -- COMBAT MOVEMENT
        -------------------------------------------------------------

        if distance
            > CONFIG.StopDistance then

            ---------------------------------------------------------
            -- Идёт и одновременно стреляет.
            ---------------------------------------------------------

            moveTo(
                targetRoot.Position,
                true
            )

        else

            stopMovement()
        end

        -------------------------------------------------------------
        -- FIRE
        -------------------------------------------------------------

        shoot(
            aimPosition
        )

        return true
    end

    ---------------------------------------------------------------
    -- LOST BEHIND WALL
    ---------------------------------------------------------------

    releaseAim()

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

    clearTarget()

    return false
end

---------------------------------------------------------------------
-- DETECTION
---------------------------------------------------------------------

local function updateDetection()

    if os.clock()
        - LastDetectionTime
        < CONFIG.DetectionInterval then

        return
    end

    LastDetectionTime =
        os.clock()

    ---------------------------------------------------------------
    -- Проверяем текущую цель.
    ---------------------------------------------------------------

    if TargetPlayer
        and isEnemy(
            TargetPlayer
        ) then

        local character =
            TargetPlayer.Character

        if character then

            local humanoid =
                character:
                    FindFirstChildOfClass(
                        "Humanoid"
                    )

            if humanoid
                and humanoid.Health > 0 then

                return
            end
        end
    end

    ---------------------------------------------------------------
    -- Новая цель.
    ---------------------------------------------------------------

    TargetPlayer =
        findTarget()
end

---------------------------------------------------------------------
-- DIED
---------------------------------------------------------------------

Humanoid.Died:
    Connect(function()

        AimOrientation.Enabled =
            false

        Waypoints = {}

        print("[BOT] died")

    end)

---------------------------------------------------------------------
-- MAIN AI LOOP
---------------------------------------------------------------------

task.spawn(function()

    while NPC.Parent
        and Humanoid.Health > 0 do

        -------------------------------------------------------------
        -- Reload timer.
        -------------------------------------------------------------

        updateReload()

        -------------------------------------------------------------
        -- Detection.
        -------------------------------------------------------------

        updateDetection()

        -------------------------------------------------------------
        -- Combat.
        -------------------------------------------------------------

        if TargetPlayer then

            local success =
                processTarget(
                    TargetPlayer
                )

            if success then

                task.wait(
                    CONFIG.ThinkInterval
                )

                continue
            end
        end

        -------------------------------------------------------------
        -- No enemy -> run around map.
        -------------------------------------------------------------

        patrol()

        task.wait(
            CONFIG.ThinkInterval
        )
    end
end)

---------------------------------------------------------------------
-- READY
---------------------------------------------------------------------

print(
    "[BOT] started",
    NPC.Name,
    "Team:",
    BOT_TEAM or "ALL"
)
