ENT.Type = "anim"
ENT.Base = "sent_combine_ball_base"
ENT.PrintName = "Combine Ball (Custom Example)"
ENT.Author = "You"
ENT.Information = "Editable Combine Ball Variant"
ENT.Category = "Comball"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Ring = {
    startRadius = 0.3,
    endRadius = 0,
    baseSpeed = 520,
    life = 32,
    thickness = 1.25,
    color = Color(0, 200, 255),
    alphaHalf = 160,
    alphaQuarter = 64
}

ENT.BounceFX = {
    maxBounces = 6,
    cooldown = 0.75,
    ar2 = { magnitude = 2.5, scale = 2.5, radius = 1.2 },
    impactSound = "NPC_CombineBall.Impact",
    screenShake = { amplitude = 25, frequency = 160, duration = 0.35, radius = 220 },
    postVelocity = { mode = "target", value = 2000 }
}

ENT.DamageFX = {
    direct = 35,
    splash = 15,
    radius = 140,
    cooldown = 0.35,
    damageType = DMG_DISSOLVE
}

ENT.ExplosionFX = {
    effectName = "cball_explode",
    effectScale = 26,
    sound = "NPC_CombineBall.Explosion",
    screenShake = { amplitude = 22, frequency = 150, duration = 1, radius = 1300 }
}