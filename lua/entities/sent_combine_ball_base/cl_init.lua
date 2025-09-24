include("shared.lua")
include("cball/core.lua")

ENT.RenderGroup = RENDERGROUP_BOTH

local ballsprite1 = Material("effects/ar2_altfire1b")
local ballsprite2 = Material("effects/ar2_altfire1")

killicon.AddFont("sent_combine_ball_base", "HL2MPTypeDeath", 8, Color(255, 80, 0, 255))
language.Add("sent_combine_ball_base", "Combine Ball")

function ENT:Initialize() end

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
    if not CombineBall then return end
    CombineBall.ClientRingsOnRemove(self)
end