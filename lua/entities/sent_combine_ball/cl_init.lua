include("shared.lua")

ENT.RenderGroup = RENDERGROUP_BOTH

local ballsprite1 = Material("effects/ar2_altfire1b")
local ballsprite2 = Material("effects/ar2_altfire1")

killicon.AddFont("sent_combine_ball", "HL2MPTypeDeath", 8, Color(255, 80, 0, 255))
language.Add("sent_combine_ball", "Combine ball")

-- Ring parameters (exact match to your requested call; second ring is double speed)
local RING = {
    startRadius = 0.3,
    endRadius   = 0,
    speed       = 380,                 -- base speed; the second ring uses double
    life        = 32,
    thickness   = 1,
    color       = Color(255, 255, 255)
}

function ENT:Initialize()
end

function ENT:Draw()
    local scale = self:GetNWFloat("scale", 1)
    local pos = self:GetPos()
    local size = 24 * scale

    render.SetMaterial(ballsprite1)
    render.DrawSprite(pos, size, size, Color(255, 255, 255, 255))

    render.SetMaterial(ballsprite2)
    render.DrawSprite(pos, size, size, Color(255, 255, 255, 255))

    if self:GetVelocity():Length() > 500 then
        for i = 1, 5 do
            render.DrawSprite(self:GetPos() + self:GetVelocity() * (i * -0.005), size / 1.5, size / 1.5, Color(255, 255, 255, 70))
        end
    end
end

-- Spawn two BeamRingPoint rings on removal; second ring has double speed
function ENT:OnRemove()
    local pos = self:GetPos()

    effects.BeamRingPoint(
        pos,
        RING.startRadius,
        RING.endRadius,
        RING.speed,
        RING.life,
        RING.thickness,
        RING.color
    )

    effects.BeamRingPoint(
        pos,
        RING.startRadius,
        RING.endRadius,
        RING.speed * 2,
        RING.life,
        RING.thickness,
        RING.color
    )
end