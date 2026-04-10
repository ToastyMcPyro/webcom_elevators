-- ═══════════════════════════════════════════════════════════
--  sv_bridge.lua – Framework Bridge (QBX / ESX auto-detect)
-- ═══════════════════════════════════════════════════════════
print('^2[webcom_elevators] sv_bridge.lua LOADING^0')

Bridge = {}
Bridge.framework = nil -- 'qbx' | 'esx'

local QBCore, ESX

local function isResourceStarted(resourceName)
    return GetResourceState(resourceName) == 'started'
end

local function callResourceExport(resourceName, exportName, ...)
    if not isResourceStarted(resourceName) then
        return false, nil
    end

    local resourceExports = exports[resourceName]
    local fn = resourceExports and resourceExports[exportName]
    if type(fn) ~= 'function' then
        return false, nil
    end

    return pcall(fn, resourceExports, ...)
end

local function getQbxPlayerItems(player)
    if not player then return nil end
    return (player.PlayerData and player.PlayerData.items) or player.items
end

local function countItemsInList(items, itemName)
    local total = 0
    for _, item in pairs(items or {}) do
        if type(item) == 'table' and (item.name == itemName or item.item == itemName) then
            total = total + (tonumber(item.amount) or tonumber(item.count) or tonumber(item.qty) or 0)
        end
    end
    return total
end

local function makeItemEntry(name, label, image, imagePath, source)
    return {
        name = name,
        label = label or name,
        image = image,
        imagePath = imagePath,
        source = source,
    }
end

-- Synchronous framework detection (runs at load time)
if GetResourceState('qbx_core') == 'started' or GetResourceState('qb-core') == 'started' then
    Bridge.framework = 'qbx'
    local ok, obj = pcall(exports['qb-core'].GetCoreObject)
    if ok and obj then
        QBCore = obj
    end
elseif GetResourceState('es_extended') == 'started' then
    Bridge.framework = 'esx'
    local ok, obj = pcall(exports['es_extended'].getSharedObject)
    if ok and obj then
        ESX = obj
    end
end

if Bridge.framework then
    print('^2[webcom_elevators]^0 Bridge initialized – framework: ' .. Bridge.framework)
else
    print('^1[webcom_elevators]^0 No supported framework detected (qbx/esx)')
end

-- ─── GetPlayerBySource ──────────────────────────────────
function Bridge.GetPlayerBySource(src)
    src = tonumber(src)
    if not src then return nil end

    if Bridge.framework == 'qbx' then
        local ok, player = pcall(exports.qbx_core.GetPlayer, exports.qbx_core, src)
        if ok and player then return player end
        if QBCore then
            local p = QBCore.Functions.GetPlayer(src)
            return p
        end
    elseif Bridge.framework == 'esx' then
        if ESX then
            local xPlayer = ESX.GetPlayerFromId(src)
            if not xPlayer then return nil end
            return _normalizeEsx(xPlayer)
        end
    end

    return nil
end

-- ─── GetCitizenId ───────────────────────────────────────
function Bridge.GetCitizenId(src)
    local player = Bridge.GetPlayerBySource(src)
    if not player then return nil end

    if Bridge.framework == 'qbx' then
        if player.PlayerData then
            return player.PlayerData.citizenid
        end
        return player.citizenid
    elseif Bridge.framework == 'esx' then
        return player.citizenid
    end
    return nil
end

-- ─── GetPlayerJob ───────────────────────────────────────
function Bridge.GetPlayerJob(src)
    local player = Bridge.GetPlayerBySource(src)
    if not player then return nil, 0 end

    if Bridge.framework == 'qbx' then
        local pd = player.PlayerData or player
        if pd.job then
            local grade = 0
            if pd.job.grade then
                grade = type(pd.job.grade) == 'table' and (pd.job.grade.level or 0) or pd.job.grade
            end
            return pd.job.name, tonumber(grade) or 0
        end
    elseif Bridge.framework == 'esx' then
        if player.job then
            local grade = 0
            if player.job.grade then
                grade = type(player.job.grade) == 'table' and (player.job.grade.level or 0) or player.job.grade
            end
            return player.job.name, tonumber(grade) or 0
        end
    end

    return nil, 0
end

-- ─── HasItem (ox_inventory primary, common inventories) ─
function Bridge.HasItem(src, itemName, count)
    src = tonumber(src)
    if not src or not itemName then return false end
    count = count or 1

    -- Try ox_inventory first
    if isResourceStarted('ox_inventory') then
        local ok, result = pcall(exports.ox_inventory.Search, exports.ox_inventory, src, 'count', itemName)
        if ok then
            return (tonumber(result) or 0) >= count
        end
    end

    for _, inventoryName in ipairs({ 'qb-inventory', 'ps-inventory', 'lj-inventory' }) do
        local ok, result = callResourceExport(inventoryName, 'HasItem', src, itemName, count)
        if ok and result ~= nil then
            return result == true or (tonumber(result) or 0) >= count
        end
    end

    local okQsHasItem, qsHasItem = callResourceExport('qs-inventory', 'HasItem', src, itemName, count)
    if okQsHasItem and qsHasItem ~= nil then
        return qsHasItem == true or (tonumber(qsHasItem) or 0) >= count
    end

    local okQsCount, qsCount = callResourceExport('qs-inventory', 'GetItemTotalAmount', src, itemName)
    if okQsCount and qsCount ~= nil then
        return (tonumber(qsCount) or 0) >= count
    end

    if Bridge.framework == 'qbx' then
        local player = Bridge.GetPlayerBySource(src)
        if countItemsInList(getQbxPlayerItems(player), itemName) >= count then
            return true
        end

        if player and player.Functions and player.Functions.GetItemByName then
            local item = player.Functions.GetItemByName(itemName)
            return item and (item.amount or item.count or 0) >= count
        end
    end

    if Bridge.framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.getInventoryItem then
            local item = xPlayer.getInventoryItem(itemName)
            local itemCount = item and (tonumber(item.count) or tonumber(item.amount) or 0) or 0
            return itemCount >= count
        end
    end

    return false
end

-- ─── RemoveItem ─────────────────────────────────────────
function Bridge.RemoveItem(src, itemName, count)
    src = tonumber(src)
    if not src or not itemName then return false end
    count = count or 1

    -- ox_inventory
    if isResourceStarted('ox_inventory') then
        local ok, result = pcall(exports.ox_inventory.RemoveItem, exports.ox_inventory, src, itemName, count)
        if ok then return result end
    end

    for _, inventoryName in ipairs({ 'qb-inventory', 'ps-inventory', 'lj-inventory', 'qs-inventory' }) do
        local ok, result = callResourceExport(inventoryName, 'RemoveItem', src, itemName, count)
        if ok and result ~= nil then
            return result
        end
    end

    if Bridge.framework == 'qbx' then
        local player = Bridge.GetPlayerBySource(src)
        if player and player.Functions and player.Functions.RemoveItem then
            return player.Functions.RemoveItem(itemName, count)
        end
    end

    if Bridge.framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.removeInventoryItem then
            xPlayer.removeInventoryItem(itemName, count)
            return true
        end
    end

    return false
end

-- ─── GetJobs (for admin UI job picker) ──────────────────
function Bridge.GetJobs()
    local result = {}

    if Bridge.framework == 'qbx' and QBCore then
        local shared = QBCore.Shared and QBCore.Shared.Jobs
        if shared then
            for name, job in pairs(shared) do
                local grades = {}
                if job.grades then
                    for level, gradeData in pairs(job.grades) do
                        grades[#grades + 1] = {
                            level = tonumber(level) or 0,
                            name = type(gradeData) == 'table' and (gradeData.name or gradeData.label or '') or tostring(gradeData),
                        }
                    end
                    table.sort(grades, function(a, b) return a.level < b.level end)
                end
                result[#result + 1] = {
                    name = name,
                    label = type(job) == 'table' and (job.label or name) or name,
                    grades = grades,
                }
            end
        end
    end

    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

-- ─── GetItems (for admin UI item picker) ────────────────
function Bridge.GetItems()
    local result = {}
    local seen = {}

    local function addEntry(entry)
        if entry and entry.name and not seen[entry.name] then
            seen[entry.name] = true
            result[#result + 1] = entry
        end
    end

    -- Try ox_inventory first
    if isResourceStarted('ox_inventory') then
        local ok, items = pcall(exports.ox_inventory.Items, exports.ox_inventory)
        if ok and type(items) == 'table' then
            for name, item in pairs(items) do
                if type(item) == 'table' then
                    local image = (item.client and item.client.image) or item.image or (name .. '.png')
                    addEntry(makeItemEntry(
                        name,
                        item.label or name,
                        image,
                        image and ('https://cfx-nui-ox_inventory/web/images/' .. image) or nil,
                        'ox_inventory'
                    ))
                end
            end
        end
    end

    if Bridge.framework == 'qbx' and QBCore then
        local shared = QBCore.Shared and QBCore.Shared.Items
        if shared then
            for name, item in pairs(shared) do
                addEntry(makeItemEntry(
                    name,
                    type(item) == 'table' and (item.label or name) or name,
                    type(item) == 'table' and (item.image or (name .. '.png')) or (name .. '.png'),
                    nil,
                    'qb-shared'
                ))
            end
        end
    end

    if Bridge.framework == 'esx' and ESX then
        local items = ESX.Items
        if type(items) ~= 'table' and type(ESX.GetItems) == 'function' then
            local ok, fetchedItems = pcall(ESX.GetItems)
            if ok and type(fetchedItems) == 'table' then
                items = fetchedItems
            end
        end

        if type(items) == 'table' then
            for name, item in pairs(items) do
                if type(item) == 'table' then
                    addEntry(makeItemEntry(
                        name,
                        item.label or name,
                        item.image or (name .. '.png'),
                        nil,
                        'esx'
                    ))
                end
            end
        end
    end

    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

-- ─── Dashboard URL from httpmanager shared config ───────
function Bridge.GetDashboardConfig()
    if GetResourceState('httpmanager') ~= 'started' then
        return nil
    end

    local ok, cfg = pcall(exports.httpmanager.getSharedConfig)
    if ok and cfg then return cfg end
    return nil
end

-- ─── ESX Normalization ──────────────────────────────────
function _normalizeEsx(xPlayer)
    local identifier = xPlayer.getIdentifier()
    if identifier then
        identifier = identifier:gsub('^char%d+:', ''):gsub('^license:', '')
    end

    local jobData = xPlayer.getJob() or {}
    local gradeData = jobData.grade_name and {
        name  = jobData.grade_name,
        level = jobData.grade or 0,
    } or { name = '', level = 0 }

    return {
        source    = xPlayer.source,
        citizenid = identifier,
        charinfo  = {
            firstname = xPlayer.getName and xPlayer.getName():match('^(%S+)') or '',
            lastname  = xPlayer.getName and xPlayer.getName():match('%S+$') or '',
        },
        job = {
            name   = jobData.name or 'unemployed',
            label  = jobData.label or 'Unemployed',
            grade  = gradeData,
            onDuty = true,
        },
        PlayerData = {
            citizenid = identifier,
            job = {
                name  = jobData.name or 'unemployed',
                label = jobData.label or 'Unemployed',
                grade = gradeData,
            },
        },
    }
end
