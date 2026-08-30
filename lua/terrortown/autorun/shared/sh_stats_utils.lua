local Utils = {}

-- function to copy tables (http://lua-users.org/wiki/CopyTable)
function Utils.deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[Utils.deepcopy(orig_key)] = Utils.deepcopy(orig_value)
        end
        setmetatable(copy, Utils.deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end

    return copy
end

function Utils.getFormattedDate()
    return os.date("%Y-%m-%d %H:%M:%S")
end

function Utils.getIsoDate()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function Utils.getSubroleName(ply)
    if not IsValid(ply) or not ply.GetSubRole then return nil end

    local role = ply:GetSubRole()
    if ply.GetSubRoleData then
        local data = ply:GetSubRoleData()
        if type(data) == "table" and type(data.name) == "string" then return data.name end
    end

    return role and tostring(role) or nil
end

local teamDefinitions = {
    { constant = "TEAM_INNOCENT", name = "innocents" },
    { constant = "TEAM_TRAITOR", name = "traitors" },
    { constant = "TEAM_JACKAL", name = "jackals" },
    { constant = "TEAM_LOVER", name = "lovers" },
    { constant = "TEAM_INFECTED", name = "infecteds" },
    { constant = "TEAM_JESTER", name = "jesters" },
    { constant = "TEAM_DUNCE", name = "dunces" },
    { constant = "TEAM_NONE", name = "nones" },
}

function Utils.getTeamName(teamId)
    for _, definition in ipairs(teamDefinitions) do
        local definedTeamId = rawget(_G, definition.constant)
        if definedTeamId ~= nil and teamId == definedTeamId then return definition.name end
    end

    return tostring(teamId)
end

function Utils.copySerializable(value)
    if type(value) ~= "table" then return value end

    local copy = {}
    for key, child in pairs(value) do
        local isArrayKey = type(key) == "number"
        local isSerializableField = type(key) == "string"
            and string.sub(key, 1, 1) ~= "_"
            and key ~= "weapons"
            and key ~= "startedUnix"
        if isArrayKey or isSerializableField then
            copy[key] = Utils.copySerializable(child)
        end
    end

    return copy
end

return Utils
