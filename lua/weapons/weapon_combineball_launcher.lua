if SERVER then
    AddCSLuaFile()
    util.AddNetworkString("combineball_openmenu")
    util.AddNetworkString("combineball_setclass")
end

SWEP.PrintName = "Combine Ball Launcher"
SWEP.Category  = "Other"
SWEP.Author    = "regunkyle"
SWEP.Instructions = [[
- Left Click: Fire
- Right Click: Open menu (Classes + Instances)
- Reload: Cycle fire modes (Single, Auto, Spread Auto, Multi, Chaos)
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

local MODE_SINGLE     = 1
local MODE_AUTO       = 2
local MODE_SPREADAUTO = 3
local MODE_MULTI      = 4
local MODE_CHAOS      = 5

local ModeNames = {
    [MODE_SINGLE]     = "Single",
    [MODE_AUTO]       = "Automatic",
    [MODE_SPREADAUTO] = "Spread Auto",
    [MODE_MULTI]      = "Multi Fire (spread)",
    [MODE_CHAOS]      = "Chaos",
}

local BASE_SPEED         = 1800
local FIRE_DELAY_SINGLE  = 0.18
local FIRE_DELAY_AUTO    = 0.08
local FIRE_DELAY_SPREAD  = 0.22
local FIRE_DELAY_MULTI   = 0.5
local FIRE_DELAY_CHAOS   = 0.05
local SPREAD_DEG_MED     = 7
local SPREAD_DEG_WIDE    = 12
local SPREADAUTO_COUNT   = 4
local MULTI_COUNT        = 8
local CHAOS_MIN          = 1
local CHAOS_MAX          = 10

local DEFAULT_CBALL_CLASSES = {
    "sent_combine_ball_base",  -- new base
    "sent_combine_ball"        -- legacy name, if present
}

function SWEP:SetupDataTables()
    self:NetworkVar("Int",    0, "FireMode")
    self:NetworkVar("String", 0, "SpawnClass")
end

function SWEP:Initialize()
    self:SetHoldType("ar2")
    if self:GetFireMode() == 0 then
        self:SetFireMode(MODE_SINGLE)
    end
    if self:GetSpawnClass() == "" then
        self:SetSpawnClass(self:PickDefaultBallClass() or "")
    end
    self._ReloadHeld = false
    self._LastFM = -1
    self:UpdateAutomaticFlag(true)

    if SERVER then
        net.Receive("combineball_setclass", function(_, ply)
            if not IsValid(ply) then return end
            local wep = ply:GetActiveWeapon()
            if not IsValid(wep) or wep ~= self then return end
            local cls = net.ReadString() or ""
            wep:ServerSetSpawnClass(cls)
        end)
    end
end

function SWEP:Deploy()
    self._LastFM = -1
    self:UpdateAutomaticFlag(true)
    return true
end

local function RandomizedDirection(forward, spreadDeg)
    local ang = forward:Angle()
    if spreadDeg and spreadDeg > 0 then
        ang:RotateAroundAxis(ang:Up(),    math.Rand(-spreadDeg, spreadDeg))
        ang:RotateAroundAxis(ang:Right(), math.Rand(-spreadDeg, spreadDeg))
    end
    return ang:Forward()
end

function SWEP:ClassInheritsFrom(className, target)
    if not isstring(className) or not isstring(target) then return false end
    if className == target then return true end
    local seen = {}
    local cur = className
    while cur and not seen[cur] do
        seen[cur] = true
        if cur == target then return true end
        local stored = scripted_ents.GetStored(cur)
        if not stored then break end
        local base = stored.Base or (stored.t and stored.t.Base)
        if not base or base == cur then break end
        cur = base
    end
    return false
end

function SWEP:ClassUsesCombineBallCore(className)
    local stored = scripted_ents.GetStored(className)
    if not stored then return false end
    local t = stored.t or stored
    if not istable(t) then return false end
    if t.Ring or t.BounceFX or t.DamageFX or t.ExplosionFX then return true end
    if isstring(t.PrintName) and string.find(string.lower(t.PrintName), "combine ball", 1, true) then return true end
    if string.find(className, "sent_combine_ball", 1, true) then return true end
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
    local cls = ent:GetClass() or ""
    if self:IsClassCombineBallRelated(cls) then return true end
    if istable(ent.BounceFX) or istable(ent.DamageFX) or istable(ent.ExplosionFX) or istable(ent.Ring) then
        return true
    end
    if string.find(cls, "sent_combine_ball", 1, true) then return true end
    return false
end

function SWEP:GetCombineBallClasses()
    local out = {}
    local seen = {}

    for _, cls in ipairs(DEFAULT_CBALL_CLASSES) do
        local stored = scripted_ents.GetStored(cls)
        if stored and not seen[cls] then
            seen[cls] = true
            table.insert(out, {
                ClassName = cls,
                PrintName = (stored.t and stored.t.PrintName) or cls,
                Base      = (stored.t and stored.t.Base) or "unknown"
            })
        end
    end

    for key, val in pairs(scripted_ents.GetList()) do
        local cls, data
        if istable(val) and val.ClassName then
            cls  = val.ClassName
            data = val.t or val
        elseif isstring(key) and istable(val) then
            cls  = key
            data = val.t or val
        end
        if isstring(cls) and not seen[cls] then
            if self:IsClassCombineBallRelated(cls) then
                seen[cls] = true
                table.insert(out, {
                    ClassName = cls,
                    PrintName = (data and data.PrintName) or cls,
                    Base      = (data and data.Base) or "unknown"
                })
            end
        end
    end

    table.sort(out, function(a, b)
        return tostring(a.ClassName) < tostring(b.ClassName)
    end)

    return out
end

function SWEP:PickDefaultBallClass()
    for _, cls in ipairs(DEFAULT_CBALL_CLASSES) do
        if scripted_ents.GetStored(cls) then
            return cls
        end
    end
    local classes = self:GetCombineBallClasses()
    if classes[1] then return classes[1].ClassName end
    return nil
end

function SWEP:ServerSetSpawnClass(cls)
    if not SERVER then return end
    if not isstring(cls) or cls == "" then return end
    local stored = scripted_ents.GetStored(cls)
    if not stored then
        local owner = self:GetOwner()
        if IsValid(owner) then owner:ChatPrint("[CombineBall] Unknown class: " .. cls) end
        return
    end
    if not self:IsClassCombineBallRelated(cls) then
        local owner = self:GetOwner()
        if IsValid(owner) then owner:ChatPrint("[CombineBall] Class is not a Combine Ball: " .. cls) end
        return
    end
    self:SetSpawnClass(cls)
    local owner = self:GetOwner()
    if IsValid(owner) then
        owner:EmitSound("buttons/button15.wav", 60, 120, 0.4)
        owner:ChatPrint("[CombineBall] Spawn class set to: " .. cls)
    end
end

function SWEP:SpawnNewBall(spawnPos, dir)
    local cls = self:GetSpawnClass()
    if not isstring(cls) or cls == "" then
        cls = self:PickDefaultBallClass() or "sent_combine_ball_base"
        self:SetSpawnClass(cls)
    end
    local ball = ents.Create(cls)
    if not IsValid(ball) then return nil end
    ball:SetPos(spawnPos)
    ball:SetAngles(dir:Angle())
    ball:Spawn()
    ball:Activate()
    return ball
end

local function KickEntity(ent, owner, dir, speed)
    if not IsValid(ent) then return end
    dir   = dir or Vector(1,0,0)
    speed = speed or 1200

    if IsValid(owner) then
        ent:SetOwner(owner)
        if ent.SetPhysicsAttacker then
            ent:SetPhysicsAttacker(owner, 5)
        end
    end

    if ent.SetCollisionGroup then
        ent:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    end

    local function pushNow()
        if not IsValid(ent) then return end
        local phys = ent.GetPhysicsObject and ent:GetPhysicsObject() or nil
        if IsValid(phys) then
            local v = dir * speed
            phys:EnableMotion(true)
            phys:Wake()
            phys:SetVelocityInstantaneous(v)
            phys:AddVelocity(v)
            phys:ApplyForceCenter(v * (phys:GetMass() or 1))
        else
            if ent.SetVelocity then ent:SetVelocity(dir * speed) end
            if ent.SetLocalVelocity then ent:SetLocalVelocity(dir * speed) end
            local mvtype = ent:GetMoveType()
            if mvtype == MOVETYPE_NONE and ent.PhysicsInitSphere then
                ent:PhysicsInitSphere(4, "metal_bouncy")
                local p2 = ent:GetPhysicsObject()
                if IsValid(p2) then
                    p2:Wake()
                    p2:SetVelocityInstantaneous(dir * speed)
                end
            end
        end
    end

    pushNow()
    timer.Simple(0, pushNow)
end

function SWEP:LaunchBall(ball, srcPos, dir, speed)
    if not IsValid(ball) then return end
    ball:SetPos(srcPos)
    ball:SetAngles(dir:Angle())
    KickEntity(ball, self:GetOwner(), dir, speed or BASE_SPEED)
end

function SWEP:FireOne(dir, speed)
    if not SERVER then return end
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local src = owner:GetShootPos() + dir * 16
    local ball = self:SpawnNewBall(src, dir)
    if not IsValid(ball) then
        owner:ChatPrint("[CombineBall] Could not create '" .. (self:GetSpawnClass() or "?") .. "'. Is it installed?")
        return
    end
    self:LaunchBall(ball, src, dir, speed or BASE_SPEED)
end

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

    if mode == MODE_SINGLE then
        self:SetNextPrimaryFire(CurTime() + FIRE_DELAY_SINGLE)
        self:DoShootEffects()
        self:FireOne(aim, BASE_SPEED)

    elseif mode == MODE_AUTO then
        self:SetNextPrimaryFire(CurTime() + FIRE_DELAY_AUTO)
        self:DoShootEffects()
        self:FireOne(aim, BASE_SPEED)

    elseif mode == MODE_SPREADAUTO then
        self:SetNextPrimaryFire(CurTime() + FIRE_DELAY_SPREAD)
        self:DoShootEffects()
        for _ = 1, SPREADAUTO_COUNT do
            local dir = RandomizedDirection(aim, SPREAD_DEG_MED)
            self:FireOne(dir, BASE_SPEED)
        end

    elseif mode == MODE_MULTI then
        self:SetNextPrimaryFire(CurTime() + FIRE_DELAY_MULTI)
        self:DoShootEffects()
        for _ = 1, MULTI_COUNT do
            local dir = RandomizedDirection(aim, SPREAD_DEG_WIDE)
            self:FireOne(dir, BASE_SPEED)
        end

    elseif mode == MODE_CHAOS then
        self:SetNextPrimaryFire(CurTime() + FIRE_DELAY_CHAOS)
        self:DoShootEffects()
        local count = math.random(CHAOS_MIN, CHAOS_MAX)
        for _ = 1, count do
            local spread = math.random(0, SPREAD_DEG_WIDE)
            local speed  = math.random(900, 2400)
            local dir    = RandomizedDirection(aim, spread)
            self:FireOne(dir, speed)
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
        if SERVER then owner:PrintMessage(HUD_PRINTCENTER, "Fire Mode: " .. (ModeNames[mode] or "?")) end
    end
end

function SWEP:UpdateAutomaticFlag(force)
    local mode = self:GetFireMode()
    local auto = (mode == MODE_AUTO or mode == MODE_SPREADAUTO or mode == MODE_CHAOS)
    if force or self.Primary.Automatic ~= auto then
        self.Primary.Automatic = auto
    end
end

function SWEP:SecondaryAttack()
    if CLIENT then
        self:OpenBallMenu()
    end
    if SERVER then
        local owner = self:GetOwner()
        if IsValid(owner) and owner:IsPlayer() then
            net.Start("combineball_openmenu")
            net.Send(owner)
        end
    end
    self:SetNextSecondaryFire(CurTime() + 0.35)
end

if CLIENT then
    local function FormatDist(u)
        return tostring(math.Round(u)) .. "u"
    end

    function SWEP:OpenBallMenu()
        if IsValid(self._BallFrame) then
            self._BallFrame:Close()
        end

        local frame = vgui.Create("DFrame")
        frame:SetTitle("Combine Ball — Classes and Instances")
        frame:SetSize(780, 540)
        frame:Center()
        frame:MakePopup()
        self._BallFrame = frame

        local sheet = vgui.Create("DPropertySheet", frame)
        sheet:Dock(FILL)

        do
            local pnl = vgui.Create("DPanel", sheet)
            pnl:Dock(FILL)

            local top = vgui.Create("DPanel", pnl)
            top:Dock(TOP)
            top:SetTall(28)
            top:DockMargin(0,0,0,4)

            local curLbl = vgui.Create("DLabel", top)
            curLbl:Dock(LEFT)
            curLbl:SetWide(420)
            curLbl:SetContentAlignment(4)
            curLbl:SetText("Current spawn class: " .. (self:GetSpawnClass() ~= "" and self:GetSpawnClass() or "(auto)"))

            local refreshBtn = vgui.Create("DButton", top)
            refreshBtn:Dock(RIGHT)
            refreshBtn:SetWide(140)
            refreshBtn:SetText("Refresh instances")

            local list = vgui.Create("DListView", pnl)
            list:Dock(FILL)
            list:AddColumn("EntID"):SetFixedWidth(60)
            list:AddColumn("Class")
            list:AddColumn("PrintName")
            list:AddColumn("Distance")

            local function RefreshInstances()
                list:Clear()
                local ply = LocalPlayer()
                local ppos = IsValid(ply) and ply:GetPos() or vector_origin
                for _, ent in ipairs(ents.GetAll()) do
                    if self:IsCombineBallEntity(ent) then
                        local dist = math.sqrt(ppos:DistToSqr(ent:GetPos()))
                        local cls  = ent:GetClass() or "?"
                        local pn   = (ent.PrintName) or (ent.GetPrintName and ent:GetPrintName()) or cls
                        list:AddLine(ent:EntIndex(), cls, tostring(pn), FormatDist(dist))
                    end
                end
            end

            refreshBtn.DoClick = function()
                RefreshInstances()
                curLbl:SetText("Current spawn class: " .. (self:GetSpawnClass() ~= "" and self:GetSpawnClass() or "(auto)"))
            end

            RefreshInstances()
            sheet:AddSheet("Instances", pnl, "icon16/brick.png")
        end

        do
            local pnl = vgui.Create("DPanel", sheet)
            pnl:Dock(FILL)

            local top = vgui.Create("DPanel", pnl)
            top:Dock(TOP)
            top:SetTall(28)
            top:DockMargin(0,0,0,4)

            local useBtn = vgui.Create("DButton", top)
            useBtn:Dock(RIGHT)
            useBtn:SetWide(140)
            useBtn:SetText("Use selected")

            local list = vgui.Create("DListView", pnl)
            list:Dock(FILL)
            list:AddColumn("Class")
            list:AddColumn("PrintName")
            list:AddColumn("Base")

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

                if SERVER then
                    self:ServerSetSpawnClass(cls)
                else
                    net.Start("combineball_setclass")
                    net.WriteString(cls)
                    net.SendToServer()
                end
                surface.PlaySound("buttons/button15.wav")
            end

            sheet:AddSheet("Classes", pnl, "icon16/application_view_list.png")
        end
    end

    net.Receive("combineball_openmenu", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) and wep.OpenBallMenu then
            wep:OpenBallMenu()
        end
    end)
end

