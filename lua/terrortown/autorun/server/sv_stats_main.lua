if not SERVER then return end

local API = include("sv_stats_api_handler.lua")

API:loadConfig()

local function openWebsite(ply)
    if not IsValid(ply) or API.config.website == "" then return end
    ply:SendLua("gui.OpenURL(" .. string.format("%q", API.config.website) .. ")")
end

hook.Add("PlayerSay", "TTT2Stats.PlayerChat", function(ply, text)
    if string.lower(string.Trim(text)) == "!stats" then openWebsite(ply) end
end)

hook.Add("ShowSpare2", "TTT2Stats.OpenStats", openWebsite)

hook.Add("Initialize", "TTT2Stats.Initialize", function()
    API:startSession()
    API:queueRetry()
end)

hook.Add("TTTBeginRound", "TTT2Stats.BeginRound", function() API:startRound() end)

hook.Add("TTTEndRound", "TTT2Stats.EndRound", function(result) API:finishRound(result) end)

hook.Add("TTT2UpdateSubrole", "TTT2Stats.SubroleChanged", function(ply) API:recordRoleChange(ply) end)

hook.Add("TTT2UpdateTeam", "TTT2Stats.TeamChanged", function(ply) API:recordRoleChange(ply) end)

hook.Add("PlayerDeath", "TTT2Stats.PlayerDeath",
    function(victim, inflictor, attacker) API:recordDeath(victim, inflictor, attacker) end)

hook.Add("PostEntityTakeDamage", "TTT2Stats.Damage", function(target, damageInfo, wasDamageTaken)
    if not wasDamageTaken or not IsValid(target) or not target:IsPlayer() then return end

    local inflictor = damageInfo:GetInflictor()
    API:recordDamage(target, damageInfo:GetAttacker(), damageInfo:GetDamage(), inflictor)
end)

hook.Add("EntityFireBullets", "TTT2Stats.BulletFired", function(entity, bulletData)
    local attacker = IsValid(bulletData.Attacker) and bulletData.Attacker or entity
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    local weaponName = API:resolveWeaponName(attacker, bulletData.Inflictor)
    local originalCallback = bulletData.Callback
    local recordedHit = false

    API:recordShot(attacker, weaponName)

    bulletData.Callback = function(callbackAttacker, traceResult, damageInfo)
        local hitEntity = traceResult and traceResult.Entity or nil
        if not recordedHit and IsValid(hitEntity) and hitEntity:IsPlayer() then
            API:recordShotHit(attacker, weaponName)
            recordedHit = true
        end

        if originalCallback then return originalCallback(callbackAttacker, traceResult, damageInfo) end
    end

    return true
end)

hook.Add("PlayerDisconnected", "TTT2Stats.PlayerDisconnected", function(ply)
    API:recordDisconnect(ply)
end)

hook.Add("PlayerSpawn", "TTT2Stats.PlayerRevived", function(ply)
    API:recordRevival(ply)
end)
