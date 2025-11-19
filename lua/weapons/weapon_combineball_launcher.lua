if SERVER then
    AddCSLuaFile()
    util.AddNetworkString("combineball_openmenu")
    util.AddNetworkString("combineball_setclass")
    util.AddNetworkString("combineball_setqueue")
end

SWEP.PrintName = "Combine Ball Launcher"
SWEP.Category  = "Other"
SWEP.Author    = "regunkyle"
SWEP.Instructions = [[
- Left Click: Fire
- Right Click: Open menu (Classes + Instances)
- Reload: Cycle fire modes
Multi-ball mode fires selected balls in rotation/random/all at once
]]

SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.UseHands  = true
SWEP.DrawCrosshair = true
SWEP.ViewModel  = "models/weapons/c_irifle.mdl"
SWEP.WorldModel = "models/weapons/w_irifle.mdl"
SWEP.HoldType   = "ar2"

SWEP.Primary.ClipSize    = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic   = false
SWEP.Primary.Ammo        = "none"

SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = false
SWEP.Secondary.Ammo        = "none"

-- ============================================================
-- CONFIGURATION
-- ============================================================
local CONFIG = {
    BASE_SPEED         = 1800,
    
    FIRE_DELAYS = {
        [1] = 0.18,  -- Single
        [2] = 0.08,  -- Auto
        [3] = 0.22,  -- Spread Auto
        [4] = 0.5,   -- Multi
        [5] = 0.05,  -- Chaos
    },
    
    SPREAD_DEG_MED     = 7,
    SPREAD_DEG_WIDE    = 12,
    SPREADAUTO_COUNT   = 4,
    MULTI_COUNT        = 8,
    CHAOS_MIN          = 1,
    CHAOS_MAX          = 10,
    
    CHAOS_SPEED_MIN    = 900,
    CHAOS_SPEED_MAX    = 2400,
}

-- Fire modes
local MODE_SINGLE     = 1
local MODE_AUTO       = 2
local MODE_SPREADAUTO = 3
local MODE_MULTI      = 4
local MODE_CHAOS      = 5

local MODE_NAMES = {
    [MODE_SINGLE]     = "Single",
    [MODE_AUTO]       = "Automatic",
    [MODE_SPREADAUTO] = "Spread Auto",
    [MODE_MULTI]      = "Multi Fire (spread)",
    [MODE_CHAOS]      = "Chaos",
}

-- Multi-ball modes
local MULTIBALL_CYCLE  = 1
local MULTIBALL_RANDOM = 2
local MULTIBALL_ALL    = 3

local MULTIBALL_NAMES = {
    [MULTIBALL_CYCLE]  = "Cycle",
    [MULTIBALL_RANDOM] = "Random",
    [MULTIBALL_ALL]    = "All at Once",
}

-- Default ball classes to look for
local DEFAULT_CBALL_CLASSES = {
    "prop_combine_ball",
    "sent_combine_ball_base",
    "sent_combine_ball"
}

-- ============================================================
-- CACHED DATA
-- ============================================================
local CachedBallClasses = nil
local CachedClassMap = {}

-- ============================================================
-- NETWORK HANDLERS (GLOBAL SCOPE)
-- ============================================================
if SERVER then
    net.Receive("combineball_setclass", function(_, ply)
        if not IsValid(ply) then return end
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep.Base ~= "weapon_base" or not wep.ServerSetSpawnClass then return end
        
        local cls = net.ReadString()
        if cls and cls ~= "" then
            wep:ServerSetSpawnClass(cls)
        end
    end)
    
    net.Receive("combineball_setqueue", function(_, ply)
        if not IsValid(ply) then return end
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep.Base ~= "weapon_base" or not wep.ServerSetQueue then return end
        
        local count = net.ReadUInt(8)
        local queue = {}
        for i = 1, count do
            local cls = net.ReadString()
            if cls and cls ~= "" then
                table.insert(queue, cls)
            end
        end
        
        local mode = net.ReadUInt(8)
        wep:ServerSetQueue(queue, mode)
    end)
end

if CLIENT then
    net.Receive("combineball_openmenu", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) and wep.OpenBallMenu then
            wep:OpenBallMenu()
        end
    end)
end

-- ============================================================
-- DATA TABLES
-- ============================================================
function SWEP:SetupDataTables()
    self:NetworkVar("Int",    0, "FireMode")
    self:NetworkVar("String", 0, "SpawnClass")
    self:NetworkVar("String", 1, "QueueData")      -- Serialized queue
    self:NetworkVar("Int",    1, "MultiBallMode")
    self:NetworkVar("Int",    2, "QueueIndex")
end

-- ============================================================
-- INITIALIZATION
-- ============================================================
function SWEP:Initialize()
    self:SetHoldType("ar2")
    
    if self:GetFireMode() == 0 then
        self:SetFireMode(MODE_SINGLE)
    end
    
    if self:GetSpawnClass() == "" then
        self:SetSpawnClass(self:PickDefaultBallClass() or "sent_combine_ball_base")
    end
    
    if self:GetMultiBallMode() == 0 then
        self:SetMultiBallMode(MULTIBALL_CYCLE)
    end
    
    self._ReloadHeld = false
    self._LastFM = -1
    self._QueueCache = nil
    
    self:UpdateAutomaticFlag(true)
end

function SWEP:Deploy()
    self._LastFM = -1
    self:UpdateAutomaticFlag(true)
    return true
end

function SWEP:OnRemove()
    if CLIENT and IsValid(self._BallFrame) then
        self._BallFrame:Close()
    end
end

-- ============================================================
-- QUEUE MANAGEMENT
-- ============================================================
function SWEP:SerializeQueue(queue)
    if not queue or #queue == 0 then return "" end
    return table.concat(queue, "|")
end

function SWEP:DeserializeQueue(str)
    if not str or str == "" then return {} end
    return string.Explode("|", str)
end

function SWEP:GetQueue()
    if self._QueueCache then return self._QueueCache end
    
    local data = self:GetQueueData()
    self._QueueCache = self:DeserializeQueue(data)
    return self._QueueCache
end

function SWEP:SetQueue(queue)
    self._QueueCache = queue
    self:SetQueueData(self:SerializeQueue(queue))
    self:SetQueueIndex(1)
end

function SWEP:ServerSetQueue(queue, mode)
    if not SERVER then return end
    
    -- Validate all classes
    local validated = {}
    for _, cls in ipairs(queue) do
        if self:ValidateClass(cls) then
            table.insert(validated, cls)
        end
    end
    
    self:SetQueue(validated)
    self:SetMultiBallMode(mode or MULTIBALL_CYCLE)
    
    local owner = self:GetOwner()
    if IsValid(owner) then
        owner:EmitSound("buttons/button15.wav", 60, 120, 0.4)
        if #validated > 0 then
            owner:ChatPrint(string.format("[CombineBall] Queue set: %d classes, mode: %s", 
                #validated, MULTIBALL_NAMES[mode] or "?"))
        else
            owner:ChatPrint("[CombineBall] Queue cleared")
        end
    end
end

function SWEP:GetNextQueueClass()
    local queue = self:GetQueue()
    if #queue == 0 then
        return self:GetSpawnClass()
    end
    
    local mode = self:GetMultiBallMode()
    local cls
    
    if mode == MULTIBALL_CYCLE then
        local idx = self:GetQueueIndex()
        cls = queue[idx]
        idx = idx + 1
        if idx > #queue then idx = 1 end
        self:SetQueueIndex(idx)
        
    elseif mode == MULTIBALL_RANDOM then
        cls = queue[math.random(1, #queue)]
        
    elseif mode == MULTIBALL_ALL then
        -- Return all, caller handles this
        return queue
    end
    
    return cls or queue[1]
end

-- ============================================================
-- CLASS VALIDATION & DETECTION
-- ============================================================
function SWEP:ValidateClass(className)
    if not isstring(className) or className == "" then return false end
    
    local stored = scripted_ents.GetStored(className)
    if not stored then return false end
    
    return self:IsClassCombineBallRelated(className)
end

function SWEP:ClassInheritsFrom(className, target)
    if not isstring(className) or not isstring(target) then return false end
    if className == target then return true end
    
    -- Check cache first
    local cacheKey = className .. ":" .. target
    if CachedClassMap[cacheKey] ~= nil then
        return CachedClassMap[cacheKey]
    end
    
    local seen = {}
    local cur = className
    local result = false
    
    while cur and not seen[cur] do
        seen[cur] = true
        if cur == target then
            result = true
            break
        end
        
        local stored = scripted_ents.GetStored(cur)
        if not stored then break end
        
        local base = stored.Base or (stored.t and stored.t.Base)
        if not base or base == cur then break end
        cur = base
    end
    
    CachedClassMap[cacheKey] = result
    return result
end

function SWEP:ClassUsesCombineBallCore(className)
    local stored = scripted_ents.GetStored(className)
    if not stored then return false end
    
    local t = stored.t or stored
    if not istable(t) then return false end
    
    -- Check for combine ball specific fields
    if t.Ring or t.BounceFX or t.DamageFX or t.ExplosionFX then return true end
    
    -- Check PrintName
    if isstring(t.PrintName) then
        local lower = string.lower(t.PrintName)
        if string.find(lower, "combine ball", 1, true) or 
           string.find(lower, "combineball", 1, true) then
            return true
        end
    end
    
    -- Check class name
    local lower = string.lower(className)
    if string.find(lower, "combine_ball", 1, true) or
       string.find(lower, "combineball", 1, true) then
        return true
    end
    
    return false
end

function SWEP:IsClassCombineBallRelated(className)
    if not isstring(className) then return false end
    
    if self:ClassInheritsFrom(className, "sent_combine_ball_base") then return true end
    if self:ClassInheritsFrom(className, "sent_combine_ball") then return true end
    if self:ClassUsesCombineBallCore(className) then return true end
    
    return false
end

function SWEP:IsCombineBallEntity(ent)
    if not IsValid(ent) then return false end
    
    local cls = ent:GetClass()
    if not cls then return false end
    
    if self:IsClassCombineBallRelated(cls) then return true end
    
    -- Check for combine ball fields
    if istable(ent.BounceFX) or istable(ent.DamageFX) or 
       istable(ent.ExplosionFX) or istable(ent.Ring) then
        return true
    end
    
    return false
end

function SWEP:GetCombineBallClasses()
    if CachedBallClasses then return CachedBallClasses end
    
    local out = {}
    local seen = {}

    -- Add defaults first
    for _, cls in ipairs(DEFAULT_CBALL_CLASSES) do
        local stored = scripted_ents.GetStored(cls)
        if stored and not seen[cls] then
            seen[cls] = true
            table.insert(out, {
                ClassName = cls,
                PrintName = (stored.t and stored.t.PrintName) or cls,
                Base      = (stored.t and stored.t.Base) or "base_entity"
            })
        end
    end

    -- Scan all entities
    for key, val in pairs(scripted_ents.GetList()) do
        local cls, data
        
        if istable(val) and val.ClassName then
            cls  = val.ClassName
            data = val.t or val
        elseif isstring(key) and istable(val) then
            cls  = key
            data = val.t or val
        end
        
        if isstring(cls) and not seen[cls] and self:IsClassCombineBallRelated(cls) then
            seen[cls] = true
            table.insert(out, {
                ClassName = cls,
                PrintName = (data and data.PrintName) or cls,
                Base      = (data and data.Base) or "base_entity"
            })
        end
    end

    -- Sort alphabetically
    table.sort(out, function(a, b)
        return a.ClassName < b.ClassName
    end)

    CachedBallClasses = out
    return out
end

function SWEP:PickDefaultBallClass()
    for _, cls in ipairs(DEFAULT_CBALL_CLASSES) do
        if scripted_ents.GetStored(cls) then
            return cls
        end
    end
    
    local classes = self:GetCombineBallClasses()
    return classes[1] and classes[1].ClassName or "sent_combine_ball_base"
end

function SWEP:ServerSetSpawnClass(cls)
    if not SERVER then return end
    if not self:ValidateClass(cls) then
        local owner = self:GetOwner()
        if IsValid(owner) then
            owner:ChatPrint("[CombineBall] Invalid or unknown class: " .. tostring(cls))
        end
        return
    end
    
    self:SetSpawnClass(cls)
    
    local owner = self:GetOwner()
    if IsValid(owner) then
        owner:EmitSound("buttons/button15.wav", 60, 120, 0.4)
        owner:ChatPrint("[CombineBall] Spawn class set to: " .. cls)
    end
end

-- ============================================================
-- BALL SPAWNING & LAUNCHING
-- ============================================================
local function RandomizedDirection(forward, spreadDeg)
    if not spreadDeg or spreadDeg <= 0 then return forward end
    
    local ang = forward:Angle()
    ang:RotateAroundAxis(ang:Up(),    math.Rand(-spreadDeg, spreadDeg))
    ang:RotateAroundAxis(ang:Right(), math.Rand(-spreadDeg, spreadDeg))
    return ang:Forward()
end

function SWEP:SpawnNewBall(cls, spawnPos, dir)
    if not isstring(cls) or cls == "" then
        cls = self:PickDefaultBallClass()
    end
    
    local ball = ents.Create(cls)
    if not IsValid(ball) then return nil end
    
    ball:SetPos(spawnPos)
    ball:SetAngles(dir:Angle())
    ball:Spawn()
    ball:Activate()
    
    return ball
end

function SWEP:LaunchBall(ball, owner, dir, speed)
    if not IsValid(ball) then return end
    
    speed = speed or CONFIG.BASE_SPEED
    
    if IsValid(owner) then
        ball:SetOwner(owner)
        if ball.SetPhysicsAttacker then
            ball:SetPhysicsAttacker(owner, 5)
        end
    end
    
    if ball.SetCollisionGroup then
        ball:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    end
    
    local phys = ball:GetPhysicsObject()
    if IsValid(phys) then
        local vel = dir * speed
        local mass = phys:GetMass()
        
        phys:EnableMotion(true)
        phys:Wake()
        phys:SetVelocityInstantaneous(vel)
        phys:ApplyForceCenter(vel * mass)
    else
        local vel = dir * speed
        if ball.SetVelocity then ball:SetVelocity(vel) end
        if ball.SetLocalVelocity then ball:SetLocalVelocity(vel) end
        
        -- Try to init physics if none
        if ball:GetMoveType() == MOVETYPE_NONE and ball.PhysicsInitSphere then
            ball:PhysicsInitSphere(4, "metal_bouncy")
            local phys2 = ball:GetPhysicsObject()
            if IsValid(phys2) then
                phys2:Wake()
                phys2:SetVelocityInstantaneous(vel)
            end
        end
    end
end

function SWEP:FireOne(cls, dir, speed)
    if not SERVER then return end
    
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local src = owner:GetShootPos() + dir * 16
    local ball = self:SpawnNewBall(cls, src, dir)
    
    if not IsValid(ball) then
        if self._LastErrorTime ~= CurTime() then -- Prevent spam
            self._LastErrorTime = CurTime()
            owner:ChatPrint("[CombineBall] Failed to create: " .. tostring(cls))
        end
        return
    end
    
    self:LaunchBall(ball, owner, dir, speed)
end

-- ============================================================
-- WEAPON ACTIONS
-- ============================================================
function SWEP:DoShootEffects()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    owner:SetAnimation(PLAYER_ATTACK1)
    
    if SERVER then
        owner:EmitSound("Weapon_IRifle.Single", 70, 100, 0.75, CHAN_WEAPON)
    end
end

function SWEP:PrimaryAttack()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local mode = self:GetFireMode()
    local aim  = owner:GetAimVector()
    
    self:SetNextPrimaryFire(CurTime() + (CONFIG.FIRE_DELAYS[mode] or 0.2))
    self:DoShootEffects()
    
    if mode == MODE_SINGLE then
        local cls = self:GetNextQueueClass()
        if istable(cls) then -- All mode
            for _, c in ipairs(cls) do
                self:FireOne(c, aim, CONFIG.BASE_SPEED)
            end
        else
            self:FireOne(cls, aim, CONFIG.BASE_SPEED)
        end
        
    elseif mode == MODE_AUTO then
        local cls = self:GetNextQueueClass()
        if istable(cls) then
            for _, c in ipairs(cls) do
                self:FireOne(c, aim, CONFIG.BASE_SPEED)
            end
        else
            self:FireOne(cls, aim, CONFIG.BASE_SPEED)
        end
        
    elseif mode == MODE_SPREADAUTO then
        local cls = self:GetNextQueueClass()
        local classes = istable(cls) and cls or {cls}
        
        for i = 1, CONFIG.SPREADAUTO_COUNT do
            local c = classes[((i - 1) % #classes) + 1]
            local dir = RandomizedDirection(aim, CONFIG.SPREAD_DEG_MED)
            self:FireOne(c, dir, CONFIG.BASE_SPEED)
        end
        
    elseif mode == MODE_MULTI then
        local cls = self:GetNextQueueClass()
        local classes = istable(cls) and cls or {cls}
        
        for i = 1, CONFIG.MULTI_COUNT do
            local c = classes[((i - 1) % #classes) + 1]
            local dir = RandomizedDirection(aim, CONFIG.SPREAD_DEG_WIDE)
            self:FireOne(c, dir, CONFIG.BASE_SPEED)
        end
        
    elseif mode == MODE_CHAOS then
        local cls = self:GetNextQueueClass()
        local classes = istable(cls) and cls or {cls}
        local count = math.random(CONFIG.CHAOS_MIN, CONFIG.CHAOS_MAX)
        
        for i = 1, count do
            local c = classes[math.random(1, #classes)]
            local spread = math.Rand(0, CONFIG.SPREAD_DEG_WIDE)
            local speed  = math.Rand(CONFIG.CHAOS_SPEED_MIN, CONFIG.CHAOS_SPEED_MAX)
            local dir    = RandomizedDirection(aim, spread)
            self:FireOne(c, dir, speed)
        end
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.35)
    
    if CLIENT then
        self:OpenBallMenu()
    elseif SERVER then
        local owner = self:GetOwner()
        if IsValid(owner) and owner:IsPlayer() then
            net.Start("combineball_openmenu")
            net.Send(owner)
        end
    end
end

function SWEP:Reload()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    if self._ReloadHeld then return end
    if not IsFirstTimePredicted() then return end
    
    self._ReloadHeld = true
    self:CycleFireMode()
end

function SWEP:Think()
    local owner = self:GetOwner()
    if IsValid(owner) then
        if not owner:KeyDown(IN_RELOAD) then
            self._ReloadHeld = false
        end
    else
        self._ReloadHeld = false
    end

    local fm = self:GetFireMode()
    if fm ~= self._LastFM then
        self._LastFM = fm
        self:UpdateAutomaticFlag()
    end
end

function SWEP:CycleFireMode()
    local mode = self:GetFireMode()
    if mode == 0 then mode = MODE_SINGLE end
    
    mode = mode + 1
    if mode > MODE_CHAOS then mode = MODE_SINGLE end

    self:SetFireMode(mode)
    self:UpdateAutomaticFlag()

    local owner = self:GetOwner()
    if IsValid(owner) then
        owner:EmitSound("buttons/lightswitch2.wav", 60, 120, 0.4)
        if SERVER then
            owner:PrintMessage(HUD_PRINTCENTER, "Fire Mode: " .. (MODE_NAMES[mode] or "?"))
        end
    end
end

function SWEP:UpdateAutomaticFlag(force)
    local mode = self:GetFireMode()
    local auto = (mode == MODE_AUTO or mode == MODE_SPREADAUTO or mode == MODE_CHAOS)
    
    if force or self.Primary.Automatic ~= auto then
        self.Primary.Automatic = auto
    end
end

-- ============================================================
-- CLIENT UI
-- ============================================================
if CLIENT then
    surface.CreateFont("CombineBallTitle", {
        font = "Roboto",
        size = 18,
        weight = 600,
    })
    
    surface.CreateFont("CombineBallLabel", {
        font = "Roboto",
        size = 14,
        weight = 400,
    })
    
    local function FormatDist(units)
        if units < 1000 then
            return string.format("%du", math.Round(units))
        else
            return string.format("%.1fk", units / 1000)
        end
    end
    
    function SWEP:OpenBallMenu()
        if IsValid(self._BallFrame) then
            self._BallFrame:Close()
        end

        local frame = vgui.Create("DFrame")
        frame:SetTitle("Combine Ball Launcher — Configuration")
        frame:SetSize(900, 600)
        frame:Center()
        frame:MakePopup()
        frame:SetDeleteOnClose(true)
        self._BallFrame = frame

        local sheet = vgui.Create("DPropertySheet", frame)
        sheet:Dock(FILL)
        sheet:DockMargin(4, 4, 4, 4)

        -- ============================================================
        -- MULTI-BALL QUEUE TAB
        -- ============================================================
        do
            local pnl = vgui.Create("DPanel", sheet)
            pnl:Dock(FILL)
            pnl.Paint = function(s, w, h)
                draw.RoundedBox(0, 0, 0, w, h, Color(40, 40, 40))
            end

            -- Top info panel
            local topInfo = vgui.Create("DPanel", pnl)
            topInfo:Dock(TOP)
            topInfo:SetTall(60)
            topInfo:DockMargin(4, 4, 4, 4)
            topInfo.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(50, 50, 50))
                draw.SimpleText("Multi-Ball Queue System", "CombineBallTitle", 8, 8, Color(255, 200, 100))
                draw.SimpleText("Select multiple classes to fire in rotation, random, or all at once", 
                    "CombineBallLabel", 8, 32, Color(200, 200, 200))
            end

            -- Mode selector
            local modePanel = vgui.Create("DPanel", pnl)
            modePanel:Dock(TOP)
            modePanel:SetTall(40)
            modePanel:DockMargin(4, 0, 4, 4)
            modePanel.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(50, 50, 50))
            end

            local modeLabel = vgui.Create("DLabel", modePanel)
            modeLabel:SetText("Queue Mode:")
            modeLabel:SetFont("CombineBallLabel")
            modeLabel:Dock(LEFT)
            modeLabel:SetWide(100)
            modeLabel:DockMargin(8, 0, 4, 0)
            modeLabel:SetContentAlignment(5)

            local modeCombo = vgui.Create("DComboBox", modePanel)
            modeCombo:Dock(LEFT)
            modeCombo:SetWide(150)
            modeCombo:DockMargin(0, 8, 8, 8)
            for mode, name in pairs(MULTIBALL_NAMES) do
                modeCombo:AddChoice(name, mode)
            end
            modeCombo:SetValue(MULTIBALL_NAMES[self:GetMultiBallMode()] or "Cycle")

            -- Queue list
            local queuePanel = vgui.Create("DPanel", pnl)
            queuePanel:Dock(LEFT)
            queuePanel:SetWide(300)
            queuePanel:DockMargin(4, 0, 2, 4)
            queuePanel.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(50, 50, 50))
            end

            local queueLabel = vgui.Create("DLabel", queuePanel)
            queueLabel:SetText("Current Queue:")
            queueLabel:SetFont("CombineBallLabel")
            queueLabel:Dock(TOP)
            queueLabel:SetTall(24)
            queueLabel:DockMargin(4, 4, 4, 2)

            local queueList = vgui.Create("DListView", queuePanel)
            queueList:Dock(FILL)
            queueList:DockMargin(4, 0, 4, 4)
            queueList:AddColumn("#"):SetFixedWidth(30)
            queueList:AddColumn("Class")
            queueList:SetMultiSelect(false)

            local function RefreshQueue()
                queueList:Clear()
                local queue = self:GetQueue()
                for i, cls in ipairs(queue) do
                    queueList:AddLine(i, cls)
                end
            end

            local queueBtns = vgui.Create("DPanel", queuePanel)
            queueBtns:Dock(BOTTOM)
            queueBtns:SetTall(32)
            queueBtns:DockMargin(4, 2, 4, 4)
            queueBtns.Paint = nil

            local btnRemove = vgui.Create("DButton", queueBtns)
            btnRemove:SetText("Remove Selected")
            btnRemove:Dock(LEFT)
            btnRemove:SetWide(145)
            btnRemove:DockMargin(0, 0, 2, 0)
            btnRemove.DoClick = function()
                local line = queueList:GetSelectedLine()
                if not line then surface.PlaySound("buttons/button10.wav") return end
                
                local queue = self:GetQueue()
                table.remove(queue, line)
                self:SetQueue(queue)
                RefreshQueue()
                surface.PlaySound("buttons/button14.wav")
            end

            local btnClear = vgui.Create("DButton", queueBtns)
            btnClear:SetText("Clear All")
            btnClear:Dock(RIGHT)
            btnClear:SetWide(145)
            btnClear:DockMargin(2, 0, 0, 0)
            btnClear.DoClick = function()
                self:SetQueue({})
                RefreshQueue()
                surface.PlaySound("buttons/button14.wav")
            end

            -- Available classes
            local classPanel = vgui.Create("DPanel", pnl)
            classPanel:Dock(FILL)
            classPanel:DockMargin(2, 0, 4, 4)
            classPanel.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(50, 50, 50))
            end

            local classLabel = vgui.Create("DLabel", classPanel)
            classLabel:SetText("Available Classes:")
            classLabel:SetFont("CombineBallLabel")
            classLabel:Dock(TOP)
            classLabel:SetTall(24)
            classLabel:DockMargin(4, 4, 4, 2)

            local classList = vgui.Create("DListView", classPanel)
            classList:Dock(FILL)
            classList:DockMargin(4, 0, 4, 4)
            classList:AddColumn("Class")
            classList:AddColumn("PrintName")
            classList:SetMultiSelect(false)

            local classes = self:GetCombineBallClasses()
            for _, info in ipairs(classes) do
                classList:AddLine(info.ClassName, tostring(info.PrintName or info.ClassName))
            end

            local classBtns = vgui.Create("DPanel", classPanel)
            classBtns:Dock(BOTTOM)
            classBtns:SetTall(32)
            classBtns:DockMargin(4, 2, 4, 4)
            classBtns.Paint = nil

            local btnAdd = vgui.Create("DButton", classBtns)
            btnAdd:SetText("Add to Queue →")
            btnAdd:Dock(FILL)
            btnAdd.DoClick = function()
                local line = classList:GetSelectedLine()
                if not line then surface.PlaySound("buttons/button10.wav") return end
                
                local row = classList:GetLine(line)
                if not IsValid(row) then return end
                
                local cls = row:GetValue(1)
                local queue = self:GetQueue()
                table.insert(queue, cls)
                self:SetQueue(queue)
                RefreshQueue()
                surface.PlaySound("buttons/button15.wav")
            end

            -- Apply button
            local applyPanel = vgui.Create("DPanel", pnl)
            applyPanel:Dock(BOTTOM)
            applyPanel:SetTall(40)
            applyPanel:DockMargin(4, 4, 4, 4)
            applyPanel.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(60, 100, 60))
            end

            local btnApply = vgui.Create("DButton", applyPanel)
            btnApply:SetText("Apply Queue to Weapon")
            btnApply:SetFont("CombineBallLabel")
            btnApply:Dock(FILL)
            btnApply:DockMargin(4, 4, 4, 4)
            btnApply.DoClick = function()
                local queue = self:GetQueue()
                local _, mode = modeCombo:GetSelected()
                mode = mode or MULTIBALL_CYCLE
                
                net.Start("combineball_setqueue")
                net.WriteUInt(#queue, 8)
                for _, cls in ipairs(queue) do
                    net.WriteString(cls)
                end
                net.WriteUInt(mode, 8)
                net.SendToServer()
                
                surface.PlaySound("buttons/button15.wav")
                frame:Close()
            end

            RefreshQueue()
            sheet:AddSheet("Multi-Ball Queue", pnl, "icon16/application_cascade.png")
        end

        -- ============================================================
        -- SINGLE CLASS TAB
        -- ============================================================
        do
            local pnl = vgui.Create("DPanel", sheet)
            pnl:Dock(FILL)
            pnl.Paint = function(s, w, h)
                draw.RoundedBox(0, 0, 0, w, h, Color(40, 40, 40))
            end

            local top = vgui.Create("DPanel", pnl)
            top:Dock(TOP)
            top:SetTall(50)
            top:DockMargin(4, 4, 4, 4)
            top.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(50, 50, 50))
            end

            local curLbl = vgui.Create("DLabel", top)
            curLbl:Dock(TOP)
            curLbl:SetTall(24)
            curLbl:SetFont("CombineBallLabel")
            curLbl:DockMargin(8, 8, 8, 0)
            curLbl:SetText("Current: " .. (self:GetSpawnClass() ~= "" and self:GetSpawnClass() or "(auto)"))
            curLbl:SetTextColor(Color(255, 200, 100))

            local useBtn = vgui.Create("DButton", top)
            useBtn:Dock(BOTTOM)
            useBtn:SetTall(24)
            useBtn:DockMargin(8, 2, 8, 4)
            useBtn:SetText("Use Selected Class")

            local list = vgui.Create("DListView", pnl)
            list:Dock(FILL)
            list:DockMargin(4, 0, 4, 4)
            list:AddColumn("Class")
            list:AddColumn("PrintName")
            list:AddColumn("Base")
            list:SetMultiSelect(false)

            local classes = self:GetCombineBallClasses()
            for _, info in ipairs(classes) do
                list:AddLine(info.ClassName, tostring(info.PrintName or info.ClassName), tostring(info.Base or ""))
            end

            function useBtn:DoClick()
                local line = list:GetSelectedLine()
                if not line then surface.PlaySound("buttons/button10.wav") return end
                
                local row = list:GetLine(line)
                if not IsValid(row) then return end
                
                local cls = row:GetValue(1)
                if not isstring(cls) or cls == "" then return end

                net.Start("combineball_setclass")
                net.WriteString(cls)
                net.SendToServer()
                
                surface.PlaySound("buttons/button15.wav")
                curLbl:SetText("Current: " .. cls)
            end

            sheet:AddSheet("Single Class", pnl, "icon16/application_view_list.png")
        end

        -- ============================================================
        -- INSTANCES TAB
        -- ============================================================
        do
            local pnl = vgui.Create("DPanel", sheet)
            pnl:Dock(FILL)
            pnl.Paint = function(s, w, h)
                draw.RoundedBox(0, 0, 0, w, h, Color(40, 40, 40))
            end

            local top = vgui.Create("DPanel", pnl)
            top:Dock(TOP)
            top:SetTall(32)
            top:DockMargin(4, 4, 4, 4)
            top.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(50, 50, 50))
            end

            local refreshBtn = vgui.Create("DButton", top)
            refreshBtn:Dock(RIGHT)
            refreshBtn:SetWide(140)
            refreshBtn:DockMargin(4, 4, 4, 4)
            refreshBtn:SetText("Refresh List")

            local countLbl = vgui.Create("DLabel", top)
            countLbl:Dock(FILL)
            countLbl:SetFont("CombineBallLabel")
            countLbl:DockMargin(8, 0, 4, 0)
            countLbl:SetContentAlignment(5)

            local list = vgui.Create("DListView", pnl)
            list:Dock(FILL)
            list:DockMargin(4, 0, 4, 4)
            list:AddColumn("EntID"):SetFixedWidth(60)
            list:AddColumn("Class")
            list:AddColumn("PrintName")
            list:AddColumn("Distance"):SetFixedWidth(80)

            local function RefreshInstances()
                list:Clear()
                local ply = LocalPlayer()
                local ppos = IsValid(ply) and ply:GetPos() or vector_origin
                local count = 0
                
                for _, ent in ipairs(ents.GetAll()) do
                    if self:IsCombineBallEntity(ent) then
                        count = count + 1
                        local dist = ppos:Distance(ent:GetPos())
                        local cls  = ent:GetClass() or "?"
                        local pn   = (ent.PrintName) or (ent.GetPrintName and ent:GetPrintName()) or cls
                        list:AddLine(ent:EntIndex(), cls, tostring(pn), FormatDist(dist))
                    end
                end
                
                countLbl:SetText(string.format("Found %d combine ball(s) in world", count))
            end

            refreshBtn.DoClick = function()
                RefreshInstances()
                surface.PlaySound("buttons/button15.wav")
            end

            RefreshInstances()
            sheet:AddSheet("Instances", pnl, "icon16/brick.png")
        end
    end
end
