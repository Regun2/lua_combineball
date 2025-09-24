AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("cball/core.lua")
include("shared.lua")
include("cball/core.lua")

CreateConVar("combineball_lifetime", "5", FCVAR_ARCHIVE)
CreateConVar("combineball_scale", "1", FCVAR_ARCHIVE)
CreateConVar("combineball_trail", "1", FCVAR_ARCHIVE)

ENT.Scale = 1
ENT.BallLife = 0
ENT.BounceT = 0

-- IMPORTANT: use ClassName so custom subclasses spawn themselves
function ENT:SpawnFunction(ply, tr, ClassName)
    if not tr.Hit then return end
    ClassName = ClassName or self.ClassName or "sent_combine_ball_base"

    local spawnPos = tr.HitPos + tr.HitNormal * 32
    local ent = ents.Create(ClassName)
    if not IsValid(ent) then return end

    ent:SetPos(spawnPos)
    ent:Spawn()
    ent:Activate()
    ent:SetOwner(ply)
    return ent
end

function ENT:Initialize()
    CombineBall.Init(self)
end

function ENT:Think()
    CombineBall.Think(self)
    self:NextThink(CurTime())
    return true
end

function ENT:PhysicsCollide(data, phys)
    CombineBall.PhysicsCollide(self, data, phys)
end

function ENT:OnRemove()
    CombineBall.OnRemove(self)
end
