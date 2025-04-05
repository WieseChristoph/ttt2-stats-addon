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

return Utils
