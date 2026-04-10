-- ═══════════════════════════════════════════════════════════
--  sv_main.lua – Core Elevator Server Logic
--  Schema init, Admin CRUD, Teleport validation, Protection checks
-- ═══════════════════════════════════════════════════════════

isReady = false  -- Global: referenced by sv_dashboard.lua

-- ─── Initialization ─────────────────────────────────────

CreateThread(function()
    while not MySQL do Wait(100) end

    _ensureSchema()
    Cache.Initialize()

    isReady = true
    print('^2[webcom_elevators]^0 Module initialized – '
        .. Cache.groupCount .. ' groups, '
        .. Cache.elevatorCount .. ' elevators, '
        .. Cache.floorCount .. ' floors')
end)

function _ensureSchema()
    local sqlFile = LoadResourceFile(GetCurrentResourceName(), 'sql/install.sql')
    if not sqlFile then
        print('^1[webcom_elevators]^0 Could not load sql/install.sql')
        return
    end

    for stmt in sqlFile:gmatch('([^;]+)') do
        local trimmed = stmt:match('^%s*(.-)%s*$')
        if trimmed and #trimmed > 5 then
            local ok, err = pcall(function() MySQL.query.await(trimmed) end)
            if not ok then
                print('^1[webcom_elevators]^0 SQL error: ' .. tostring(err))
            end
        end
    end
end

-- ─── Rate Limiting ──────────────────────────────────────

local lastAction = {}

local function throttle(src)
    local now = GetGameTimer()
    if lastAction[src] and (now - lastAction[src]) < Config.Throttle.MinEventInterval then
        return true
    end
    lastAction[src] = now
    return false
end

-- ─── Cooldown Tracking ──────────────────────────────────

local playerCooldowns = {} -- src → timestamp (ms)

local function isOnCooldown(src, cooldownMs)
    local now = GetGameTimer()
    local last = playerCooldowns[src]
    if last and (now - last) < (cooldownMs or Config.Cooldown.DefaultMs) then
        return true, (cooldownMs or Config.Cooldown.DefaultMs) - (now - last)
    end
    return false, 0
end

local function setCooldown(src)
    playerCooldowns[src] = GetGameTimer()
end

-- ═══════════════════════════════════════════════════════════
--  PROTECTION VALIDATION (Server-side only)
-- ═══════════════════════════════════════════════════════════

--- Validate floor protection. Returns true if access granted.
---@param src number
---@param floor table
---@param inputData table  { pin, password } from client
---@return boolean, string  ok, reason
function ValidateProtection(src, floor, inputData)
    if not floor then return false, 'invalid_floor' end

    local pType = (floor.protection_type or 'none'):lower()
    local pData = floor.protection_data

    if pType == ProtectionType.NONE then
        return true, 'ok'
    end

    if not pData then return false, 'invalid_protection' end

    if pType == ProtectionType.PIN then
        local correctPin = tostring(pData.pin or '')
        local inputPin = tostring(inputData and inputData.pin or '')
        if inputPin == '' then return false, 'pin_required' end
        if inputPin ~= correctPin then return false, 'wrong_pin' end
        return true, 'ok'
    end

    if pType == ProtectionType.PASSWORD then
        local correctPw = tostring(pData.password or '')
        local inputPw = tostring(inputData and inputData.password or '')
        if inputPw == '' then return false, 'password_required' end
        if inputPw ~= correctPw then return false, 'wrong_password' end
        return true, 'ok'
    end

    if pType == ProtectionType.JOB then
        local requiredJob = pData.job
        local minRank = tonumber(pData.minRank) or 0
        if not requiredJob then return false, 'invalid_protection' end

        local playerJob, playerGrade = Bridge.GetPlayerJob(src)
        if not playerJob or playerJob ~= requiredJob then
            return false, 'wrong_job'
        end
        if playerGrade < minRank then
            return false, 'insufficient_rank'
        end
        return true, 'ok'
    end

    if pType == ProtectionType.ITEM then
        local itemName = pData.item
        local consume = pData.consume == true
        if not itemName then return false, 'invalid_protection' end

        if not Bridge.HasItem(src, itemName, 1) then
            return false, 'missing_item'
        end

        if consume then
            Bridge.RemoveItem(src, itemName, 1)
        end

        return true, 'ok'
    end

    return false, 'unknown_protection'
end

-- ═══════════════════════════════════════════════════════════
--  CLIENT DATA REQUESTS
-- ═══════════════════════════════════════════════════════════

--- Build elevator data for client (simplified, no protection secrets)
function GetClientElevatorData()
    local result = {}

    for _, elevator in pairs(Cache.elevators) do
        if elevator.is_active then
            local group = Cache.groups[elevator.group_id]
            local floors = Cache.GetFloorsSorted(elevator.id)

            -- Strip sensitive protection data for client
            local clientFloors = {}
            for _, floor in ipairs(floors) do
                if floor.is_active then
                    clientFloors[#clientFloors + 1] = {
                        id              = floor.id,
                        elevatorId      = floor.elevator_id,
                        floorNumber     = floor.floor_number,
                        label           = floor.label,
                        position        = floor.position,
                        interactionPoint = floor.interaction_point,
                        protectionType  = (floor.protection_type or 'none'):upper(),
                        isActive        = floor.is_active,
                        -- NOTE: protection_data is NOT sent to client (PIN/password are secret)
                    }
                end
            end

            result[#result + 1] = {
                id              = elevator.id,
                groupId         = elevator.group_id,
                groupLabel      = group and group.label or '',
                groupColor      = group and group.color or Config.DefaultColor,
                name            = elevator.name,
                label           = elevator.label,
                navigationMode  = elevator.navigation_mode,
                interactionType = elevator.interaction_type,
                cooldownMs      = elevator.cooldown_ms,
                floors          = clientFloors,
            }
        end
    end

    return result
end

-- ═══════════════════════════════════════════════════════════
--  NET EVENTS – Player
-- ═══════════════════════════════════════════════════════════

-- Get all elevator data
RegisterNetEvent('webcom_elevators:sv:getElevators', function()
    local src = source
    -- No throttle: read-only cache lookup, triggered automatically after CRUD

    local data = GetClientElevatorData()
    TriggerClientEvent('webcom_elevators:cl:receiveElevators', src, data)
end)

-- Request teleport to a floor
RegisterNetEvent('webcom_elevators:sv:requestTeleport', function(floorId, inputData)
    local src = source
    if throttle(src) then return end
    if type(floorId) ~= 'number' then return end

    -- Sanitize inputData
    if type(inputData) ~= 'table' then inputData = {} end

    local floor = Cache.floors[floorId]
    if not floor or not floor.is_active then
        TriggerClientEvent('webcom_elevators:cl:teleportResult', src, false, 'invalid_floor')
        return
    end

    local elevator = Cache.elevators[floor.elevator_id]
    if not elevator or not elevator.is_active then
        TriggerClientEvent('webcom_elevators:cl:teleportResult', src, false, 'invalid_elevator')
        return
    end

    -- Cooldown check
    local onCd, remaining = isOnCooldown(src, elevator.cooldown_ms)
    if onCd then
        TriggerClientEvent('webcom_elevators:cl:teleportResult', src, false, 'cooldown', { remaining = remaining })
        return
    end

    -- Protection check
    local ok, reason = ValidateProtection(src, floor, inputData)
    if not ok then
        TriggerClientEvent('webcom_elevators:cl:teleportResult', src, false, reason)
        return
    end

    -- Set cooldown
    setCooldown(src)

    -- Send teleport data
    TriggerClientEvent('webcom_elevators:cl:teleportResult', src, true, 'ok', {
        position = floor.position,
        floorLabel = floor.label,
        elevatorLabel = elevator.label,
    })
end)

-- Validate PIN (pre-check before teleport, so NUI can show success/error)
lib.callback.register('webcom_elevators:validatePin', function(src, floorId, pin)
    if type(floorId) ~= 'number' then return false end
    if type(pin) ~= 'string' then return false end

    local floor = Cache.floors[floorId]
    if not floor then return false end
    if (floor.protection_type or ''):lower() ~= ProtectionType.PIN then return false end

    local correctPin = tostring(floor.protection_data and floor.protection_data.pin or '')
    return pin == correctPin
end)

-- Validate Password
lib.callback.register('webcom_elevators:validatePassword', function(src, floorId, password)
    if type(floorId) ~= 'number' then return false end
    if type(password) ~= 'string' then return false end

    local floor = Cache.floors[floorId]
    if not floor then return false end
    if (floor.protection_type or ''):lower() ~= ProtectionType.PASSWORD then return false end

    local correctPw = tostring(floor.protection_data and floor.protection_data.password or '')
    return password == correctPw
end)

-- ═══════════════════════════════════════════════════════════
--  NET EVENTS – Admin CRUD
-- ═══════════════════════════════════════════════════════════

-- Get all data for admin panel
RegisterNetEvent('webcom_elevators:sv:adminGetData', function()
    local src = source
    -- No throttle: read-only cache lookup, triggered automatically after CRUD
    if not HasPermission(src, 'admin') then return end

    local groups = {}
    for _, group in pairs(Cache.groups) do
        local elevators = Cache.GetElevatorsInGroup(group.id)
        local elevatorsData = {}
        for _, elev in ipairs(elevators) do
            local floors = Cache.GetFloorsSorted(elev.id)
            -- Map floors to camelCase for NUI (include full protection_data for admin)
            local floorsData = {}
            for _, floor in ipairs(floors) do
                floorsData[#floorsData + 1] = {
                    id              = floor.id,
                    elevatorId      = floor.elevator_id,
                    floorNumber     = floor.floor_number,
                    label           = floor.label,
                    position        = floor.position,
                    interactionPoint = floor.interaction_point,
                    protectionType  = (floor.protection_type or 'none'):upper(),
                    protectionData  = floor.protection_data,
                    isActive        = floor.is_active,
                }
            end
            elevatorsData[#elevatorsData + 1] = {
                id              = elev.id,
                name            = elev.name,
                label           = elev.label,
                navigationMode  = elev.navigation_mode,
                interactionType = elev.interaction_type,
                cooldownMs      = elev.cooldown_ms,
                isActive        = elev.is_active,
                floors          = floorsData,
                floorCount      = #floorsData,
            }
        end

        groups[#groups + 1] = {
            id            = group.id,
            name          = group.name,
            label         = group.label,
            description   = group.description,
            color         = group.color,
            elevators     = elevatorsData,
            elevatorCount = #elevatorsData,
        }
    end

    -- Get available jobs for picker
    local jobs = Bridge.GetJobs()
    local items = Bridge.GetItems()

    TriggerClientEvent('webcom_elevators:cl:adminReceiveData', src, {
        groups    = groups,
        jobs      = jobs,
        items     = items,
        stats     = {
            groups    = Cache.groupCount,
            elevators = Cache.elevatorCount,
            floors    = Cache.floorCount,
        },
    })
end)

-- Create group
RegisterNetEvent('webcom_elevators:sv:createGroup', function(data)
    local src = source
    if throttle(src) then return end
    if not HasPermission(src, 'admin') then return end
    if type(data) ~= 'table' or not data.name or not data.label then return end

    -- Sanitize
    local name = tostring(data.name):lower():gsub('[^a-z0-9_]', '')
    if name == '' then
        TriggerClientEvent('webcom_elevators:cl:adminResult', src, false, 'Ungültiger Name')
        return
    end

    local id = MySQL.insert.await(
        'INSERT INTO webcom_elevator_groups (name, label, description, color, created_by) VALUES (?, ?, ?, ?, ?)',
        { name, data.label, data.description or '', data.color or Config.DefaultColor, GetPlayerCitizenId(src) or tostring(src) }
    )

    Cache.Refresh()
    TriggerClientEvent('webcom_elevators:cl:adminResult', src, true, 'Gruppe erstellt')
    TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
end)

-- Update group
RegisterNetEvent('webcom_elevators:sv:updateGroup', function(groupId, data)
    local src = source
    if throttle(src) then return end
    if not HasPermission(src, 'admin') then return end
    if type(groupId) ~= 'number' or type(data) ~= 'table' then return end

    MySQL.update.await(
        'UPDATE webcom_elevator_groups SET label = ?, description = ?, color = ? WHERE id = ?',
        { data.label or '', data.description or '', data.color or Config.DefaultColor, groupId }
    )

    Cache.Refresh()
    TriggerClientEvent('webcom_elevators:cl:adminResult', src, true, 'Gruppe aktualisiert')
    TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
end)

-- Delete group
RegisterNetEvent('webcom_elevators:sv:deleteGroup', function(groupId)
    local src = source
    if throttle(src) then return end
    if not HasPermission(src, 'admin') then return end
    if type(groupId) ~= 'number' then return end

    MySQL.query.await('DELETE FROM webcom_elevator_groups WHERE id = ?', { groupId })
    Cache.Refresh()
    TriggerClientEvent('webcom_elevators:cl:adminResult', src, true, 'Gruppe gelöscht')
    TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
end)

-- Create elevator with floors
RegisterNetEvent('webcom_elevators:sv:createElevator', function(data)
    local src = source
    if throttle(src) then return end
    if not HasPermission(src, 'admin') then return end
    if type(data) ~= 'table' then return end
    if not data.groupId or not data.name or not data.label then
        TriggerClientEvent('webcom_elevators:cl:adminResult', src, false, 'Fehlende Felder')
        return
    end

    -- Sanitize name
    local name = tostring(data.name):lower():gsub('[^a-z0-9_]', '')
    if name == '' then
        TriggerClientEvent('webcom_elevators:cl:adminResult', src, false, 'Ungültiger Name')
        return
    end

    -- Check group exists
    if not Cache.groups[data.groupId] then
        TriggerClientEvent('webcom_elevators:cl:adminResult', src, false, 'Gruppe nicht gefunden')
        return
    end

    local elevId = MySQL.insert.await([[
        INSERT INTO webcom_elevators (group_id, name, label, navigation_mode, interaction_type, cooldown_ms, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.groupId,
        name,
        data.label,
        data.navigationMode or 'list',
        data.interactionType or 'target',
        tonumber(data.cooldownMs) or 5000,
        GetPlayerCitizenId(src) or tostring(src),
    })

    -- Insert floors
    if data.floors and type(data.floors) == 'table' then
        for i, f in ipairs(data.floors) do
            if f.position and f.label then
                MySQL.insert.await([[
                    INSERT INTO webcom_elevator_floors (elevator_id, floor_number, label, position, interaction_point, protection_type, protection_data)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ]], {
                    elevId,
                    tonumber(f.floorNumber) or i,
                    f.label,
                    json.encode(f.position),
                    f.interactionPoint and json.encode(f.interactionPoint) or nil,
                    (f.protectionType or 'none'):lower(),
                    f.protectionData and json.encode(f.protectionData) or nil,
                })
            end
        end
    end

    Cache.Refresh()
    TriggerClientEvent('webcom_elevators:cl:adminResult', src, true, 'Aufzug erstellt')
    TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
end)

-- Update elevator
RegisterNetEvent('webcom_elevators:sv:updateElevator', function(elevId, data)
    local src = source
    if throttle(src) then return end
    if not HasPermission(src, 'admin') then return end
    if type(elevId) ~= 'number' or type(data) ~= 'table' then return end

    MySQL.update.await([[
        UPDATE webcom_elevators SET label = ?, group_id = ?, navigation_mode = ?, interaction_type = ?, cooldown_ms = ?, is_active = ?
        WHERE id = ?
    ]], {
        data.label,
        tonumber(data.groupId) or Cache.elevators[elevId].group_id,
        data.navigationMode or 'list',
        data.interactionType or 'target',
        tonumber(data.cooldownMs) or 5000,
        (data.isActive == nil or data.isActive) and 1 or 0,
        elevId,
    })

    Cache.Refresh()
    TriggerClientEvent('webcom_elevators:cl:adminResult', src, true, 'Aufzug aktualisiert')
    TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
end)

-- Delete elevator
RegisterNetEvent('webcom_elevators:sv:deleteElevator', function(elevId)
    local src = source
    if throttle(src) then return end
    if not HasPermission(src, 'admin') then return end
    if type(elevId) ~= 'number' then return end

    MySQL.query.await('DELETE FROM webcom_elevators WHERE id = ?', { elevId })
    Cache.Refresh()
    TriggerClientEvent('webcom_elevators:cl:adminResult', src, true, 'Aufzug gelöscht')
    TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
end)

-- Toggle elevator active
RegisterNetEvent('webcom_elevators:sv:toggleElevator', function(elevId)
    local src = source
    if throttle(src) then return end
    if not HasPermission(src, 'admin') then return end
    if type(elevId) ~= 'number' then return end

    local elev = Cache.elevators[elevId]
    if not elev then return end

    local newState = elev.is_active and 0 or 1
    MySQL.update.await('UPDATE webcom_elevators SET is_active = ? WHERE id = ?', { newState, elevId })

    Cache.Refresh()
    TriggerClientEvent('webcom_elevators:cl:adminResult', src, true, newState == 1 and 'Aufzug aktiviert' or 'Aufzug deaktiviert')
    TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
end)

-- ─── Floor CRUD ─────────────────────────────────────────

RegisterNetEvent('webcom_elevators:sv:addFloor', function(elevId, floorData)
    local src = source
    if throttle(src) then return end
    if not HasPermission(src, 'admin') then return end
    if type(elevId) ~= 'number' or type(floorData) ~= 'table' then return end

    if not floorData.position or not floorData.label then
        TriggerClientEvent('webcom_elevators:cl:adminResult', src, false, 'Position und Label sind erforderlich')
        return
    end

    MySQL.insert.await([[
        INSERT INTO webcom_elevator_floors (elevator_id, floor_number, label, position, interaction_point, protection_type, protection_data)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        elevId,
        tonumber(floorData.floorNumber) or 0,
        floorData.label,
        json.encode(floorData.position),
        floorData.interactionPoint and json.encode(floorData.interactionPoint) or nil,
        (floorData.protectionType or 'none'):lower(),
        floorData.protectionData and json.encode(floorData.protectionData) or nil,
    })

    Cache.Refresh()
    TriggerClientEvent('webcom_elevators:cl:adminResult', src, true, 'Etage hinzugefügt')
    TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
end)

RegisterNetEvent('webcom_elevators:sv:updateFloor', function(floorId, floorData)
    local src = source
    if throttle(src) then return end
    if not HasPermission(src, 'admin') then return end
    if type(floorId) ~= 'number' or type(floorData) ~= 'table' then return end

    -- Support both camelCase (from NUI) and snake_case
    local floorNumber = floorData.floorNumber or floorData.floor_number
    local label = floorData.label
    local position = floorData.position
    local interactionPoint = floorData.interactionPoint or floorData.interaction_point
    local protectionType = (floorData.protectionType or floorData.protection_type or 'none'):lower()
    local protectionData = floorData.protectionData or floorData.protection_data
    local isActive = floorData.isActive
    if isActive == nil then isActive = floorData.is_active end
    if isActive == nil then isActive = true end

    -- Preserve existing data for fields not provided
    local existing = Cache.floors[floorId]
    if existing then
        if floorNumber == nil then floorNumber = existing.floor_number end
        if label == nil then label = existing.label end
        if position == nil then position = existing.position end
        if interactionPoint == nil then interactionPoint = existing.interaction_point end
    end

    MySQL.update.await([[
        UPDATE webcom_elevator_floors
        SET floor_number = ?, label = ?, position = ?, interaction_point = ?, protection_type = ?, protection_data = ?, is_active = ?
        WHERE id = ?
    ]], {
        tonumber(floorNumber) or 0,
        label or '',
        json.encode(position or {}),
        interactionPoint and json.encode(interactionPoint) or nil,
        protectionType,
        protectionData and json.encode(protectionData) or nil,
        isActive and 1 or 0,
        floorId,
    })

    Cache.Refresh()
    TriggerClientEvent('webcom_elevators:cl:adminResult', src, true, 'Etage aktualisiert')
    TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
end)

RegisterNetEvent('webcom_elevators:sv:deleteFloor', function(floorId)
    local src = source
    if throttle(src) then return end
    if not HasPermission(src, 'admin') then return end
    if type(floorId) ~= 'number' then return end

    MySQL.query.await('DELETE FROM webcom_elevator_floors WHERE id = ?', { floorId })
    Cache.Refresh()
    TriggerClientEvent('webcom_elevators:cl:adminResult', src, true, 'Etage gelöscht')
    TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
end)

-- ─── Admin: Teleport to position ────────────────────────

RegisterNetEvent('webcom_elevators:sv:adminTeleport', function(position)
    local src = source
    if not HasPermission(src, 'admin') then return end
    if type(position) ~= 'table' or not position.x then return end

    TriggerClientEvent('webcom_elevators:cl:adminTeleport', src, position)
end)

-- ─── Cleanup on player drop ─────────────────────────────

AddEventHandler('playerDropped', function()
    local src = source
    lastAction[src] = nil
    playerCooldowns[src] = nil
end)
