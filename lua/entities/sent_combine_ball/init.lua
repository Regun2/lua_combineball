AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- Keep original gameplay convars (no new convars added).
CreateConVar("combineball_lifetime", "5", FCVAR_ARCHIVE)
CreateConVar("combineball_scale", "1", FCVAR_ARCHIVE)
CreateConVar("combineball_trail", "1", FCVAR_ARCHIVE)

-- Bounce/explosion tweakables (edit in code).
-- Bounce effect now uses AR2Impact; tweak magnitude/scale/radius here.
local FX = {
    Bounce = {
        maxBounces = 5,    -- how many bounces before removal
        cooldown   = 1,    -- seconds before another bounce decrements count

        ar2 = {
            magnitude = 10,  -- visual intensity
            scale     = 10,  -- overall effect size
            radius    = 10   -- additional size parameter used by the effect
        },

        impactSound = "NPC_CombineBall.Impact",
        screenShake = { amplitude = 20, frequency = 150, duration = 0.35, radius = 200 },

        -- Post-bounce velocity behavior:
        -- mode = "target" sets absolute speed; mode = "mult" scales current speed.
        postVelocity = { mode = "target", value = 1782 * 0.9 }
        -- Example: postVelocity = { mode = "mult", value = 1.0 }
    },

    Explosion = {
        effectName  = "cball_explode",
        effectScale = 24.3,
        sound       = "NPC_CombineBall.Explosion",
        screenShake = { amplitude = 20, frequency = 150, duration = 1, radius = 1250 }
    }
}

ENT.Scale    = 1
ENT.BallLife = 0
ENT.BounceT  = 0

function ENT:SpawnFunction(ply, tr)
    if not tr.Hit then return end
    local SpawnPos = tr.HitPos + tr.HitNormal * 32
    local ent = ents.Create("sent_combine_ball")
    if not IsValid(ent) then return end
    ent:SetPos(SpawnPos)
    ent:Spawn()
    ent:Activate()
    ent:SetOwner(ply)
    return ent
end

function ENT:Initialize()
    self.BounceFX = table.Copy(FX.Bounce)

    self.Scale = math.Clamp(tonumber(GetConVar("combineball_scale"):GetFloat() or 1), 0.1, 10)
    self:SetModel("models/roller.mdl")
    self:PhysicsInitSphere(10 * self.Scale, "metal_bouncy")

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:EnableGravity(false)
        phys:AddGameFlag(FVPHYSICS_DMG_DISSOLVE)
        phys:SetMass(250)
    end

    self.HoldSound = false
    self.BallLife = CurTime() + math.Clamp(tonumber(GetConVar("combineball_lifetime"):GetFloat() or 5), 1, 600)
    self.NextFlyBy = CurTime() + 2

    self:SetCollisionBounds(
        Vector(-10 * self.Scale, -10 * self.Scale, -10 * self.Scale),
        Vector(10 * self.Scale,  10 * self.Scale,  10 * self.Scale)
    )

    if GetConVar("combineball_trail"):GetBool() then
        util.SpriteTrail(self, 0, Color(215, 244, 23, 244), true, 25.0, 0, 0.1, 1, "sprites/combineball_trail_black_1.vmt")
    end

    self:SetNWFloat("scale", self.Scale)

    self.Maxbounce = self.BounceFX.maxBounces
    self.BounceT   = 0
end

function ENT:Think()
    if self.BallLife <= CurTime() then
        self:Remove()
        return
    end

    local entz = ents.FindInSphere(self:GetPos(), 100)
    for _, ent in pairs(entz) do
        if ent:IsPlayer() and self.NextFlyBy <= CurTime() and not self.HoldSound then
            self:EmitSound("NPC_CombineBall.WhizFlyby")
            self.NextFlyBy = CurTime() + 2
        end
    end

    if self:IsPlayerHolding() then
        if not self.HoldSound then
            self:EmitSound("NPC_CombineBall.HoldingInPhysCannon")
            self.HoldSound = true
            self:SetNWBool("pickedup", true)
            self.BallLife = CurTime() + math.Clamp(tonumber(GetConVar("combineball_lifetime"):GetFloat() or 5), 1, 600)
        end

        self.Maxbounce = self.BounceFX.maxBounces
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    else
        if self.HoldSound then
            self.BallLife = CurTime() + math.Clamp(tonumber(GetConVar("combineball_lifetime"):GetFloat() or 5), 1, 600)
            self.Maxbounce = self.BounceFX.maxBounces
            self:SetNWBool("pickedup", false)
            self:StopSound("NPC_CombineBall.HoldingInPhysCannon")
            self:SetCollisionGroup(COLLISION_GROUP_NONE)
            self.HoldSound = false
        end

        self:SetNWFloat("scale", self.Scale)
    end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableGravity(false)
    end

    self:NextThink(CurTime())
    return true
end

function ENT:PhysicsCollide(data, phys)
    -- Strider core special-case
    if IsValid(data.HitEntity) and data.HitEntity:GetClass() == "phys_bone_follower" then
        local entz = ents.FindInSphere(self:GetPos(), 200)
        for _, ent in pairs(entz) do
            if IsValid(ent) and ent:GetClass() == "npc_strider" then
                util.BlastDamage(self:GetOwner() or self, self:GetOwner() or self, ent:GetPos(), 5, 125)
                self:Remove()
                return
            end
        end
    end

    if self.Maxbounce <= 0 then
        self:Remove()
        return
    end

    if self.HoldSound or not data.HitPos then return end

    local cfg = self.BounceFX

    -- AR2Impact bounce effect
    do
        local ed = EffectData()
        ed:SetOrigin(data.HitPos)
        ed:SetNormal((data.HitNormal or -data.OurOldVelocity:GetNormalized()):GetNormalized())
        ed:SetMagnitude((cfg.ar2 and cfg.ar2.magnitude) or 1)
        ed:SetScale((cfg.ar2 and cfg.ar2.scale) or 1)
        ed:SetRadius((cfg.ar2 and cfg.ar2.radius) or 1)
        util.Effect("AR2Impact", ed)
    end

    -- Impact sound
    if cfg.impactSound then
        self:EmitSound(cfg.impactSound)
    end

    -- Decrement bounces with cooldown
    local now = CurTime()
    if (self.BounceT or 0) <= now then
        self.Maxbounce = self.Maxbounce - 1
        self.BounceT = now + (cfg.cooldown or 0)
    end

    -- Screen shake
    local ss = cfg.screenShake
    if ss then
        util.ScreenShake(data.HitPos, ss.amplitude or 20, ss.frequency or 150, ss.duration or 1, ss.radius or 200)
    end

    -- Post-bounce velocity behavior
    if IsValid(phys) then
        local v = phys:GetVelocity()
        local dir
        if v:LengthSqr() < 1e-6 then
            dir = (data.HitNormal or VectorRand())
        else
            dir = v:GetNormalized()
        end

        local pv = cfg.postVelocity or {}
        local speed
        if pv.mode == "mult" then
            speed = v:Length() * (pv.value or 1)
        else
            speed = pv.value or 1600
        end

        phys:SetVelocity(dir * speed)
    end
end

function ENT:OnRemove()
    local pos = self:GetPos()

    -- Explosion effect/sound/shake (server-side)
    local exp = FX.Explosion
    if exp and exp.effectName then
        local effect = EffectData()
        effect:SetStart(pos)
        effect:SetOrigin(pos)
        effect:SetScale(exp.effectScale or 24.3)
        util.Effect(exp.effectName, effect)
    end

    if exp and exp.screenShake then
        local ss = exp.screenShake
        util.ScreenShake(pos, ss.amplitude or 20, ss.frequency or 150, ss.duration or 1, ss.radius or 1250)
    end

    if exp and exp.sound then
        self:EmitSound(exp.sound)
    end

    self:StopSound("NPC_CombineBall.HoldingInPhysCannon")
end