-- lua/weapons/weapon_combineball_launcher.lua
if SERVER then
    AddCSLuaFile()
    util.AddNetworkString("combineball_openmenu")
end

SWEP.PrintName = "Combine Ball Launcher"
SWEP.Category  = "Other"
SWEP.Author    = "YourName"
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

-- Fire modes
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

-- Tuning
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

function SWEP:SetupDataTables()
    self:NetworkVar("Int", 0, "FireMode")
end

function SWEP:Initialize()
    self:SetHoldType("ar2")
    if self:GetFireMode() == 0 then
        self:SetFireMode(MODE_SINGLE)
    end
    self._ReloadHeld = false
    self._LastFM = -1
    self:UpdateAutomaticFlag(true)
end

function SWEP:Deploy()
    self._LastFM = -1
    self:UpdateAutomaticFlag(true)
    return true
end

-- Helper: spread
local function RandomizedDirection(forward, spreadDeg)
    local ang = forward:Angle()
    if spreadDeg and spreadDeg > 0 then
        ang:RotateAroundAxis(ang:Up(),   math.Rand(-spreadDeg, spreadDeg))
        ang:RotateAroundAxis(ang:Right(), math.Rand(-spreadDeg, spreadDeg))
    end
    return ang:Forward()
end

-- Always spawn a fresh ball so previous ones aren't "stolen"
function SWEP:SpawnNewBall(spawnPos, dir)
    local ball = ents.Create("sent_combine_ball")
    if not IsValid(ball) then return nil end
    ball:SetPos(spawnPos)
    ball:SetAngles(dir:Angle())
    ball:Spawn()
    ball:Activate()
    return ball
end

-- Robust motion kick that works for most SENTs/props/NPC-ish things
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

    -- Ensure collision is projectile-like so it doesn't instantly snag
    if ent.SetCollisionGroup then
        ent:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    end

    local function pushNow()
        if not IsValid(ent) then return end
        local mvtype = ent:GetMoveType()

        local phys = ent.GetPhysicsObject and ent:GetPhysicsObject() or nil
        if IsValid(phys) then
            phys:EnableMotion(true)
            phys:Wake()
            -- Use multiple methods to guarantee motion sticks
            local v = dir * speed
            phys:SetVelocityInstantaneous(v)
            phys:AddVelocity(v) -- in case SetVelocityInstantaneous gets eaten
            phys:ApplyForceCenter(v * (phys:GetMass() or 1))
        else
            -- Fallback for non-physics entities
            if ent.SetVelocity then ent:SetVelocity(dir * speed) end
            if ent.SetLocalVelocity then ent:SetLocalVelocity(dir * speed) end
            -- As a last resort, try to switch to physics if it's frozen
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

    -- Do it now and again next tick (some SENTs init physics a tick late)
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
        owner:ChatPrint("[CombineBall] Could not create 'sent_combine_ball'. Is it installed?")
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

-- Switch fire mode only once per reload press
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

-- Right-click: open menu (client + server net for reliability)
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

-- Client-side menu
if CLIENT then
    local function IsSentCombineBall(ent)
        if not IsValid(ent) then return false end
        local cls = ent:GetClass()
        local nm = ent.GetName and ent:GetName() or ""
        return (cls == "sent_combine_ball") or (nm == "sent_combine_ball")
    end

    local function ClassInheritsFrom(className, target)
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

    local function GatherClassesRelatingTo(target)
        local out = {}
        -- scripted_ents.GetList() may be keyed or array depending on version; handle both
        for key, val in pairs(scripted_ents.GetList()) do
            local cls, data
            if istable(val) and val.ClassName then
                cls = val.ClassName
                data = val.t or val
            elseif isstring(key) and istable(val) then
                cls = key
                data = val.t or val
            end
            if isstring(cls) and ClassInheritsFrom(cls, target) then
                table.insert(out, {
                    ClassName  = cls,
                    PrintName  = (data and data.PrintName) or cls,
                    Base       = (data and data.Base) or "unknown"
                })
            end
        end
        -- Ensure target itself shows up even if not in registry
        local already = false
        for _, v in ipairs(out) do if v.ClassName == target then already = true break end end
        if not already then
            table.insert(out, { ClassName = target, PrintName = target, Base = "unknown" })
        end
        table.sort(out, function(a,b) return a.ClassName < b.ClassName end)
        return out
    end

    function SWEP:OpenBallMenu()
        if IsValid(self._BallFrame) then
            self._BallFrame:Close()
        end

        local frame = vgui.Create("DFrame")
        frame:SetTitle("sent_combine_ball — Classes and Instances")
        frame:SetSize(720, 500)
        frame:Center()
        frame:MakePopup()
        self._BallFrame = frame

        local sheet = vgui.Create("DPropertySheet", frame)
        sheet:Dock(FILL)

        -- Instances tab (currently spawned entities)
        do
            local pnl = vgui.Create("DPanel", sheet)
            pnl:Dock(FILL)

            local list = vgui.Create("DListView", pnl)
            list:Dock(FILL)
            list:AddColumn("EntID"):SetFixedWidth(60)
            list:AddColumn("Class")
            list:AddColumn("Name")
            list:AddColumn("Distance")

            local refreshBtn = vgui.Create("DButton", pnl)
            refreshBtn:Dock(BOTTOM)
            refreshBtn:SetTall(28)
            refreshBtn:SetText("Refresh instances")

            local function RefreshInstances()
                list:Clear()
                local ply = LocalPlayer()
                local ppos = IsValid(ply) and ply:GetPos() or vector_origin
                for _, ent in ipairs(ents.GetAll()) do
                    if IsSentCombineBall(ent) then
                        local dist = math.sqrt(ppos:DistToSqr(ent:GetPos()))
                        local name = ent.GetName and ent:GetName() or ""
                        list:AddLine(ent:EntIndex(), ent:GetClass() or "?", (name ~= "" and name) or "(none)", math.Round(dist) .. "u")
                    end
                end
            end
            refreshBtn.DoClick = RefreshInstances
            RefreshInstances()

            sheet:AddSheet("Instances", pnl, "icon16/brick.png")
        end

        -- Classes tab (entities in general related to this class)
        do
            local pnl = vgui.Create("DPanel", sheet)
            pnl:Dock(FILL)

            local list = vgui.Create("DListView", pnl)
            list:Dock(FILL)
            list:AddColumn("Class")
            list:AddColumn("PrintName")
            list:AddColumn("Base")

            local classes = GatherClassesRelatingTo("sent_combine_ball")
            for _, info in ipairs(classes) do
                list:AddLine(info.ClassName, info.PrintName or info.ClassName, info.Base or "")
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
        else
            -- Fallback
            local fake = setmetatable({}, {__index = SWEP})
            SWEP.OpenBallMenu(fake)
        end
    end)
end