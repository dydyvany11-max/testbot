--[[
    ExecutorBot.lua

    Клиентский AI-бот для собственного Roblox place.

    FLOW:

        EXECUTE
          ↓
        MODES
          ↓
        выбрать:
          Unranked
          Deathmatch
          Casual
          ↓
        Hover
          ↓
        Select
          ↓
        Play
          ↓
        T / CT
          ↓
        Spawn
          ↓
        Buy
          ↓
        Patrol
          ↓
        Detection
          ↓
        Chase
          ↓
        Aim
          ↓
        Tool:Activate()
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
-- GLOBAL ENVIRONMENT
---------------------------------------------------------------------

local ENV =
    getgenv
    and getgenv()
    or _G

---------------------------------------------------------------------
-- STOP PREVIOUS INSTANCE
---------------------------------------------------------------------

if ENV.ExecutorBot
    and ENV.ExecutorBot.Stop then

    pcall(function()
        ENV.ExecutorBot:Stop()
    end)
end

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local CONFIG = {

    -----------------------------------------------------------------
    -- GAME MODE
    -----------------------------------------------------------------

    -- "Unranked"
    -- "Deathmatch"
    -- "Casual"

    GameMode = "Unranked",

    -----------------------------------------------------------------
    -- TEAM
    -----------------------------------------------------------------

    -- "T"
    -- "CT"

    PreferredSide = "T",

    -----------------------------------------------------------------
    -- MENU
    -----------------------------------------------------------------

    AutoEnterGame = true,

    ModesAliases = {
        "Modes",
        "Mode",
    },

    ModeAliases = {

        Unranked = {
            "Unranked",
        },

        Deathmatch = {
            "Deathmatch",
            "Death Match",
        },

        Casual = {
            "Casual",
        },
    },

    SelectAliases = {
        "Select",
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

    MenuClickDelay = 0.40,

    HoverDelay = 0.45,

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

    -- 1 = всегда пытается вести в голову.
    HeadAimChance = 0.90,

    RotateCharacter = true,

    -- Если оружие стреляет туда,
    -- куда направлена камера.
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

    BuyDelayAfterSpawn = 1.2,

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
    -- WEAPON EQUIP
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

Bot.CharacterConnection = nil

---------------------------------------------------------------------
-- NORMALIZE
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
-- GUI VISIBLE
---------------------------------------------------------------------

local function isGuiVisible(object)

    local current = object

    while current do

        if current:IsA("GuiObject") then

            if not current.Visible then
                return false
            end
        end

        current = current.Parent
    end

    return true
end

---------------------------------------------------------------------
-- GET CHARACTER DATA
---------------------------------------------------------------------

local function getPlayerCharacter(player)

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
        or not root then

        return nil
    end

    if humanoid.Health <= 0 then
        return nil
    end

    return character, humanoid, root
end

---------------------------------------------------------------------
-- UPDATE LOCAL CHARACTER
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

    if not humanoid
        or not root then

        return false
    end

    self.Character =
        character

    self.Humanoid =
        humanoid

    self.Root =
        root

    self.Head =
        character:FindFirstChild(
            "Head"
        )

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
    -- firesignal если executor поддерживает.
    -----------------------------------------------------------------

    if firesignal
        and button:IsA("GuiButton") then

        local success =
            pcall(function()

                firesignal(
                    button.Activated
                )

                if button:IsA("TextButton")
                    or button:IsA("ImageButton") then

                    firesignal(
                        button.MouseButton1Click
                    )
                end
            end)

        if success then

            task.wait(0.05)

            return true
        end
    end

    -----------------------------------------------------------------
    -- Mouse input fallback.
    -----------------------------------------------------------------

    if not button:IsA("GuiObject") then
        return false
    end

    local position =
        button.AbsolutePosition

    local size =
        button.AbsoluteSize

    local x =
        position.X
        + size.X / 2

    local y =
        position.Y
        + size.Y / 2

    local success =
        pcall(function()

            VirtualInputManager:SendMouseMoveEvent(
                x,
                y,
                game
            )

            task.wait(0.05)

            VirtualInputManager:SendMouseButtonEvent(
                x,
                y,
                0,
                true,
                game,
                0
            )

            task.wait(0.05)

            VirtualInputManager:SendMouseButtonEvent(
                x,
                y,
                0,
                false,
                game,
                0
            )
        end)

    return success
end

---------------------------------------------------------------------
-- HOVER
---------------------------------------------------------------------

function Bot:HoverObject(object)

    if not object
        or not object:IsA("GuiObject") then

        return false
    end

    local position =
        object.AbsolutePosition

    local size =
        object.AbsoluteSize

    local x =
        position.X
        + size.X / 2

    local y =
        position.Y
        + size.Y / 2

    return pcall(function()

        VirtualInputManager:SendMouseMoveEvent(
            x,
            y,
            game
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

function Bot:GuiMatches(
    object,
    aliases
)

    local name =
        normalize(
            object.Name
        )

    local text =
        self:GetGuiText(
            object
        )

    for _, alias in ipairs(aliases) do

        local wanted =
            normalize(alias)

        if name == wanted
            or text == wanted then

            return true
        end

        if #wanted >= 3 then

            if string.find(
                name,
                wanted,
                1,
                true
            ) then

                return true
            end

            if string.find(
                text,
                wanted,
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
-- FIND GUI
---------------------------------------------------------------------

function Bot:FindGuiObject(
    aliases,
    onlyButtons
)

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

        if onlyButtons then

            if not object:IsA(
                "GuiButton"
            ) then

                continue
            end

        else

            if not object:IsA(
                "GuiObject"
            ) then

                continue
            end
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
-- WAIT GUI
---------------------------------------------------------------------

function Bot:WaitForGuiObject(
    aliases,
    onlyButtons,
    timeout
)

    local start =
        os.clock()

    while self.Running do

        local object =
            self:FindGuiObject(
                aliases,
                onlyButtons
            )

        if object then
            return object
        end

        if os.clock() - start
            >= timeout then

            return nil
        end

        task.wait(0.15)
    end

    return nil
end

---------------------------------------------------------------------
-- OPEN MODES
---------------------------------------------------------------------

function Bot:OpenModes()

    print(
        "[BOT] Waiting for Modes..."
    )

    local button =
        self:WaitForGuiObject(
            CONFIG.ModesAliases,
            true,
            CONFIG.MenuTimeout
        )

    if not button then

        warn(
            "[BOT] Modes button not found"
        )

        return false
    end

    print(
        "[BOT] Modes found:",
        button:GetFullName()
    )

    self:ClickButton(
        button
    )

    task.wait(
        CONFIG.MenuClickDelay
    )

    return true
end

---------------------------------------------------------------------
-- CURRENT MODE ALIASES
---------------------------------------------------------------------

function Bot:GetModeAliases()

    return CONFIG.ModeAliases[
        CONFIG.GameMode
    ] or {
        CONFIG.GameMode
    }
end

---------------------------------------------------------------------
-- FIND MODE
---------------------------------------------------------------------

function Bot:FindModeCard()

    local aliases =
        self:GetModeAliases()

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

        if not object:IsA(
            "GuiObject"
        ) then
            continue
        end

        if not isGuiVisible(object) then
            continue
        end

        if not self:GuiMatches(
            object,
            aliases
        ) then
            continue
        end

        -------------------------------------------------------------
        -- Ищем крупный parent-контейнер карточки.
        -------------------------------------------------------------

        local current =
            object

        local best =
            object

        for _ = 1, 7 do

            if not current
                or not current.Parent then

                break
            end

            if current:IsA(
                "GuiObject"
            ) then

                local size =
                    current.AbsoluteSize

                if size.X >= 100
                    and size.Y >= 50 then

                    best =
                        current
                end
            end

            current =
                current.Parent
        end

        return best
    end

    return nil
end

---------------------------------------------------------------------
-- SELECT MODE
---------------------------------------------------------------------

function Bot:SelectMode()

    if not self:OpenModes() then
        return false
    end

    print(
        "[BOT] Looking for mode:",
        CONFIG.GameMode
    )

    local started =
        os.clock()

    local card = nil

    while self.Running do

        card =
            self:FindModeCard()

        if card then
            break
        end

        if os.clock() - started
            >= CONFIG.MenuTimeout then

            break
        end

        task.wait(0.15)
    end

    if not card then

        warn(
            "[BOT] Mode card not found:",
            CONFIG.GameMode
        )

        return false
    end

    print(
        "[BOT] Mode found:",
        card:GetFullName()
    )

    -----------------------------------------------------------------
    -- HOVER
    -----------------------------------------------------------------

    self:HoverObject(
        card
    )

    task.wait(
        CONFIG.HoverDelay
    )

    -----------------------------------------------------------------
    -- SELECT появляется после hover.
    -----------------------------------------------------------------

    local selectButton = nil

    local selectStart =
        os.clock()

    while self.Running
        and os.clock() - selectStart < 5 do

        self:HoverObject(
            card
        )

        selectButton =
            self:FindGuiObject(
                CONFIG.SelectAliases,
                true
            )

        if selectButton then
            break
        end

        task.wait(0.10)
    end

    if not selectButton then

        warn(
            "[BOT] Select not found"
        )

        return false
    end

    print(
        "[BOT] Clicking Select"
    )

    self:ClickButton(
        selectButton
    )

    task.wait(
        CONFIG.MenuClickDelay
    )

    return true
end

---------------------------------------------------------------------
-- PLAY
---------------------------------------------------------------------

function Bot:ClickPlay()

    print(
        "[BOT] Waiting for Play..."
    )

    local button =
        self:WaitForGuiObject(
            CONFIG.PlayAliases,
            true,
            CONFIG.MenuTimeout
        )

    if not button then

        warn(
            "[BOT] Play not found"
        )

        return false
    end

    print(
        "[BOT] Clicking Play"
    )

    self:ClickButton(
        button
    )

    task.wait(
        CONFIG.MenuClickDelay
    )

    return true
end

---------------------------------------------------------------------
-- TEAM SELECT
---------------------------------------------------------------------

function Bot:SelectTeam()

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
        "[BOT] Waiting for team:",
        CONFIG.PreferredSide
    )

    local button =
        self:WaitForGuiObject(
            aliases,
            true,
            CONFIG.MenuTimeout
        )

    if not button then

        warn(
            "[BOT] Team button not found"
        )

        return false
    end

    print(
        "[BOT] Selecting:",
        CONFIG.PreferredSide
    )

    self:ClickButton(
        button
    )

    task.wait(
        CONFIG.MenuClickDelay
    )

    return true
end

---------------------------------------------------------------------
-- COMPLETE MENU FLOW
---------------------------------------------------------------------

function Bot:EnterGame()

    if not CONFIG.AutoEnterGame then
        return true
    end

    print(
        "[BOT] Starting menu automation"
    )

    ---------------------------------------------------------------
    -- MODES -> MODE -> SELECT
    ---------------------------------------------------------------

    if not self:SelectMode() then
        return false
    end

    ---------------------------------------------------------------
    -- PLAY
    ---------------------------------------------------------------

    if not self:ClickPlay() then
        return false
    end

    ---------------------------------------------------------------
    -- TEAM
    ---------------------------------------------------------------

    if not self:SelectTeam() then
        return false
    end

    print(
        "[BOT] Menu completed"
    )

    return true
end

---------------------------------------------------------------------
-- IS ENEMY
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
        and LocalPlayer.Team
            == player.Team then

        return false
    end

    return true
end

---------------------------------------------------------------------
-- RAYCAST PARAMS
---------------------------------------------------------------------

function Bot:GetRaycastParams()

    local params =
        RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {
        self.Character,
    }

    params.IgnoreWater =
        true

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
        + Vector3.new(
            0,
            2,
            0
        )
end

---------------------------------------------------------------------
-- LINE OF SIGHT
---------------------------------------------------------------------

function Bot:CanSee(character)

    local target =
        character:FindFirstChild(
            "Head"
        )
        or character:FindFirstChild(
            "HumanoidRootPart"
        )

    if not target then
        return false
    end

    local origin =
        self:GetEyePosition()

    local direction =
        target.Position
        - origin

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

    local nearestDistance =
        math.huge

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
            getPlayerCharacter(
                player
            )

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

        nearest =
            player

        nearestDistance =
            distance
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

    self.Target =
        player

    local _,
        _,
        root =
        getPlayerCharacter(
            player
        )

    if root then

        self.LastSeenPosition =
            root.Position

        self.LastSeenTime =
            os.clock()
    end
end

---------------------------------------------------------------------
-- COMPUTE PATH
---------------------------------------------------------------------

function Bot:ComputePath(
    destination
)

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

    if #self.PathWaypoints >= 2 then

        self.PathIndex =
            2

    else

        self.PathIndex =
            1
    end

    self.LastPathDestination =
        destination

    self.LastPathTime =
        os.clock()

    return true
end

---------------------------------------------------------------------
-- SHOULD REPATH
---------------------------------------------------------------------

function Bot:NeedsRepath(
    destination
)

    if #self.PathWaypoints
        == 0 then

        return true
    end

    if os.clock()
        - self.LastPathTime
        >= CONFIG.RepathInterval then

        return true
    end

    if self.LastPathDestination then

        local moved =
            (
                destination
                - self.LastPathDestination
            ).Magnitude

        if moved
            >= CONFIG.RepathDistance then

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

function Bot:MoveTo(
    destination
)

    self.Humanoid.AutoRotate =
        true

    if self:NeedsRepath(
        destination
    ) then

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
-- STOP MOVE
---------------------------------------------------------------------

function Bot:StopMoving()

    if not self.Humanoid
        or not self.Root then

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
        in ipairs(
            folder:GetChildren()
        ) do

        if object:IsA(
            "BasePart"
        ) then

            table.insert(
                self.PatrolPoints,
                object
            )
        end
    end

    table.sort(
        self.PatrolPoints,

        function(a, b)

            return a.Name
                < b.Name
        end
    )
end

---------------------------------------------------------------------
-- RANDOM PATROL
---------------------------------------------------------------------

function Bot:GetRandomDestination()

    local radius =
        CONFIG.RandomPatrolRadius

    local offset =
        Vector3.new(

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

    local base =
        self.SpawnPosition
        or self.Root.Position

    local point =
        base + offset

    local origin =
        point
        + Vector3.new(
            0,
            120,
            0
        )

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
            + Vector3.new(
                0,
                2,
                0
            )
    end

    return point
end

---------------------------------------------------------------------
-- PATROL
---------------------------------------------------------------------

function Bot:Patrol()

    if os.clock()
        < self.NextPatrol then

        return
    end

    ---------------------------------------------------------------
    -- FIXED POINTS
    ---------------------------------------------------------------

    if #self.PatrolPoints > 0 then

        local point =
            self.PatrolPoints[
                self.PatrolIndex
            ]

        if not point then

            self.PatrolIndex =
                1

            return
        end

        local distance =
            (
                self.Root.Position
                - point.Position
            ).Magnitude

        if distance <= 5 then

            self.PatrolIndex += 1

            if self.PatrolIndex
                > #self.PatrolPoints then

                self.PatrolIndex =
                    1
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

    local distance =
        (
            self.Root.Position
            - self.RandomPatrolDestination
        ).Magnitude

    if distance <= 6 then

        self.RandomPatrolDestination =
            nil

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
-- CURRENT TOOL
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

function Bot:FindTool(
    weaponName
)

    local wanted =
        normalize(
            weaponName
        )

    local function search(parent)

        if not parent then
            return nil
        end

        for _, tool
            in ipairs(
                parent:GetChildren()
            ) do

            if tool:IsA("Tool") then

                local name =
                    normalize(
                        tool.Name
                    )

                if name == wanted
                    or string.find(
                        name,
                        wanted,
                        1,
                        true
                    ) then

                    return tool
                end
            end
        end

        return nil
    end

    local equipped =
        search(
            self.Character
        )

    if equipped then
        return equipped
    end

    local backpack =
        LocalPlayer:
            FindFirstChildOfClass(
                "Backpack"
            )

    return search(
        backpack
    )
end

---------------------------------------------------------------------
-- EQUIP BEST WEAPON
---------------------------------------------------------------------

function Bot:EquipBestWeapon()

    if not self.Humanoid then
        return nil
    end

    for _, name
        in ipairs(
            CONFIG.WeaponPriority
        ) do

        local tool =
            self:FindTool(
                name
            )

        if tool then

            if tool.Parent
                ~= self.Character then

                pcall(function()

                    self.Humanoid:
                        EquipTool(
                            tool
                        )
                end)
            end

            return tool
        end
    end

    local current =
        self:GetCurrentTool()

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

            pcall(function()

                self.Humanoid:
                    EquipTool(
                        tool
                    )
            end)

            return tool
        end
    end

    return nil
end

---------------------------------------------------------------------
-- AIM POSITION
---------------------------------------------------------------------

function Bot:GetAimPosition(
    character,
    root
)

    local targetPart =
        root

    local head =
        character:FindFirstChild(
            "Head"
        )

    if CONFIG.PreferHead
        and head
        and math.random()
            <= CONFIG.HeadAimChance then

        targetPart =
            head
    end

    local position =
        targetPart.Position

    ---------------------------------------------------------------
    -- SIMPLE PREDICTION
    ---------------------------------------------------------------

    if CONFIG.Prediction then

        local distance =
            (
                position
                - self:GetEyePosition()
            ).Magnitude

        local travelTime =
            distance
            / CONFIG.EstimatedBulletSpeed

        position +=
            root.AssemblyLinearVelocity
            * travelTime
    end

    return position
end

---------------------------------------------------------------------
-- AIM
---------------------------------------------------------------------

function Bot:AimAt(
    position
)

    ---------------------------------------------------------------
    -- CHARACTER
    ---------------------------------------------------------------

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

    ---------------------------------------------------------------
    -- CAMERA
    ---------------------------------------------------------------

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

    self.Reloading =
        true

    self:PressKey(
        Enum.KeyCode.R
    )

    task.delay(
        CONFIG.ReloadTime,

        function()

            if not Bot then
                return
            end

            Bot.Reloading =
                false

            Bot.ShotCounter =
                0
        end
    )
end

---------------------------------------------------------------------
-- FIRE
---------------------------------------------------------------------

function Bot:Fire()

    if self.Reloading then
        return
    end

    if os.clock()
        - self.LastShot
        < CONFIG.FireDelay then

        return
    end

    local tool =
        self:GetCurrentTool()

    if not tool then

        tool =
            self:EquipBestWeapon()
    end

    if not tool then
        return
    end

    self.LastShot =
        os.clock()

    self.ShotCounter += 1

    ---------------------------------------------------------------
    -- СТРЕЛЬБА ЧЕРЕЗ РЕАЛЬНЫЙ TOOL
    ---------------------------------------------------------------

    pcall(function()

        tool:Activate()

    end)

    ---------------------------------------------------------------
    -- RELOAD
    ---------------------------------------------------------------

    if self.ShotCounter
        >= CONFIG.ReloadEveryShots then

        self:Reload()
    end
end

---------------------------------------------------------------------
-- FIND BUY BUTTON
---------------------------------------------------------------------

function Bot:FindBuyButton(
    weaponName
)

    local playerGui =
        LocalPlayer:
            FindFirstChildOfClass(
                "PlayerGui"
            )

    if not playerGui then
        return nil
    end

    local wanted =
        normalize(
            weaponName
        )

    ---------------------------------------------------------------
    -- Exact first.
    ---------------------------------------------------------------

    for _, object
        in ipairs(
            playerGui:GetDescendants()
        ) do

        if not object:IsA(
            "GuiButton"
        ) then

            continue
        end

        if not isGuiVisible(
            object
        ) then

            continue
        end

        local name =
            normalize(
                object.Name
            )

        local text =
            self:GetGuiText(
                object
            )

        if name == wanted
            or text == wanted then

            return object
        end
    end

    ---------------------------------------------------------------
    -- Partial.
    ---------------------------------------------------------------

    for _, object
        in ipairs(
            playerGui:GetDescendants()
        ) do

        if not object:IsA(
            "GuiButton"
        ) then

            continue
        end

        if not isGuiVisible(
            object
        ) then

            continue
        end

        local name =
            normalize(
                object.Name
            )

        local text =
            self:GetGuiText(
                object
            )

        if string.find(
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

function Bot:TryBuyWeapon(
    weaponName
)

    if self:FindTool(
        weaponName
    ) then

        return true
    end

    ---------------------------------------------------------------
    -- OPEN B
    ---------------------------------------------------------------

    self:PressKey(
        CONFIG.BuyKey
    )

    task.wait(
        CONFIG.BuyMenuDelay
    )

    ---------------------------------------------------------------
    -- FIND WEAPON BUTTON
    ---------------------------------------------------------------

    local button =
        self:FindBuyButton(
            weaponName
        )

    if not button then

        -- close B
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

    ---------------------------------------------------------------
    -- CLOSE B
    ---------------------------------------------------------------

    self:PressKey(
        CONFIG.BuyKey
    )

    task.wait(0.1)

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

    print(
        "[BOT] AutoBuy..."
    )

    for _, weapon
        in ipairs(
            CONFIG.BuyPriority
        ) do

        if not self.Running then
            return
        end

        local success =
            self:TryBuyWeapon(
                weapon
            )

        if success then

            print(
                "[BOT] Bought:",
                weapon
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

    self.Target =
        nil

    self.LastSeenPosition =
        nil

    self.PathWaypoints = {}

    self.LastPathDestination =
        nil

    if self.Humanoid then

        self.Humanoid.AutoRotate =
            true
    end
end

---------------------------------------------------------------------
-- TARGET PROCESS
---------------------------------------------------------------------

function Bot:ProcessTarget()

    local player =
        self.Target

    if not player then
        return false
    end

    local character,
        humanoid,
        root =
        getPlayerCharacter(
            player
        )

    if not character then

        self:ClearTarget()

        return false
    end

    local distance =
        (
            root.Position
            - self.Root.Position
        ).Magnitude

    local visible =
        self:CanSee(
            character
        )

    ---------------------------------------------------------------
    -- VISIBLE
    ---------------------------------------------------------------

    if visible then

        self.LastSeenPosition =
            root.Position

        self.LastSeenTime =
            os.clock()

        -----------------------------------------------------------
        -- ATTACK RANGE
        -----------------------------------------------------------

        if distance
            <= CONFIG.AttackRange then

            local aimPosition =
                self:GetAimPosition(
                    character,
                    root
                )

            self:AimAt(
                aimPosition
            )

            -------------------------------------------------------
            -- FAR SIDE OF ATTACK RANGE:
            -- still approach.
            -------------------------------------------------------

            if distance
                > CONFIG.AttackRange
                    * 0.85 then

                self:MoveTo(
                    root.Position
                )

            else

                self:StopMoving()
            end

            -------------------------------------------------------
            -- FIRE
            -------------------------------------------------------

            self:Fire()

            return true
        end

        -----------------------------------------------------------
        -- CHASE
        -----------------------------------------------------------

        self:MoveTo(
            root.Position
        )

        return true
    end

    ---------------------------------------------------------------
    -- LOST BEHIND WALL
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

    ---------------------------------------------------------------
    -- REALLY LOST
    ---------------------------------------------------------------

    self:ClearTarget()

    return false
end

---------------------------------------------------------------------
-- UPDATE AI
---------------------------------------------------------------------

function Bot:Update()

    if not self.Character
        or not self.Character.Parent then

        return
    end

    if not self.Humanoid
        or self.Humanoid.Health <= 0 then

        return
    end

    ---------------------------------------------------------------
    -- SEARCH
    ---------------------------------------------------------------

    self:UpdateDetection()

    ---------------------------------------------------------------
    -- TARGET
    ---------------------------------------------------------------

    if self.Target then

        if self:ProcessTarget() then
            return
        end
    end

    ---------------------------------------------------------------
    -- NO TARGET
    ---------------------------------------------------------------

    self:Patrol()
end

---------------------------------------------------------------------
-- CHARACTER SPAWN
---------------------------------------------------------------------

function Bot:CharacterSpawned(
    character
)

    if not self.Running then
        return
    end

    ---------------------------------------------------------------
    -- Wait character.
    ---------------------------------------------------------------

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

        warn(
            "[BOT] Character initialization failed"
        )

        return
    end

    print(
        "[BOT] Character spawned"
    )

    self.SpawnPosition =
        self.Root.Position

    self.Target =
        nil

    self.LastSeenPosition =
        nil

    self.PathWaypoints = {}

    self.LastPathDestination =
        nil

    self.RandomPatrolDestination =
        nil

    self.ShotCounter =
        0

    self.Reloading =
        false

    self:LoadPatrolPoints()

    ---------------------------------------------------------------
    -- BUY
    ---------------------------------------------------------------

    task.spawn(function()

        task.wait(
            CONFIG.BuyDelayAfterSpawn
        )

        if not Bot.Running
            or not Bot.Humanoid
            or Bot.Humanoid.Health <= 0 then

            return
        end

        Bot:AutoBuy()
    end)
end

---------------------------------------------------------------------
-- START
---------------------------------------------------------------------

function Bot:Start()

    if self.Running then
        return
    end

    self.Running =
        true

    print(
        "==============================="
    )

    print(
        "[BOT] START"
    )

    print(
        "[BOT] Mode:",
        CONFIG.GameMode
    )

    print(
        "[BOT] Team:",
        CONFIG.PreferredSide
    )

    print(
        "==============================="
    )

    ---------------------------------------------------------------
    -- RESPAWN EVENT
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
    -- MENU FLOW
    ---------------------------------------------------------------

    task.spawn(function()

        if CONFIG.AutoEnterGame then

            local success =
                Bot:EnterGame()

            if not success then

                warn(
                    "[BOT] Menu automation failed"
                )

                return
            end
        end

        -----------------------------------------------------------
        -- Возможно character уже появился ДО event.
        -----------------------------------------------------------

        task.wait(0.5)

        local character =
            LocalPlayer.Character

        if character
            and character:FindFirstChild(
                "HumanoidRootPart"
            ) then

            Bot:CharacterSpawned(
                character
            )
        end
    end)

    ---------------------------------------------------------------
    -- AI LOOP
    ---------------------------------------------------------------

    task.spawn(function()

        while Bot.Running do

            local success, err =
                pcall(function()

                    Bot:Update()
                end)

            if not success then

                warn(
                    "[BOT AI ERROR]",
                    err
                )
            end

            task.wait(
                CONFIG.ThinkDelay
            )
        end
    end)
end

---------------------------------------------------------------------
-- STOP
---------------------------------------------------------------------

function Bot:Stop()

    self.Running =
        false

    self:ClearTarget()

    if self.CharacterConnection then

        self.CharacterConnection:
            Disconnect()

        self.CharacterConnection =
            nil
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
        "[BOT] STOPPED"
    )
end

---------------------------------------------------------------------
-- EXPORT
---------------------------------------------------------------------

ENV.ExecutorBot =
    Bot

---------------------------------------------------------------------
-- START
---------------------------------------------------------------------

Bot:Start()
