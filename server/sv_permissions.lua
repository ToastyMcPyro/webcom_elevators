-- ═══════════════════════════════════════════════════════════
--  sv_permissions.lua – Dual-Mode Permission System
--  'config' mode: ACE / job / citizenid checks
--  'dashboard' mode: httpmanager license-auth
-- ═══════════════════════════════════════════════════════════

--- Check if player has a specific permission
---@param src number
---@param permKey string  Permission key (e.g. 'admin')
---@return boolean
function HasPermission(src, permKey)
    if Config.PermissionMode == 'dashboard' then
        return _checkDashboardPermission(src, permKey)
    else
        return _checkConfigPermission(src, permKey)
    end
end

-- ─── Config Mode ────────────────────────────────────────

function _checkConfigPermission(src, permKey)
    local perm = Config.Permissions[permKey]
    if not perm then return false end

    -- ACE check
    if perm.aces then
        for _, ace in ipairs(perm.aces) do
            if IsPlayerAceAllowed(tostring(src), ace) then
                return true
            end
        end
    end

    -- Job check
    if perm.jobs and #perm.jobs > 0 then
        local jobName = Bridge.GetPlayerJob(src)
        if jobName then
            for _, j in ipairs(perm.jobs) do
                if j == jobName then
                    return true
                end
            end
        end
    end

    -- CitizenID check
    if perm.citizenids and #perm.citizenids > 0 then
        local citizenid = Bridge.GetCitizenId(src)
        if citizenid then
            for _, cid in ipairs(perm.citizenids) do
                if cid == citizenid then
                    return true
                end
            end
        end
    end

    return false
end

-- ─── Dashboard Mode ─────────────────────────────────────

function _checkDashboardPermission(src, permKey)
    local dashPerm = Config.DashboardPermissions[permKey]
    if not dashPerm then return false end

    -- Get player FiveM license identifier
    local identifiers = GetPlayerIdentifiers(src)
    local license = nil
    for _, id in ipairs(identifiers) do
        if id:find('^license:') then
            license = id
            break
        end
    end
    if not license then return false end

    -- Query httpmanager for permission check
    local ok, result = pcall(function()
        return exports.httpmanager:checkPermission(license, dashPerm)
    end)

    return ok and result == true
end

-- ─── Helper: Get Player CitizenId ───────────────────────

function GetPlayerCitizenId(src)
    return Bridge.GetCitizenId(src)
end

-- ─── Helper: Get Player Job Name ────────────────────────

function GetPlayerJobName(src)
    local name, _ = Bridge.GetPlayerJob(src)
    return name
end

-- ─── Helper: Get Player Job Grade ───────────────────────

function GetPlayerJobGrade(src)
    local _, grade = Bridge.GetPlayerJob(src)
    return grade
end
