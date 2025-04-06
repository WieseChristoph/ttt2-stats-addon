local Utils = include("terrortown/autorun/shared/sh_stats_utils.lua")
local Json = include("terrortown/autorun/shared/sh_stats_json.lua")

local mapSuccessfullyAdded = false

local API = {}

API.config = {
  website = "",
  token = "",
}

API.roundStats = {}

API.initialRoundStats = {
  startTime = "",
  endTime = "",
  winnerTeam = "",
  playerStats = {}
}

API.initialPlayerStats = {
  team = "",
  deaths = {}
}

API.initialDeathStats = {
  attacker = nil,
  teamkill = false,
  inflictor = nil,
  hitgroup = 0,
  timeOfDeath = ""
}

function API.log(msg)
  print("[TTT2 Stats][API] " .. msg .. ".")
end

function API:addMap(mapName)
  if self.config.website == nil or self.config.website == "" then
    API.log("Error: No website configured")
    return
  end

  if self.config.token == nil or self.config.token == "" then
    API.log("Error: No token configured")
    return
  end

  API.log("Adding map " .. mapName)
  API.log("Adding map " .. self.config.website .. "/api/maps/" .. mapName)

  local request = {
    url     = self.config.website .. "/api/maps/" .. mapName,
    method  = "PUT",
    headers = {
      ["Authorization"] = "Bearer " .. self.config.token,
    },

    success = function(code, body, headers)
      if code ~= 201 then
        API.log("Error: API returned code " .. code .. ".")
        return
      end

      mapSuccessfullyAdded = true
      API.log("Map " .. mapName .. " added successfully.")
    end,

    failed  = function(reason)
      API.log("Error: " .. reason)
    end
  }

  HTTP(request)
end

function API:addRound()
  if not mapSuccessfullyAdded then
    API.log("Map not added yet. Cannot add round.")
    return
  end

  if self.roundStats == nil or self.roundStats == {} then
    API.log("No round stats to add.")
    return
  end

  API.log("Adding round")
  local roundStats = Utils.deepcopy(self.roundStats)

  local roundStatsJson = Json.encode(roundStats)

  local request = {
    url     = self.config.website .. "/api/maps/latest/rounds",
    method  = "PUT",
    headers = {
      ["Authorization"] = "Bearer " .. self.config.token,
      ["Content-Type"] = "application/json",
    },
    body    = roundStatsJson,

    success = function(code, body, headers)
      if code ~= 201 then
        API.log("Error: API returned code " .. code .. ".")
        return
      end

      API.log("Round added successfully.")
    end,

    failed  = function(reason)
      API.log("Error: " .. reason)
    end
  }

  HTTP(request)
end

return API
