return function(API, Utils)
    API.roundStats = nil

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

    function API:startRound()
        local now = os.time()
        local playerCount = 0
        self.roundStats = {
            startedAt = Utils.getIsoDate(),
            startedUnix = now,
            players = {},
            events = {},
            _nextEventSequence = 1,
        }

        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:IsPlayer() and not ply:IsSpec() and not ply:IsBot() then
                playerCount = playerCount + 1
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

        self:log("INFO", "Round started", {
            map = game.GetMap(),
            players = playerCount,
            startedAt = self.roundStats.startedAt,
        })
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

        local attackerSnapshot
        if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
            if self:getPlayer(attacker:SteamID64()) then
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

        self:log("INFO", "Round finalized", {
            events = #payload.events,
            map = payload.mapName,
            players = #payload.players,
            roundKey = payload.roundKey,
            winningTeam = payload.winningTeam,
        })
        self:sendRound(payload)
        self.roundStats = nil
    end
end
