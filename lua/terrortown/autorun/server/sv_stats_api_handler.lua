local Utils = include("terrortown/autorun/shared/sh_stats_utils.lua")
local Json = include("terrortown/autorun/shared/sh_stats_json.lua")

local API = {
    config = { website = "", token = "" },
    sessionKey = nil,
    sessionReady = false,
    roundStats = nil,
    roundDeliveries = {},
}

local queuePath = "ttt2_stats/queue"

local function getWeaponStats(playerStats, weaponName)
    local name = weaponName or "unknown"
    playerStats.weapons[name] = playerStats.weapons[name] or {
        weaponName = name, shotsFired = 0, shotsHit = 0, damageDealt = 0,
    }
    return playerStats.weapons[name]
end

local function refreshPlayerRole(playerStats, ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    playerStats.finalTeamName = Utils.getTeamName(ply:GetTeam())
    playerStats.finalSubroleName = Utils.getSubroleName(ply)
end

local function stopAliveTimer(playerStats, now)
    if not playerStats._isAlive or not playerStats._aliveSinceUnix then return end

    playerStats._survivalSeconds = playerStats._survivalSeconds
        + math.max(0, now - playerStats._aliveSinceUnix)
    playerStats._aliveSinceUnix = nil
end

local function playerSnapshot(ply)
    return {
        steamId = ply:SteamID64(),
        teamName = Utils.getTeamName(ply:GetTeam()),
        subroleName = Utils.getSubroleName(ply),
    }
end

local function ensureQueue()
    if not file.IsDir("ttt2_stats", "DATA") then file.CreateDir("ttt2_stats") end
    if not file.IsDir(queuePath, "DATA") then file.CreateDir(queuePath) end
end

local function cleanWebsite(website)
    if type(website) ~= "string" then return "" end
    return string.Trim(website):gsub("/+$", "")
end

function API.log(message)
    print("[TTT2 Stats] " .. tostring(message))
end

function API:loadConfig()
    ensureQueue()
    local path = "ttt2_stats/config.json"
    local defaults = { website = "", token = "" }
    if not file.Exists(path, "DATA") then
        file.Write(path, Json.encode(defaults))
        self.config = defaults
        return
    end

    local ok, decoded = pcall(Json.decode, file.Read(path, "DATA") or "")
    if not ok or type(decoded) ~= "table" then decoded = {} end

    self.config = { website = cleanWebsite(decoded.website), token = tostring(decoded.token or "") }
    file.Write(path, Json.encode(self.config))
end

function API:isConfigured()
    if self.config.website == "" then
        self:log("No website configured")
        return false
    end

    if self.config.token == "" then
        self:log("No token configured")
        return false
    end

    return true
end

function API:request(path, body, onSuccess, onFailure)
    if not self:isConfigured() then return false end

    HTTP({
        url = self.config.website .. path,
        method = "PUT",
        headers = {
            ["Authorization"] = "Bearer " .. self.config.token,
            ["Content-Type"] = "application/json",
        },
        body = Json.encode(body),
        success = function(code)
            if code >= 200 and code < 300 then
                if onSuccess then onSuccess() end
            elseif onFailure then
                onFailure("API returned HTTP " .. tostring(code))
            end
        end,
        failed = function(reason)
            if onFailure then onFailure(tostring(reason)) end
        end,
    })

    return true
end

function API:saveQueuedRound(payload)
    ensureQueue()
    local key = string.gsub(payload.roundKey, "[^%w%-]", "_")
    local path = queuePath .. "/" .. key .. ".json"
    file.Write(path, Json.encode(payload))

    return path
end

function API:sendSession()
    if not self.sessionKey then return end

    self:request("/api/ingest/v1/sessions", {
        protocolVersion = 1,
        sessionKey = self.sessionKey,
        mapName = game.GetMap(),
        startedAt = self.sessionStartedAt,
    }, function()
        self.sessionReady = true
        self:log("Session registered")
        self:flushQueue()
    end, function(reason)
        self.sessionReady = false
        self:log("Session registration failed: " .. reason)
    end)
end

function API:startSession()
    self.sessionStartedAt = Utils.getIsoDate()
    self.sessionKey = game.GetMap() .. "-" .. tostring(os.time())
    self.sessionReady = false
    self:sendSession()
end

function API:sendRound(payload)
    local queuedFile = self:saveQueuedRound(payload)
    if not self.sessionReady or self.roundDeliveries[queuedFile] then return end

    self.roundDeliveries[queuedFile] = true
    local requestStarted = self:request("/api/ingest/v1/rounds", payload, function()
        self.roundDeliveries[queuedFile] = nil
        if file.Exists(queuedFile, "DATA") then file.Delete(queuedFile) end
        self:log("Round " .. payload.roundKey .. " recorded")
    end, function(reason)
        self.roundDeliveries[queuedFile] = nil
        self:log("Round delivery failed: " .. reason)
    end)
    if not requestStarted then self.roundDeliveries[queuedFile] = nil end
end

function API:flushQueue()
    if not self.sessionReady then return end

    ensureQueue()

    local files = file.Find(queuePath .. "/*.json", "DATA")
    for _, filename in ipairs(files) do
        local path = queuePath .. "/" .. filename
        local ok, payload = pcall(Json.decode, file.Read(path, "DATA") or "")
        if ok and type(payload) == "table" then self:sendRound(payload) else file.Delete(path) end
    end
end

function API:queueRetry()
    timer.Create("TTT2Stats.Retry", 30, 0, function()
        if not self.sessionReady then self:sendSession() end
        self:flushQueue()
    end)
end

function API:startRound()
    local now = os.time()
    self.roundStats = {
        startedAt = Utils.getIsoDate(),
        startedUnix = now,
        players = {},
        events = {},
        _nextEventSequence = 1,
    }
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsPlayer() and not ply:IsSpec() and not ply:IsBot() then
            local steamId = ply:SteamID64()
            local teamName = Utils.getTeamName(ply:GetTeam())
            local subroleName = Utils.getSubroleName(ply)
            self.roundStats.players[steamId] = {
                steamId = steamId,
                initialTeamName = teamName,
                initialSubroleName = subroleName,
                finalTeamName = teamName,
                finalSubroleName = subroleName,
                joinedAt = Utils.getIsoDate(),
                leftAt = nil,
                damageDealt = 0,
                damageTaken = 0,
                shotsFired = 0,
                shotsHit = 0,
                survivalSeconds = nil,
                weapons = {},
                _isAlive = true,
                _aliveSinceUnix = now,
                _survivalSeconds = 0,
            }
        end
    end
end

function API:getPlayer(steamId)
    return self.roundStats and self.roundStats.players[steamId] or nil
end

function API:recordEvent(event)
    if not self.roundStats then return end

    event.sequence = self.roundStats._nextEventSequence
    event.occurredAt = Utils.getIsoDate()
    self.roundStats._nextEventSequence = self.roundStats._nextEventSequence + 1
    table.insert(self.roundStats.events, event)
end

function API:recordRoleChange(ply)
    if not self.roundStats or not IsValid(ply) or not ply:IsPlayer() then return end

    local stats = self:getPlayer(ply:SteamID64())
    if not stats then return end

    local newTeamName = Utils.getTeamName(ply:GetTeam())
    local newSubroleName = Utils.getSubroleName(ply)
    if stats.finalTeamName == newTeamName and stats.finalSubroleName == newSubroleName then return end

    self:recordEvent({
        type = "roleChange",
        steamId = ply:SteamID64(),
        fromTeamName = stats.finalTeamName,
        fromSubroleName = stats.finalSubroleName,
        toTeamName = newTeamName,
        toSubroleName = newSubroleName,
    })
    stats.finalTeamName = newTeamName
    stats.finalSubroleName = newSubroleName
end

function API:recordRevival(ply)
    if not self.roundStats or not IsValid(ply) or not ply:IsPlayer() then return end

    local stats = self:getPlayer(ply:SteamID64())
    if not stats or stats._isAlive then return end

    stats._isAlive = true
    stats._aliveSinceUnix = os.time()
    self:recordEvent({
        type = "revival",
        steamId = ply:SteamID64(),
        teamName = Utils.getTeamName(ply:GetTeam()),
        subroleName = Utils.getSubroleName(ply),
    })
end

function API:recordDisconnect(ply)
    if not self.roundStats or not IsValid(ply) or not ply:IsPlayer() then return end

    local stats = self:getPlayer(ply:SteamID64())
    if not stats then return end

    refreshPlayerRole(stats, ply)
    stats.leftAt = Utils.getIsoDate()
    stopAliveTimer(stats, os.time())
    stats._isAlive = false
end

function API:resolveWeaponName(ply, weapon)
    if type(weapon) == "string" and weapon ~= "" then return weapon end

    if IsValid(weapon) and weapon.GetClass and (not weapon.IsPlayer or not weapon:IsPlayer()) then
        return weapon:GetClass()
    end

    if IsValid(ply) and ply.GetActiveWeapon then
        local activeWeapon = ply:GetActiveWeapon()
        if IsValid(activeWeapon) and activeWeapon.GetClass then return activeWeapon:GetClass() end
    end

    return "unknown"
end

function API:recordDamage(victim, attacker, amount, weapon)
    if not self.roundStats or not IsValid(victim) or not victim:IsPlayer() then return end

    local victimStats = self:getPlayer(victim:SteamID64())
    if not victimStats then return end

    local damage = math.max(0, tonumber(amount) or 0)
    victimStats.damageTaken = victimStats.damageTaken + damage

    if not IsValid(attacker) or not attacker:IsPlayer() then return end

    local attackerStats = self:getPlayer(attacker:SteamID64())
    if not attackerStats then return end

    attackerStats.damageDealt = attackerStats.damageDealt + damage
    local weaponStats = getWeaponStats(attackerStats, self:resolveWeaponName(attacker, weapon))
    weaponStats.damageDealt = weaponStats.damageDealt + damage
end

function API:recordShot(ply, weaponName)
    if not self.roundStats or not IsValid(ply) or not ply:IsPlayer() then return end

    local stats = self:getPlayer(ply:SteamID64())
    if not stats then return end

    stats.shotsFired = stats.shotsFired + 1
    local weaponStats = getWeaponStats(stats, self:resolveWeaponName(ply, weaponName))
    weaponStats.shotsFired = weaponStats.shotsFired + 1
end

function API:recordShotHit(ply, weaponName)
    if not self.roundStats or not IsValid(ply) or not ply:IsPlayer() then return end

    local stats = self:getPlayer(ply:SteamID64())
    if not stats then return end

    local weaponStats = getWeaponStats(stats, self:resolveWeaponName(ply, weaponName))
    if weaponStats.shotsHit >= weaponStats.shotsFired then return end

    stats.shotsHit = stats.shotsHit + 1
    weaponStats.shotsHit = weaponStats.shotsHit + 1
end

function API:recordDeath(victim, inflictor, attacker)
    if not self.roundStats or not IsValid(victim) or not victim:IsPlayer() then return end

    local victimStats = self:getPlayer(victim:SteamID64())
    if not victimStats or not victimStats._isAlive then return end

    local now = os.time()
    local weaponName = self:resolveWeaponName(attacker, inflictor)
    stopAliveTimer(victimStats, now)
    victimStats._isAlive = false

    local attackerSnapshot, attackerStats
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
        attackerStats = self:getPlayer(attacker:SteamID64())
        if attackerStats then
            attackerSnapshot = playerSnapshot(attacker)
        end
    end

    self:recordEvent({
        type = "death",
        victim = playerSnapshot(victim),
        attacker = attackerSnapshot,
        inflictor = weaponName,
        hitgroup = victim:LastHitGroup(),
    })
end

function API:finishRound(winnerTeam)
    if not self.roundStats then return end

    local endedUnix = os.time()
    local payload = {
        protocolVersion = 1,
        sessionKey = self.sessionKey,
        sessionStartedAt = self.sessionStartedAt,
        roundKey = self.sessionKey .. "-round-" .. tostring(self.roundStats.startedUnix),
        mapName = game.GetMap(),
        startedAt = self.roundStats.startedAt,
        endedAt = Utils.getIsoDate(),
        winningTeam = Utils.getTeamName(winnerTeam),
        winningSubrole = nil,
        players = {},
        events = Utils.copySerializable(self.roundStats.events),
    }

    local currentPlayers = {}
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsPlayer() then currentPlayers[ply:SteamID64()] = ply end
    end

    for steamId, stats in pairs(self.roundStats.players) do
        local currentPlayer = currentPlayers[steamId]
        if currentPlayer then refreshPlayerRole(stats, currentPlayer) end

        stopAliveTimer(stats, endedUnix)
        stats.survivalSeconds = stats._survivalSeconds

        local playerPayload = Utils.copySerializable(stats)
        playerPayload.weapons = {}
        for _, weaponStats in pairs(stats.weapons) do
            table.insert(playerPayload.weapons,
                Utils.copySerializable(weaponStats))
        end
        table.insert(payload.players, playerPayload)
    end

    self:sendRound(payload)
    self.roundStats = nil
end

return API
