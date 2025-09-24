CombineBall = CombineBall or {}

CombineBall.Defaults = {
    Ring = {
        startRadius = 0.3,
        endRadius = 0,
        baseSpeed = 380,
        life = 32,
        thickness = 1,
        color = Color(255,255,255),
        alphaHalf = 128,
        alphaQuarter = 64
    },
    Bounce = {
        maxBounces = 5,
        cooldown = 1,
        ar2 = { magnitude = 2, scale = 2, radius = 1 },
        impactSound = "NPC_CombineBall.Impact",
        screenShake = { amplitude = 20, frequency = 150, duration = 0.35, radius = 200 },
        postVelocity = { mode = "target", value = 1782 * 0.9 }
    },
    Damage = {
        direct = 30,
        splash = 12,
        radius = 120,
        cooldown = 0.35,
        damageType = DMG_DISSOLVE
    },
    Explosion = {
        effectName = "cball_explode",
        effectScale = 24.3,
        sound = "NPC_CombineBall.Explosion",
        screenShake = { amplitude = 20, frequency = 150, duration = 1, radius = 1250 }
    }
}

function CombineBall.GetRingParams(ent)
    local r = ent.Ring or CombineBall.Defaults.Ring
    return {
        startRadius = r.startRadius or 0.3,
        endRadius = r.endRadius or 0,
        baseSpeed = r.baseSpeed or 380,
        life = r.life or 32,
        thickness = r.thickness or 1,
        color = r.color or Color(255,255,255),
        alphaHalf = r.alphaHalf or 128,
        alphaQuarter = r.alphaQuarter or 64
    }
end

function CombineBall.ShouldHurtEntity(ent, target)
    if not IsValid(target) or not target:IsPlayer() then return false end
    local o = ent:GetOwner()
    return not (IsValid(o) and target == o)
end

function CombineBall.DealPlayerDamage(ent, ply, dmg, hitpos)
    if not IsValid(ply) or not CombineBall.ShouldHurtEntity(ent, ply) then return end
    ent.DmgCD = ent.DmgCD or {}
    local now = CurTime()
    local cd = (ent.DamageFX and ent.DamageFX.cooldown) or CombineBall.Defaults.Damage.cooldown
    if ent.DmgCD[ply] and ent.DmgCD[ply] > now then return end
    ent.DmgCD[ply] = now + cd
    local di = DamageInfo()
    di:SetDamage(dmg)
    di:SetAttacker(IsValid(ent:GetOwner()) and ent:GetOwner() or ent)
    di:SetInflictor(ent)
    di:SetDamageType((ent.DamageFX and ent.DamageFX.damageType) or CombineBall.Defaults.Damage.damageType)
    di:SetDamagePosition(hitpos or ent:GetPos())
    ply:TakeDamageInfo(di)
end

function CombineBall.DoSplashDamage(ent, center)
    local fx = ent.DamageFX or CombineBall.Defaults.Damage
    local nearby = ents.FindInSphere(center, fx.radius or 120)
    for _, v in ipairs(nearby) do
        if CombineBall.ShouldHurtEntity(ent, v) then
            CombineBall.DealPlayerDamage(ent, v, fx.splash or 10, center)
        end
    end
end

function CombineBall.Init(ent)
    ent.BounceFX = ent.BounceFX or table.Copy(CombineBall.Defaults.Bounce)
    ent.DamageFX = ent.DamageFX or table.Copy(CombineBall.Defaults.Damage)
    ent.ExplosionFX = ent.ExplosionFX or table.Copy(CombineBall.Defaults.Explosion)
    ent.DmgCD = ent.DmgCD or {}
    ent.Scale = math.Clamp(tonumber(GetConVar("combineball_scale"):GetFloat() or 1), 0.1, 10)
    ent:SetModel("models/roller.mdl")
    ent:PhysicsInitSphere(10 * ent.Scale, "metal_bouncy")
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:EnableGravity(false)
        phys:AddGameFlag(FVPHYSICS_DMG_DISSOLVE)
        phys:SetMass(250)
    end
    ent.HoldSound = false
    ent.BallLife = CurTime() + math.Clamp(tonumber(GetConVar("combineball_lifetime"):GetFloat() or 5), 1, 600)
    ent.NextFlyBy = CurTime() + 2
    ent:SetCollisionBounds(Vector(-10 * ent.Scale, -10 * ent.Scale, -10 * ent.Scale), Vector(10 * ent.Scale, 10 * ent.Scale, 10 * ent.Scale))
    if GetConVar("combineball_trail"):GetBool() then
        util.SpriteTrail(ent, 0, Color(215, 244, 23, 244), true, 25.0, 0, 0.1, 1, "sprites/combineball_trail_black_1.vmt")
    end
    ent:SetNWFloat("scale", ent.Scale)
    ent.Maxbounce = ent.BounceFX.maxBounces or 5
    ent.BounceT = 0
end

function CombineBall.Think(ent)
    if ent.BallLife <= CurTime() then
        ent:Remove()
        return
    end
    local entz = ents.FindInSphere(ent:GetPos(), 100)
    for _, v in pairs(entz) do
        if v:IsPlayer() and ent.NextFlyBy <= CurTime() and not ent.HoldSound then
            ent:EmitSound("NPC_CombineBall.WhizFlyby")
            ent.NextFlyBy = CurTime() + 2
        end
    end
    if ent:IsPlayerHolding() then
        if not ent.HoldSound then
            ent:EmitSound("NPC_CombineBall.HoldingInPhysCannon")
            ent.HoldSound = true
            ent:SetNWBool("pickedup", true)
            ent.BallLife = CurTime() + math.Clamp(tonumber(GetConVar("combineball_lifetime"):GetFloat() or 5), 1, 600)
        end
        ent.Maxbounce = ent.BounceFX.maxBounces or 5
        ent:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    else
        if ent.HoldSound then
            ent.BallLife = CurTime() + math.Clamp(tonumber(GetConVar("combineball_lifetime"):GetFloat() or 5), 1, 600)
            ent.Maxbounce = ent.BounceFX.maxBounces or 5
            ent:SetNWBool("pickedup", false)
            ent:StopSound("NPC_CombineBall.HoldingInPhysCannon")
            ent:SetCollisionGroup(COLLISION_GROUP_NONE)
            ent.HoldSound = false
        end
        ent:SetNWFloat("scale", ent.Scale)
    end
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableGravity(false) end
    ent:NextThink(CurTime())
end

function CombineBall.PhysicsCollide(ent, data, phys)
    if IsValid(data.HitEntity) and data.HitEntity:GetClass() == "phys_bone_follower" then
        local entz = ents.FindInSphere(ent:GetPos(), 200)
        for _, v in pairs(entz) do
            if IsValid(v) and v:GetClass() == "npc_strider" then
                util.BlastDamage(ent:GetOwner() or ent, ent:GetOwner() or ent, v:GetPos(), 5, 125)
                ent:Remove()
                return
            end
        end
    end
    if ent.Maxbounce <= 0 then ent:Remove() return end
    if ent.HoldSound or not data.HitPos then return end
    local cfg = ent.BounceFX or CombineBall.Defaults.Bounce
    local ed = EffectData()
    ed:SetOrigin(data.HitPos)
    ed:SetNormal((data.HitNormal or -data.OurOldVelocity:GetNormalized()):GetNormalized())
    ed:SetMagnitude((cfg.ar2 and cfg.ar2.magnitude) or 1)
    ed:SetScale((cfg.ar2 and cfg.ar2.scale) or 1)
    ed:SetRadius((cfg.ar2 and cfg.ar2.radius) or 1)
    util.Effect("AR2Impact", ed)
    if cfg.impactSound then ent:EmitSound(cfg.impactSound) end
    local now = CurTime()
    if (ent.BounceT or 0) <= now then
        ent.Maxbounce = ent.Maxbounce - 1
        ent.BounceT = now + (cfg.cooldown or 0)
    end
    local ss = cfg.screenShake
    if ss then util.ScreenShake(data.HitPos, ss.amplitude or 20, ss.frequency or 150, ss.duration or 1, ss.radius or 200) end
    if IsValid(data.HitEntity) and data.HitEntity:IsPlayer() then
        CombineBall.DealPlayerDamage(ent, data.HitEntity, (ent.DamageFX and ent.DamageFX.direct) or CombineBall.Defaults.Damage.direct or 25, data.HitPos)
    end
    CombineBall.DoSplashDamage(ent, data.HitPos)
    if IsValid(phys) then
        local v = phys:GetVelocity()
        local dir = v:LengthSqr() < 1e-6 and (data.HitNormal or VectorRand()) or v:GetNormalized()
        local pv = cfg.postVelocity or {}
        local speed = (pv.mode == "mult") and (v:Length() * (pv.value or 1)) or (pv.value or 1600)
        phys:SetVelocity(dir * speed)
    end
end

function CombineBall.OnRemove(ent)
    local pos = ent:GetPos()
    local exp = ent.ExplosionFX or CombineBall.Defaults.Explosion
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
    if exp and exp.sound then ent:EmitSound(exp.sound) end
    ent:StopSound("NPC_CombineBall.HoldingInPhysCannon")
end

function CombineBall.ClientRingsOnRemove(ent)
    local p = CombineBall.GetRingParams(ent)
    local pos = ent:GetPos()
    local c = p.color
    local c1 = Color(c.r, c.g, c.b, p.alphaHalf or 128)
    local c2 = Color(c.r, c.g, c.b, p.alphaQuarter or 64)
    effects.BeamRingPoint(pos, p.startRadius, p.endRadius, p.baseSpeed * 1.25, p.life, p.thickness, c1)
    effects.BeamRingPoint(pos, p.startRadius, p.endRadius, p.baseSpeed * 2, p.life, p.thickness, c2)
end