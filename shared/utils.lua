-- ═══════════════════════════════════════════════════════════
--  Shared Utilities
-- ═══════════════════════════════════════════════════════════

--- Squared distance (2D) – avoids sqrt
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return number
function DistSq(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
end

--- Squared distance (3D)
---@param x1 number
---@param y1 number
---@param z1 number
---@param x2 number
---@param y2 number
---@param z2 number
---@return number
function DistSq3D(x1, y1, z1, x2, y2, z2)
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    return dx * dx + dy * dy + dz * dz
end

--- Safe JSON decode
---@param str string
---@return table|nil
function SafeJsonDecode(str)
    if not str or str == '' then return nil end
    local ok, result = pcall(json.decode, str)
    if ok then return result end
    return nil
end

--- Generate a simple UUID v4
---@return string
function UUID()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end
