if not SERVER then return end

local API = include("sv_stats_api_handler.lua")
local Json = include("terrortown/autorun/shared/sh_stats_json.lua")

local function log(msg)
  print("[TTT2 Stats] " .. msg .. ".")
end

-- create data folder
if not file.IsDir("ttt2_stats", "DATA") then
  file.CreateDir("ttt2_stats")
end

-- create config.txt if it doesn't exist
if not file.Exists("ttt2_stats/config.json", "DATA") then
  local configJson = Json.encode(API.config)
  file.Write("ttt2_stats/config.json", configJson)
end

-- read config.txt
if file.Exists("ttt2_stats/config.json", "DATA") then
  local configJson = file.Read("ttt2_stats/config.json", "DATA")
  API.config = Json.decode(configJson)
else
  log("Could not find config.json")
end

-- open stats on command
hook.Add("PlayerSay", "PlayerChat", function(ply, text)
  if (text == "!stats") then
    ply:SendLua("gui.OpenURL('" .. API.config.website .. "')")
  end
end)

-- open stats when F4 is pressed
hook.Add("ShowSpare2", "F4Pressed", function(ply)
  ply:SendLua("gui.OpenURL('" .. API.config.website .. "')")
end)

hook.Add("Initialize", "Initialize", function()
  log("Initialized")
  API:addMap(game.GetMap())
end)

hook.Add("TTTBeginRound", "BeginRound", function()
  -- init round stats
  API.roundStats = Utils.deepcopy(API.initialRoundStats)
  API.roundStats.startTime = Utils.getFormattedDate()
  -- init player stats
  for i, ply in ipairs(player.GetAll()) do
    if not ply:IsSpec() and not ply:IsBot() then
      API.roundStats.playerStats[ply:SteamID64()] = Utils.deepcopy(API.initialPlayerStats)
    end
  end
end)

hook.Add("TTTEndRound", "EndRound", function(result)
  -- add endTime, winnerTeam to the round and teams to all players
  API.roundStats.endTime = Utils.getFormattedDate()
  API.roundStats.winnerTeam = result
  for steamID, stats in pairs(API.roundStats.playerStats) do
    -- check for type "Player" (if not the player probably  disconnected)
    if type(player.GetBySteamID64(steamID)) == "Player" then
      stats["team"] = player.GetBySteamID64(steamID):GetTeam()
    end
  end

  API:addRound()
  API.roundStats = {}
end)

hook.Add("PlayerDeath", "PlayerDeath", function(victim, inflictor, attacker)
  -- round has not ended
  if API.roundStats.endTime ~= nil and API.roundStats.endTime == "" then
    -- victim is not a bot
    if not victim:IsBot() then
      local victimStats = API.roundStats.playerStats[victim:SteamID64()]
      -- victim is in the current round
      if victimStats ~= nil then
        if attacker ~= victim then
          local deathStats = Utils.deepcopy(API.initialDeathStats)
          deathStats.timeOfDeath = Utils.getFormattedDate()

          deathStats.hitgroup = victim:LastHitGroup()

          if attacker:IsPlayer() then
            deathStats.attacker = attacker:SteamID64()
            if attacker:GetTeam() == victim:GetTeam() then
              deathStats.teamkill = true
            end
          end

          if inflictor:IsValid() or inflictor == game.GetWorld() then
            if type(inflictor) == "Player" then
              if inflictor:GetActiveWeapon():IsValid() then
                deathStats.inflictor = inflictor:GetActiveWeapon():GetPrintName()
              end
            else
              deathStats.inflictor = inflictor:GetClass()
            end
          end

          table.insert(victimStats.deaths, deathStats)
        end
      end
    end
  end
end)

hook.Add("PlayerDisconnected", "PlayerDisconnected", function(ply)
  -- add player team on disconnect
  if API.roundStats.playerStats ~= nil and API.roundStats.playerStats[ply:SteamID64()] ~= nil then
    API.roundStats.playerStats[ply:SteamID64()]["team"] = ply:GetTeam()
  end
end)
