local Utils = include("terrortown/autorun/shared/sh_stats_utils.lua")
local Json = include("terrortown/autorun/shared/sh_stats_json.lua")

local API = {
    config = { website = "", token = "", logLevel = "INFO" },
    logLevel = "INFO",
}

local logLevelOrder = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

local function normalizeLogLevel(level)
    local normalized = string.upper(tostring(level or "INFO"))
    return logLevelOrder[normalized] and normalized or "INFO"
end

local function cleanLogValue(value)
    return tostring(value):gsub("[\r\n]", " ")
end

local function formatLogContext(context)
    if type(context) ~= "table" then return "" end

    local fields = {}
    for key, value in pairs(context) do
        if type(value) ~= "table" and type(value) ~= "function" then
            table.insert(fields, tostring(key) .. "=" .. cleanLogValue(value))
        end
    end
    table.sort(fields)

    if #fields == 0 then return "" end
    return " {" .. table.concat(fields, ", ") .. "}"
end

function API:log(level, message, context)
    if message == nil then
        message = level
        level = "INFO"
    else
        level = normalizeLogLevel(level)
    end

    if logLevelOrder[level] < logLevelOrder[normalizeLogLevel(self.logLevel)] then return end

    print("[TTT2 Stats][" .. level .. "] " .. cleanLogValue(message) .. formatLogContext(context))
end

function API:encodeJson(value, operation, context)
    local ok, encoded = pcall(Json.encode, value)
    if ok then return encoded end

    context = context or {}
    context.operation = operation
    context.reason = encoded
    self:log("ERROR", "JSON encoding failed", context)

    return nil
end

local config = include("terrortown/autorun/server/sv_stats_config.lua")
config(API, Json, normalizeLogLevel, logLevelOrder)

local delivery = include("terrortown/autorun/server/sv_stats_delivery.lua")
delivery(API, Utils, Json)

local rounds = include("terrortown/autorun/server/sv_stats_rounds.lua")
rounds(API, Utils)

return API
