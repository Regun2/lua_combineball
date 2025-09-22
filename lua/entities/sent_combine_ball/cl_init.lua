include("shared.lua")

ENT.RenderGroup = RENDERGROUP_BOTH

local ballsprite1 = Material("effects/ar2_altfire1b")
local ballsprite2 = Material("effects/ar2_altfire1")

killicon.AddFont("sent_combine_ball", "HL2MPTypeDeath", 8, Color(255, 80, 0, 255))
language.Add("sent_combine_ball", "Combine ball")

function ENT:GetRingStartRadius() return 0.3 end
function ENT:GetRingEndRadius() return 0 end
function ENT:GetRingBaseSpeed() return 380 end
function ENT:GetRingLife() return 32 end
function ENT:GetRingThickness() return 1 end
function ENT:GetRingColors() return Color(255,255,255,128), Color(255,255,255,64) end

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

function ENT:OnRemove()
    local pos = self:GetPos()
    local s = self:GetRingBaseSpeed()
    local c1, c2 = self:GetRingColors()
    effects.BeamRingPoint(pos, self:GetRingStartRadius(), self:GetRingEndRadius(), s * 1.25, self:GetRingLife(), self:GetRingThickness(), c1)
    effects.BeamRingPoint(pos, self:GetRingStartRadius(), self:GetRingEndRadius(), s * 2, self:GetRingLife(), self:GetRingThickness(), c2)
end