ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Combine Ball"
ENT.Author = "regunkyle (original by Jvs)"
ENT.Information = "A lua programmed Combine Ball"
ENT.Category = "Jvs"
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:IsOwner(ply)
    local o = self:GetOwner()
    return IsValid(o) and o == ply
end

function ENT:ShouldHurtEntity(ent)
    return ent:IsPlayer() and not self:IsOwner(ent)
end