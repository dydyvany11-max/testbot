--[[
    autobot.lua

    Запускать УЖЕ ПОСЛЕ того, как ты:
      1. Сам выбрал Unranked / Deathmatch / Casual
      2. Нажал Play
      3. Выбрал сторону
      4. Загрузился в матч

    После этого бот автоматически:

      - бегает по карте
      - Pathfinding
      - ищет противников
      - проверяет Line Of Sight
      - наводится
      - стреляет через текущий Tool
      - перезаряжается
      - закупается
      - открывает награды через N
      - открывает Home
      - забирает Hourly/Daily/Weekly/Monthly Claim
      - обнаруживает конец матча
      - жмёт Close
      - ждёт 60 секунд
      - жмёт Play
      - выбирает сторону
      - продолжает играть

    Остановить:
        getgenv().AutoBot:Stop()

    Запустить снова:
        getgenv().AutoBot:Start()

    Принудительно забрать награды:
        getgenv().AutoBot:ClaimRewards()
]]

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

---------------------------------------------------------------------
-- ENVIRONMENT
---------------------------------------------------------------------

local ENV = getgenv and getgenv() or _G

-- При повторном execute выключаем старую версию.
if ENV.AutoBot and ENV.AutoBot.Stop then
    pcall(function()
        ENV.AutoBot:Stop()
    end)
end

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local CONFIG = {

    -----------------------------------------------------------------
    -- СТОРОНА
    -----------------------------------------------------------------

    -- Используется уже ПОСЛЕ следующего Play.
    -- "T" или "CT"

    PreferredSide = "T",

    -----------------------------------------------------------------
    -- AI
    -----------------------------------------------------------------

    ThinkDelay = 0.05,

    DetectionInterval = 0.10,

    DetectionRadius = 300,

    LostTargetTime = 4,

    IgnoreSameTeam = true,

    -----------------------------------------------------------------
    -- COMBAT
    -----------------------------------------------------------------

    AttackRange = 150,

    MinimumCombatDistance = 25,

    FireDelay = 0.10,

    -----------------------------------------------------------------
    -- AIM
    -----------------------------------------------------------------

    PreferHead = true,

    HeadAimChance = 0.90,

    RotateCharacter = true,

    -- Если оружие стреляет туда,
    -- куда направлена камера:
    RotateCamera = true,

    Prediction = false,

    EstimatedBulletSpeed = 900,

    -----------------------------------------------------------------
    -- RELOAD
    -----------------------------------------------------------------

    ReloadEveryShots = 27,

    ReloadTime = 2.5,

    -----------------------------------------------------------------
    -- PATHFINDING
    -----------------------------------------------------------------

    RepathInterval = 0.45,

    RepathDistance = 6,

    WaypointReachDistance = 4,

    AgentRadius = 2,

    AgentHeight = 5,

    AgentCanJump = true,

    AgentCanClimb = false,

    -----------------------------------------------------------------
    -- PATROL
    -----------------------------------------------------------------

    PatrolFolder = "PatrolPoints",

    RandomPatrolRadius = 180,

    PatrolPause = 0.6,

    -----------------------------------------------------------------
    -- BUY
    -----------------------------------------------------------------

    AutoBuy = true,

    BuyKey = Enum.KeyCode.B,

    BuyDelayAfterSpawn = 1.3,

    BuyMenuDelay = 0.4,

    BuyClickDelay = 0.3,

    BuyPriority = {
        "AWP",
        "AK47",
        "AK-47",
        "M4A1",
        "M4A4",
        "Galil",
        "Famas",
        "MP5",
        "P90",
        "Deagle",
        "P250",
    },

    -----------------------------------------------------------------
    -- WEAPON PRIORITY
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

        "MP5",
        "P90",

        "Deagle",
        "Desert Eagle",

        "P250",

        "USP",
        "USP-S",

        "Glock",
    },

    -----------------------------------------------------------------
    -- REWARDS
    -----------------------------------------------------------------

    AutoClaimRewards = true,

    -- N открывает меню.
    RewardsKey = Enum.KeyCode.N,

    -- Через сколько секунд после execute
    -- впервые проверить награды.
    FirstRewardCheckDelay = 8,

    -- Проверять каждые 5 минут.
    RewardCheckInterval = 300,

    RewardMenuDelay = 0.6,

    -- После N пытаемся нажать домик/Home.
    ClickHomeBeforeClaim = true,

    HomeAliases = {
        "Home",
        "House",
        "Main",
    },

    ClaimAliases = {
        "Claim",
        "Collect",
        "Redeem",
    },

    RewardAliases = {
        "Hourly",
        "Daily",
        "Weekly",
        "Monthly",
    },

    -----------------------------------------------------------------
    -- MATCH END
    -----------------------------------------------------------------

    AutoReplay = true,

    -- После Close ждём минуту.
    MatchEndWait = 60,

    MatchEndCheckInterval = 0.5,

    CloseAliases = {
        "Close",
        "Continue",
    },

    -- Слова, которые помогают понять,
    -- что Close относится именно к концу матча.
    ResultAliases = {
        "Victory",
        "Defeat",
        "Winner",
        "Match",
        "Results",
        "Result",
        "Score",
        "Map",
        "MVP",
    },

    PlayAliases = {
        "Play",
    },

    TAliases = {
        "T",
        "Terrorist",
        "Terrorists",
    },

    CTAliases = {
        "CT",
        "Counter Terrorist",
        "Counter-Terrorist",
        "Counter Terrorists",
        "Counter-Terrorists",
    },

    MenuTimeout = 30,

    MenuClickDelay = 0.4,
}

---------------------------------------------------------------------
-- BOT
---------------------------------------------------------------------

local Bot = {}

Bot.Running = false

Bot.Character = nil
Bot.Humanoid = nil
Bot.Root = nil
Bot.Head = nil

Bot.Target = nil

Bot.LastSeenPosition = nil
Bot.LastSeenTime = 0
Bot.LastDetection = 0

Bot.LastShot = 0
Bot.ShotCounter = 0
Bot.Reloading = false

Bot.PathWaypoints = {}
Bot.PathIndex = 1

Bot.LastPathDestination = nil
Bot.LastPathTime = 0

Bot.SpawnPosition = nil

Bot.PatrolPoints = {}
Bot.PatrolIndex = 1

Bot.RandomPatrolDestination = nil
Bot.NextPatrol = 0

Bot.HandlingMatchEnd = false
Bot.ClaimingRewards = false

Bot.CharacterConnection = nil

---------------------------------------------------------------------
-- UTIL
---------------------------------------------------------------------

local function normalize(value)

    if value == nil then
        return ""
    end

    return string.lower(
        tostring(value)
    )
end

---------------------------------------------------------------------
-- GUI VISIBILITY
---------------------------------------------------------------------

local function isGuiVisible(object)

    local current = object

    while current do

        if current:IsA("GuiObject") then

            if current.Visible == false then
                return false
            end
        end

        current = current.Parent
    end

    return true
end

---------------------------------------------------------------------
-- CHARACTER DATA
---------------------------------------------------------------------

local function getPlayerCharacter(player)

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

    if not humanoid or not root then
        return nil
    end

    if humanoid.Health <= 0 then
        return nil
    end

    return character, humanoid, root
end

---------------------------------------------------------------------
-- LOCAL CHARACTER
---------------------------------------------------------------------

function Bot:GetCharacter()

    local character =
        LocalPlayer.Character

    if not character then
        return false
    end

    local humanoid =
        character:FindFirstChildOfClass(
            "Humanoid"
        )

    local root =
        character:FindFirstChild(
            "HumanoidRootPart"
        )

    if not humanoid or not root then
        return false
    end

    self.Character = character
    self.Humanoid = humanoid
    self.Root = root

    self.Head =
        character:FindFirstChild("Head")

    return true
end

---------------------------------------------------------------------
-- PRESS KEY
---------------------------------------------------------------------

function Bot:PressKey(key)

    pcall(function()

        VirtualInputManager:SendKeyEvent(
            true,
            key,
            false,
            game
        )

        task.wait(0.04)

        VirtualInputManager:SendKeyEvent(
            false,
            key,
            false,
            game
        )
    end)
end

---------------------------------------------------------------------
-- CLICK BUTTON
---------------------------------------------------------------------

function Bot:ClickButton(button)

    if not button then
        return false
    end

    -----------------------------------------------------------------
    -- firesignal
    -----------------------------------------------------------------

    if firesignal and button:IsA("GuiButton") then

        local success =
            pcall(function()

                firesignal(
                    button.Activated
                )
            end)

        if success then
            task.wait(0.05)
            return true
        end
    end

    -----------------------------------------------------------------
    -- Mouse fallback
    -----------------------------------------------------------------

    if not button:IsA("GuiObject") then
        return false
    end

    local pos =
        button.AbsolutePosition

    local size =
        button.AbsoluteSize

    local x =
        pos.X + size.X / 2

    local y =
        pos.Y + size.Y / 2

    return pcall(function()

        VirtualInputManager:SendMouseMoveEvent(
            x,
            y,
            game
        )

        task.wait(0.03)

        VirtualInputManager:SendMouseButtonEvent(
            x,
            y,
            0,
            true,
            game,
            0
        )

        task.wait(0.04)

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

---------------------------------------------------------------------
-- GUI TEXT
---------------------------------------------------------------------

function Bot:GetGuiText(object)

    if object:IsA("TextButton")
        or object:IsA("TextLabel") then

        return normalize(
            object.Text
        )
    end

    return ""
end

---------------------------------------------------------------------
-- GUI MATCH
---------------------------------------------------------------------

function Bot:GuiMatches(object, aliases)

    local objectName =
        normalize(object.Name)

    local text =
        self:GetGuiText(object)

    for _, alias in ipairs(aliases) do

        local wanted =
            normalize(alias)

        -------------------------------------------------------------
        -- Для T/CT не используем partial match,
        -- иначе "T" совпадёт вообще почти со всем.
        -------------------------------------------------------------

        if #wanted <= 2 then

            if objectName == wanted
                or text == wanted then

                return true
            end

            continue
        end

        if objectName == wanted
            or text == wanted
            or string.find(
                objectName,
                wanted,
                1,
                true
            )
            or string.find(
                text,
                wanted,
                1,
                true
            ) then

            return true
        end
    end

    return false
end

---------------------------------------------------------------------
-- FIND GUI BUTTON
---------------------------------------------------------------------

function Bot:FindGuiButton(aliases)

    local playerGui =
        LocalPlayer:FindFirstChildOfClass(
            "PlayerGui"
        )

    if not playerGui then
        return nil
    end

    for _, object
        in ipairs(
            playerGui:GetDescendants()
        ) do

        if not object:IsA("GuiButton") then
            continue
        end

        if not isGuiVisible(object) then
            continue
        end

        if self:GuiMatches(
            object,
            aliases
        ) then

            return object
        end
    end

    return nil
end

---------------------------------------------------------------------
-- WAIT BUTTON
---------------------------------------------------------------------

function Bot:WaitForButton(
    aliases,
    timeout
)

    local started =
        os.clock()

    while self.Running do

        local button =
            self:FindGuiButton(
                aliases
            )

        if button then
            return button
        end

        if os.clock() - started
            >= timeout then

            return nil
        end

        task.wait(0.15)
    end

    return nil
end

---------------------------------------------------------------------
-- BUTTON CONTEXT TEXT
---------------------------------------------------------------------

function Bot:GetObjectContextText(object)

    local textParts = {}

    local current = object

    ---------------------------------------------------------------
    -- Смотрим несколько родителей вверх.
    ---------------------------------------------------------------

    for _ = 1, 5 do

        if not current then
            break
        end

        table.insert(
            textParts,
            normalize(current.Name)
        )

        if current:IsA("TextLabel")
            or current:IsA("TextButton") then

            table.insert(
                textParts,
                normalize(current.Text)
            )
        end

        -----------------------------------------------------------
        -- И текст рядом с кнопкой.
        -----------------------------------------------------------

        for _, child
            in ipairs(current:GetDescendants()) do

            if child:IsA("TextLabel")
                or child:IsA("TextButton") then

                table.insert(
                    textParts,
                    normalize(child.Text)
                )
            end
        end

        current = current.Parent
    end

    return table.concat(
        textParts,
        " "
    )
end

---------------------------------------------------------------------
-- CONTEXT HAS WORD
---------------------------------------------------------------------

function Bot:ContextMatches(
    object,
    aliases
)

    local context =
        self:GetObjectContextText(
            object
        )

    for _, alias
        in ipairs(aliases) do

        local wanted =
            normalize(alias)

        if string.find(
            context,
            wanted,
            1,
            true
        ) then

            return true
        end
    end

    return false
end

---------------------------------------------------------------------
-- ENEMY
---------------------------------------------------------------------

function Bot:IsEnemy(player)

    if player == LocalPlayer then
        return false
    end

    if not CONFIG.IgnoreSameTeam then
        return true
    end

    if LocalPlayer.Team
        and player.Team
        and LocalPlayer.Team == player.Team then

        return false
    end

    return true
end

---------------------------------------------------------------------
-- RAYCAST
---------------------------------------------------------------------

function Bot:GetRaycastParams()

    local params =
        RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {
        self.Character
    }

    params.IgnoreWater = true

    return params
end

---------------------------------------------------------------------
-- EYE
---------------------------------------------------------------------

function Bot:GetEyePosition()

    if self.Head then
        return self.Head.Position
    end

    return self.Root.Position
        + Vector3.new(0, 2, 0)
end

---------------------------------------------------------------------
-- LOS
---------------------------------------------------------------------

function Bot:CanSee(character)

    local target =
        character:FindFirstChild("Head")
        or character:FindFirstChild(
            "HumanoidRootPart"
        )

    if not target then
        return false
    end

    local origin =
        self:GetEyePosition()

    local direction =
        target.Position - origin

    local result =
        Workspace:Raycast(
            origin,
            direction,
            self:GetRaycastParams()
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
-- FIND TARGET
---------------------------------------------------------------------

function Bot:FindTarget()

    local nearest = nil
    local nearestDistance = math.huge

    for _, player
        in ipairs(
            Players:GetPlayers()
        ) do

        if not self:IsEnemy(player) then
            continue
        end

        local character,
            humanoid,
            root =
            getPlayerCharacter(player)

        if not character then
            continue
        end

        local distance =
            (
                root.Position
                - self.Root.Position
            ).Magnitude

        if distance
            > CONFIG.DetectionRadius then

            continue
        end

        if distance
            >= nearestDistance then

            continue
        end

        if not self:CanSee(
            character
        ) then

            continue
        end

        nearest = player
        nearestDistance = distance
    end

    return nearest
end

---------------------------------------------------------------------
-- DETECTION
---------------------------------------------------------------------

function Bot:UpdateDetection()

    if os.clock()
        - self.LastDetection
        < CONFIG.DetectionInterval then

        return
    end

    self.LastDetection =
        os.clock()

    local player =
        self:FindTarget()

    if not player then
        return
    end

    self.Target = player

    local _, _, root =
        getPlayerCharacter(player)

    if root then

        self.LastSeenPosition =
            root.Position

        self.LastSeenTime =
            os.clock()
    end
end

---------------------------------------------------------------------
-- PATH
---------------------------------------------------------------------

function Bot:ComputePath(destination)

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
                self.Root.Position,
                destination
            )
        end)

    if not success
        or path.Status
            ~= Enum.PathStatus.Success then

        self.PathWaypoints = {}

        return false
    end

    self.PathWaypoints =
        path:GetWaypoints()

    self.PathIndex =
        #self.PathWaypoints >= 2
        and 2
        or 1

    self.LastPathDestination =
        destination

    self.LastPathTime =
        os.clock()

    return true
end

---------------------------------------------------------------------
-- REPATH
---------------------------------------------------------------------

function Bot:NeedsRepath(destination)

    if #self.PathWaypoints == 0 then
        return true
    end

    if os.clock()
        - self.LastPathTime
        >= CONFIG.RepathInterval then

        return true
    end

    if self.LastPathDestination then

        if (
            destination
            - self.LastPathDestination
        ).Magnitude >= CONFIG.RepathDistance then

            return true
        end
    end

    return false
end

---------------------------------------------------------------------
-- FOLLOW PATH
---------------------------------------------------------------------

function Bot:FollowPath()

    local waypoint =
        self.PathWaypoints[
            self.PathIndex
        ]

    if not waypoint then
        return false
    end

    local distance =
        (
            self.Root.Position
            - waypoint.Position
        ).Magnitude

    if distance
        <= CONFIG.WaypointReachDistance then

        self.PathIndex += 1

        waypoint =
            self.PathWaypoints[
                self.PathIndex
            ]

        if not waypoint then
            return false
        end
    end

    if waypoint.Action
        == Enum.PathWaypointAction.Jump then

        self.Humanoid.Jump =
            true
    end

    self.Humanoid:MoveTo(
        waypoint.Position
    )

    return true
end

---------------------------------------------------------------------
-- MOVE
---------------------------------------------------------------------

function Bot:MoveTo(destination)

    self.Humanoid.AutoRotate = true

    if self:NeedsRepath(destination) then

        if not self:ComputePath(
            destination
        ) then

            self.Humanoid:MoveTo(
                destination
            )

            return
        end
    end

    self:FollowPath()
end

---------------------------------------------------------------------
-- STOP
---------------------------------------------------------------------

function Bot:StopMoving()

    if not self.Root
        or not self.Humanoid then

        return
    end

    self.Humanoid:MoveTo(
        self.Root.Position
    )
end

---------------------------------------------------------------------
-- PATROL POINTS
---------------------------------------------------------------------

function Bot:LoadPatrolPoints()

    self.PatrolPoints = {}

    local folder =
        Workspace:FindFirstChild(
            CONFIG.PatrolFolder
        )

    if not folder then
        return
    end

    for _, object
        in ipairs(folder:GetChildren()) do

        if object:IsA("BasePart") then

            table.insert(
                self.PatrolPoints,
                object
            )
        end
    end

    table.sort(
        self.PatrolPoints,

        function(a, b)
            return a.Name < b.Name
        end
    )
end

---------------------------------------------------------------------
-- RANDOM PATROL
---------------------------------------------------------------------

function Bot:GetRandomDestination()

    local radius =
        CONFIG.RandomPatrolRadius

    local base =
        self.SpawnPosition
        or self.Root.Position

    local point =
        base
        + Vector3.new(
            math.random(-radius, radius),
            0,
            math.random(-radius, radius)
        )

    local origin =
        point
        + Vector3.new(0, 120, 0)

    local result =
        Workspace:Raycast(
            origin,

            Vector3.new(
                0,
                -300,
                0
            ),

            self:GetRaycastParams()
        )

    if result then

        return result.Position
            + Vector3.new(0, 2, 0)
    end

    return point
end

---------------------------------------------------------------------
-- PATROL
---------------------------------------------------------------------

function Bot:Patrol()

    if self.HandlingMatchEnd
        or self.ClaimingRewards then

        return
    end

    if os.clock()
        < self.NextPatrol then

        return
    end

    ---------------------------------------------------------------
    -- ЗАДАННЫЕ ТОЧКИ
    ---------------------------------------------------------------

    if #self.PatrolPoints > 0 then

        local point =
            self.PatrolPoints[
                self.PatrolIndex
            ]

        if not point then

            self.PatrolIndex = 1
            return
        end

        if (
            self.Root.Position
            - point.Position
        ).Magnitude <= 5 then

            self.PatrolIndex += 1

            if self.PatrolIndex
                > #self.PatrolPoints then

                self.PatrolIndex = 1
            end

            self.PathWaypoints = {}

            self.NextPatrol =
                os.clock()
                + CONFIG.PatrolPause

            return
        end

        self:MoveTo(
            point.Position
        )

        return
    end

    ---------------------------------------------------------------
    -- RANDOM
    ---------------------------------------------------------------

    if not self.RandomPatrolDestination then

        self.RandomPatrolDestination =
            self:GetRandomDestination()

        self.PathWaypoints = {}
    end

    if (
        self.Root.Position
        - self.RandomPatrolDestination
    ).Magnitude <= 6 then

        self.RandomPatrolDestination = nil

        self.PathWaypoints = {}

        self.NextPatrol =
            os.clock()
            + CONFIG.PatrolPause

        return
    end

    self:MoveTo(
        self.RandomPatrolDestination
    )
end

---------------------------------------------------------------------
-- TOOL
---------------------------------------------------------------------

function Bot:GetCurrentTool()

    if not self.Character then
        return nil
    end

    return self.Character:
        FindFirstChildOfClass(
            "Tool"
        )
end

---------------------------------------------------------------------
-- FIND TOOL
---------------------------------------------------------------------

function Bot:FindTool(weaponName)

    local wanted =
        normalize(weaponName)

    local function search(parent)

        if not parent then
            return nil
        end

        for _, object
            in ipairs(
                parent:GetChildren()
            ) do

            if not object:IsA("Tool") then
                continue
            end

            local name =
                normalize(object.Name)

            if name == wanted
                or string.find(
                    name,
                    wanted,
                    1,
                    true
                ) then

                return object
            end
        end

        return nil
    end

    return search(self.Character)
        or search(
            LocalPlayer:
                FindFirstChildOfClass(
                    "Backpack"
                )
        )
end

---------------------------------------------------------------------
-- EQUIP
---------------------------------------------------------------------

function Bot:EquipBestWeapon()

    if not self.Humanoid then
        return nil
    end

    for _, weaponName
        in ipairs(
            CONFIG.WeaponPriority
        ) do

        local tool =
            self:FindTool(
                weaponName
            )

        if tool then

            if tool.Parent
                ~= self.Character then

                pcall(function()

                    self.Humanoid:
                        EquipTool(tool)
                end)
            end

            return tool
        end
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

            pcall(function()
                self.Humanoid:
                    EquipTool(tool)
            end)

            return tool
        end
    end

    return self:GetCurrentTool()
end

---------------------------------------------------------------------
-- AIM POSITION
---------------------------------------------------------------------

function Bot:GetAimPosition(
    character,
    root
)

    local part = root

    local head =
        character:FindFirstChild(
            "Head"
        )

    if CONFIG.PreferHead
        and head
        and math.random()
            <= CONFIG.HeadAimChance then

        part = head
    end

    local position =
        part.Position

    if CONFIG.Prediction then

        local distance =
            (
                position
                - self:GetEyePosition()
            ).Magnitude

        position +=
            root.AssemblyLinearVelocity
            * (
                distance
                / CONFIG.EstimatedBulletSpeed
            )
    end

    return position
end

---------------------------------------------------------------------
-- AIM
---------------------------------------------------------------------

function Bot:AimAt(position)

    if CONFIG.RotateCharacter then

        local flat =
            Vector3.new(
                position.X,
                self.Root.Position.Y,
                position.Z
            )

        if (
            flat
            - self.Root.Position
        ).Magnitude > 0.01 then

            self.Humanoid.AutoRotate =
                false

            self.Root.CFrame =
                CFrame.lookAt(
                    self.Root.Position,
                    flat
                )
        end
    end

    if CONFIG.RotateCamera
        and Camera then

        Camera.CFrame =
            CFrame.lookAt(
                Camera.CFrame.Position,
                position
            )
    end
end

---------------------------------------------------------------------
-- RELOAD
---------------------------------------------------------------------

function Bot:Reload()

    if self.Reloading then
        return
    end

    self.Reloading = true

    self:PressKey(
        Enum.KeyCode.R
    )

    task.delay(
        CONFIG.ReloadTime,

        function()

            Bot.Reloading = false
            Bot.ShotCounter = 0
        end
    )
end

---------------------------------------------------------------------
-- FIRE
---------------------------------------------------------------------

function Bot:Fire()

    if self.Reloading
        or self.HandlingMatchEnd
        or self.ClaimingRewards then

        return
    end

    if os.clock()
        - self.LastShot
        < CONFIG.FireDelay then

        return
    end

    local tool =
        self:GetCurrentTool()
        or self:EquipBestWeapon()

    if not tool then
        return
    end

    self.LastShot =
        os.clock()

    self.ShotCounter += 1

    ---------------------------------------------------------------
    -- Существующая система оружия.
    ---------------------------------------------------------------

    pcall(function()
        tool:Activate()
    end)

    if self.ShotCounter
        >= CONFIG.ReloadEveryShots then

        self:Reload()
    end
end

---------------------------------------------------------------------
-- BUY BUTTON
---------------------------------------------------------------------

function Bot:FindBuyButton(weaponName)

    local playerGui =
        LocalPlayer:
            FindFirstChildOfClass(
                "PlayerGui"
            )

    if not playerGui then
        return nil
    end

    local wanted =
        normalize(weaponName)

    for _, object
        in ipairs(
            playerGui:GetDescendants()
        ) do

        if not object:IsA(
            "GuiButton"
        ) then

            continue
        end

        if not isGuiVisible(object) then
            continue
        end

        local name =
            normalize(object.Name)

        local text =
            self:GetGuiText(object)

        if name == wanted
            or text == wanted
            or string.find(
                name,
                wanted,
                1,
                true
            )
            or string.find(
                text,
                wanted,
                1,
                true
            ) then

            return object
        end
    end

    return nil
end

---------------------------------------------------------------------
-- TRY BUY
---------------------------------------------------------------------

function Bot:TryBuyWeapon(weaponName)

    if self:FindTool(weaponName) then
        return true
    end

    self:PressKey(
        CONFIG.BuyKey
    )

    task.wait(
        CONFIG.BuyMenuDelay
    )

    local button =
        self:FindBuyButton(
            weaponName
        )

    if not button then

        self:PressKey(
            CONFIG.BuyKey
        )

        return false
    end

    self:ClickButton(
        button
    )

    task.wait(
        CONFIG.BuyClickDelay
    )

    self:PressKey(
        CONFIG.BuyKey
    )

    task.wait(0.15)

    return self:FindTool(
        weaponName
    ) ~= nil
end

---------------------------------------------------------------------
-- AUTO BUY
---------------------------------------------------------------------

function Bot:AutoBuy()

    if not CONFIG.AutoBuy then

        self:EquipBestWeapon()

        return
    end

    if self.HandlingMatchEnd then
        return
    end

    for _, weaponName
        in ipairs(
            CONFIG.BuyPriority
        ) do

        if not self.Running then
            return
        end

        if self:TryBuyWeapon(
            weaponName
        ) then

            print(
                "[AutoBot] bought:",
                weaponName
            )

            break
        end
    end

    self:EquipBestWeapon()
end

---------------------------------------------------------------------
-- CLEAR TARGET
---------------------------------------------------------------------

function Bot:ClearTarget()

    self.Target = nil

    self.LastSeenPosition = nil

    self.PathWaypoints = {}

    self.LastPathDestination = nil

    if self.Humanoid then
        self.Humanoid.AutoRotate = true
    end
end

---------------------------------------------------------------------
-- TARGET
---------------------------------------------------------------------

function Bot:ProcessTarget()

    local player = self.Target

    if not player then
        return false
    end

    local character,
        humanoid,
        root =
        getPlayerCharacter(player)

    if not character then

        self:ClearTarget()

        return false
    end

    local distance =
        (
            root.Position
            - self.Root.Position
        ).Magnitude

    ---------------------------------------------------------------
    -- VISIBLE
    ---------------------------------------------------------------

    if self:CanSee(character) then

        self.LastSeenPosition =
            root.Position

        self.LastSeenTime =
            os.clock()

        if distance
            <= CONFIG.AttackRange then

            local aim =
                self:GetAimPosition(
                    character,
                    root
                )

            self:AimAt(aim)

            if distance
                > CONFIG.AttackRange * 0.85 then

                self:MoveTo(
                    root.Position
                )

            else

                self:StopMoving()
            end

            self:Fire()

            return true
        end

        self:MoveTo(
            root.Position
        )

        return true
    end

    ---------------------------------------------------------------
    -- ПОСЛЕДНЯЯ ПОЗИЦИЯ
    ---------------------------------------------------------------

    if self.LastSeenPosition
        and os.clock()
            - self.LastSeenTime
            <= CONFIG.LostTargetTime then

        self:MoveTo(
            self.LastSeenPosition
        )

        return true
    end

    self:ClearTarget()

    return false
end

---------------------------------------------------------------------
-- REWARDS
---------------------------------------------------------------------

function Bot:FindClaimButtons()

    local found = {}

    local playerGui =
        LocalPlayer:
            FindFirstChildOfClass(
                "PlayerGui"
            )

    if not playerGui then
        return found
    end

    for _, object
        in ipairs(
            playerGui:GetDescendants()
        ) do

        if not object:IsA(
            "GuiButton"
        ) then

            continue
        end

        if not isGuiVisible(object) then
            continue
        end

        if not self:GuiMatches(
            object,
            CONFIG.ClaimAliases
        ) then

            continue
        end

        -----------------------------------------------------------
        -- Желательно, чтобы рядом было
        -- Hourly/Daily/Weekly/Monthly.
        -----------------------------------------------------------

        if self:ContextMatches(
            object,
            CONFIG.RewardAliases
        ) then

            table.insert(
                found,
                object
            )
        end
    end

    ---------------------------------------------------------------
    -- Fallback:
    -- если не нашли по контексту,
    -- нажмём видимые Claim.
    ---------------------------------------------------------------

    if #found == 0 then

        for _, object
            in ipairs(
                playerGui:GetDescendants()
            ) do

            if object:IsA("GuiButton")
                and isGuiVisible(object)
                and self:GuiMatches(
                    object,
                    CONFIG.ClaimAliases
                ) then

                table.insert(
                    found,
                    object
                )
            end
        end
    end

    return found
end

---------------------------------------------------------------------
-- CLAIM REWARDS
---------------------------------------------------------------------

function Bot:ClaimRewards()

    if not CONFIG.AutoClaimRewards then
        return
    end

    if self.ClaimingRewards
        or self.HandlingMatchEnd then

        return
    end

    self.ClaimingRewards = true

    print(
        "[AutoBot] checking rewards"
    )

    self:ClearTarget()

    self:StopMoving()

    ---------------------------------------------------------------
    -- N
    ---------------------------------------------------------------

    self:PressKey(
        CONFIG.RewardsKey
    )

    task.wait(
        CONFIG.RewardMenuDelay
    )

    ---------------------------------------------------------------
    -- HOME / домик
    ---------------------------------------------------------------

    if CONFIG.ClickHomeBeforeClaim then

        local home =
            self:FindGuiButton(
                CONFIG.HomeAliases
            )

        if home then

            self:ClickButton(home)

            task.wait(0.4)
        end
    end

    ---------------------------------------------------------------
    -- CLAIM ALL
    ---------------------------------------------------------------

    local buttons =
        self:FindClaimButtons()

    print(
        "[AutoBot] claim buttons:",
        #buttons
    )

    for _, button
        in ipairs(buttons) do

        if not self.Running then
            break
        end

        if button.Parent
            and isGuiVisible(button) then

            self:ClickButton(
                button
            )

            task.wait(0.25)
        end
    end

    ---------------------------------------------------------------
    -- Закрываем N меню.
    ---------------------------------------------------------------

    task.wait(0.3)

    self:PressKey(
        CONFIG.RewardsKey
    )

    task.wait(0.3)

    self.ClaimingRewards = false
end

---------------------------------------------------------------------
-- FIND MATCH-END CLOSE
---------------------------------------------------------------------

function Bot:FindMatchEndClose()

    local playerGui =
        LocalPlayer:
            FindFirstChildOfClass(
                "PlayerGui"
            )

    if not playerGui then
        return nil
    end

    local viewport =
        Camera
        and Camera.ViewportSize
        or Vector2.new(1920, 1080)

    for _, object
        in ipairs(
            playerGui:GetDescendants()
        ) do

        if not object:IsA(
            "GuiButton"
        ) then

            continue
        end

        if not isGuiVisible(object) then
            continue
        end

        if not self:GuiMatches(
            object,
            CONFIG.CloseAliases
        ) then

            continue
        end

        -----------------------------------------------------------
        -- Вариант №1:
        -- рядом есть Results/Victory/Defeat/etc.
        -----------------------------------------------------------

        if self:ContextMatches(
            object,
            CONFIG.ResultAliases
        ) then

            return object
        end

        -----------------------------------------------------------
        -- Вариант №2:
        -- Close справа снизу.
        -----------------------------------------------------------

        local pos =
            object.AbsolutePosition

        if pos.X
            > viewport.X * 0.55
            and pos.Y
            > viewport.Y * 0.55 then

            return object
        end
    end

    return nil
end

---------------------------------------------------------------------
-- SELECT SIDE
---------------------------------------------------------------------

function Bot:SelectSide()

    local aliases

    if string.upper(
        CONFIG.PreferredSide
    ) == "CT" then

        aliases =
            CONFIG.CTAliases

    else

        aliases =
            CONFIG.TAliases
    end

    print(
        "[AutoBot] waiting team:",
        CONFIG.PreferredSide
    )

    local button =
        self:WaitForButton(
            aliases,
            CONFIG.MenuTimeout
        )

    if not button then

        warn(
            "[AutoBot] team button not found"
        )

        return false
    end

    self:ClickButton(
        button
    )

    print(
        "[AutoBot] selected:",
        CONFIG.PreferredSide
    )

    return true
end

---------------------------------------------------------------------
-- PLAY AGAIN
---------------------------------------------------------------------

function Bot:PlayAgain()

    print(
        "[AutoBot] waiting for Play"
    )

    local play =
        self:WaitForButton(
            CONFIG.PlayAliases,
            CONFIG.MenuTimeout
        )

    if not play then

        warn(
            "[AutoBot] Play not found"
        )

        return false
    end

    self:ClickButton(play)

    print(
        "[AutoBot] Play clicked"
    )

    task.wait(
        CONFIG.MenuClickDelay
    )

    return self:SelectSide()
end

---------------------------------------------------------------------
-- HANDLE MATCH END
---------------------------------------------------------------------

function Bot:HandleMatchEnd(closeButton)

    if self.HandlingMatchEnd then
        return
    end

    self.HandlingMatchEnd = true

    self:ClearTarget()

    self:StopMoving()

    print(
        "[AutoBot] match finished"
    )

    ---------------------------------------------------------------
    -- CLOSE
    ---------------------------------------------------------------

    if closeButton
        and closeButton.Parent then

        self:ClickButton(
            closeButton
        )
    end

    print(
        "[AutoBot] Close clicked"
    )

    ---------------------------------------------------------------
    -- Ждём минуту.
    ---------------------------------------------------------------

    for _ = 1, CONFIG.MatchEndWait do

        if not self.Running then

            self.HandlingMatchEnd =
                false

            return
        end

        task.wait(1)
    end

    ---------------------------------------------------------------
    -- PLAY → SIDE
    ---------------------------------------------------------------

    if self.Running then

        self:PlayAgain()
    end

    self.HandlingMatchEnd =
        false
end

---------------------------------------------------------------------
-- MATCH END MONITOR
---------------------------------------------------------------------

function Bot:StartMatchEndMonitor()

    task.spawn(function()

        while Bot.Running do

            if CONFIG.AutoReplay
                and not Bot.HandlingMatchEnd
                and not Bot.ClaimingRewards then

                local close =
                    Bot:FindMatchEndClose()

                if close then

                    task.spawn(function()

                        Bot:HandleMatchEnd(
                            close
                        )
                    end)
                end
            end

            task.wait(
                CONFIG.MatchEndCheckInterval
            )
        end
    end)
end

---------------------------------------------------------------------
-- REWARD LOOP
---------------------------------------------------------------------

function Bot:StartRewardLoop()

    if not CONFIG.AutoClaimRewards then
        return
    end

    task.spawn(function()

        task.wait(
            CONFIG.FirstRewardCheckDelay
        )

        while Bot.Running do

            if not Bot.HandlingMatchEnd then

                pcall(function()
                    Bot:ClaimRewards()
                end)
            end

            local remaining =
                CONFIG.RewardCheckInterval

            while remaining > 0
                and Bot.Running do

                local chunk =
                    math.min(
                        5,
                        remaining
                    )

                task.wait(chunk)

                remaining -= chunk
            end
        end
    end)
end

---------------------------------------------------------------------
-- CHARACTER SPAWNED
---------------------------------------------------------------------

function Bot:CharacterSpawned(character)

    if not self.Running then
        return
    end

    character:WaitForChild(
        "Humanoid",
        10
    )

    character:WaitForChild(
        "HumanoidRootPart",
        10
    )

    task.wait(0.4)

    if not self:GetCharacter() then
        return
    end

    print(
        "[AutoBot] spawned"
    )

    self.SpawnPosition =
        self.Root.Position

    self.Target = nil

    self.LastSeenPosition = nil

    self.PathWaypoints = {}

    self.LastPathDestination = nil

    self.RandomPatrolDestination = nil

    self.ShotCounter = 0

    self.Reloading = false

    self:LoadPatrolPoints()

    ---------------------------------------------------------------
    -- BUY AFTER SPAWN
    ---------------------------------------------------------------

    task.spawn(function()

        task.wait(
            CONFIG.BuyDelayAfterSpawn
        )

        if not Bot.Running
            or Bot.HandlingMatchEnd then

            return
        end

        if Bot.Humanoid
            and Bot.Humanoid.Health > 0 then

            Bot:AutoBuy()
        end
    end)
end

---------------------------------------------------------------------
-- MAIN AI UPDATE
---------------------------------------------------------------------

function Bot:Update()

    if self.HandlingMatchEnd
        or self.ClaimingRewards then

        return
    end

    if not self.Character
        or not self.Character.Parent then

        return
    end

    if not self.Humanoid
        or self.Humanoid.Health <= 0 then

        return
    end

    self:UpdateDetection()

    if self.Target then

        if self:ProcessTarget() then
            return
        end
    end

    self:Patrol()
end

---------------------------------------------------------------------
-- START
---------------------------------------------------------------------

function Bot:Start()

    if self.Running then
        return
    end

    self.Running = true

    print(
        "================================"
    )

    print(
        "[AutoBot] STARTED"
    )

    print(
        "[AutoBot] Side:",
        CONFIG.PreferredSide
    )

    print(
        "================================"
    )

    ---------------------------------------------------------------
    -- RESPAWN
    ---------------------------------------------------------------

    self.CharacterConnection =
        LocalPlayer.CharacterAdded:
            Connect(function(character)

                if not Bot.Running then
                    return
                end

                task.spawn(function()

                    Bot:CharacterSpawned(
                        character
                    )
                end)
            end)

    ---------------------------------------------------------------
    -- CURRENT CHARACTER
    ---------------------------------------------------------------

    if LocalPlayer.Character then

        task.spawn(function()

            Bot:CharacterSpawned(
                LocalPlayer.Character
            )
        end)
    end

    ---------------------------------------------------------------
    -- AI
    ---------------------------------------------------------------

    task.spawn(function()

        while Bot.Running do

            local success, err =
                pcall(function()

                    Bot:Update()
                end)

            if not success then

                warn(
                    "[AutoBot AI]",
                    err
                )
            end

            task.wait(
                CONFIG.ThinkDelay
            )
        end
    end)

    ---------------------------------------------------------------
    -- REWARDS
    ---------------------------------------------------------------

    self:StartRewardLoop()

    ---------------------------------------------------------------
    -- MATCH END
    ---------------------------------------------------------------

    self:StartMatchEndMonitor()
end

---------------------------------------------------------------------
-- STOP
---------------------------------------------------------------------

function Bot:Stop()

    self.Running = false

    self:ClearTarget()

    if self.CharacterConnection then

        self.CharacterConnection:
            Disconnect()

        self.CharacterConnection = nil
    end

    if self.Humanoid
        and self.Root then

        pcall(function()

            self.Humanoid:MoveTo(
                self.Root.Position
            )

            self.Humanoid.AutoRotate =
                true
        end)
    end

    print(
        "[AutoBot] STOPPED"
    )
end

---------------------------------------------------------------------
-- EXPORT
---------------------------------------------------------------------

ENV.AutoBot = Bot

---------------------------------------------------------------------
-- START
---------------------------------------------------------------------

Bot:Start()
