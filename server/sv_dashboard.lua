-- ═══════════════════════════════════════════════════════════
--  sv_dashboard.lua – httpmanager REST Endpoints + Widget Push
-- ═══════════════════════════════════════════════════════════

local function waitReady()
    while not isReady do Wait(100) end
end

local function hasHttpManager()
    return GetResourceState('httpmanager') == 'started'
end

local function printStandaloneBanner()
    print('^3+------------------------------------------------------------------------+^0')
    print('^3| [webcom_elevators] Standalone mode: dashboard endpoints are disabled.  |^0')
    print('^3| Full ArgusAdmin experience: https://weko-web.de/argusadmin            |^0')
    print('^3+------------------------------------------------------------------------+^0')
end

-- ─── Register Endpoints ─────────────────────────────────

CreateThread(function()
    waitReady()

    if not hasHttpManager() then
        printStandaloneBanner()
        return
    end

    -- Auto-config from httpmanager
    local ok, cfg = pcall(exports.httpmanager.getSharedConfig)
    if ok and cfg then
        Config.WebcomBaseUrl = cfg.DashboardURL
        Config.ServerId = cfg.ServerId
    end

    -- Listen for config updates
    AddEventHandler('httpmanager:sharedConfigUpdated', function(newCfg)
        if newCfg then
            Config.WebcomBaseUrl = newCfg.DashboardURL
            Config.ServerId = newCfg.ServerId
        end
    end)

    local epOk, epErr = pcall(function()

    -- GET all data (groups + elevators + floors)
    exports.httpmanager:registerEndpoint('elevators', function(_data)
        return _buildFullElevatorData()
    end)

    -- GET dashboard-data (combined stats + groups + elevators for web dashboard)
    exports.httpmanager:registerEndpoint('elevators/dashboard-data', function(_data)
        local protectedCount = 0
        for _, floor in pairs(Cache.floors) do
            if (floor.protection_type or 'none'):lower() ~= 'none' then
                protectedCount = protectedCount + 1
            end
        end

        local groupsArr = {}
        for _, group in pairs(Cache.groups) do
            groupsArr[#groupsArr + 1] = {
                id            = group.id,
                name          = group.name,
                label         = group.label,
                description   = group.description,
                color         = group.color,
                elevatorCount = 0,
            }
        end

        local elevatorsArr = {}
        for _, elev in pairs(Cache.elevators) do
            local floors = Cache.GetFloorsSorted(elev.id)
            local clientFloors = {}
            for _, f in ipairs(floors) do
                clientFloors[#clientFloors + 1] = {
                    id             = f.id,
                    floorNumber    = f.floor_number,
                    label          = f.label,
                    protectionType = (f.protection_type or 'none'):upper(),
                }
            end
            elevatorsArr[#elevatorsArr + 1] = {
                id             = elev.id,
                name           = elev.name,
                label          = elev.label,
                navigationMode = elev.navigation_mode,
                isActive       = elev.is_active,
                cooldownMs     = elev.cooldown_ms,
                groupId        = elev.group_id,
                floors         = clientFloors,
            }
            -- Update group elevator count
            for _, g in ipairs(groupsArr) do
                if g.id == elev.group_id then
                    g.elevatorCount = g.elevatorCount + 1
                    break
                end
            end
        end

        return {
            stats = {
                totalGroups    = Cache.groupCount,
                totalElevators = Cache.elevatorCount,
                totalFloors    = Cache.floorCount,
                protectedFloors = protectedCount,
            },
            groups    = groupsArr,
            elevators = elevatorsArr,
        }
    end)

    -- GET stats
    exports.httpmanager:registerEndpoint('elevators/stats', function(_data)
        local protectedCount = 0
        for _, floor in pairs(Cache.floors) do
            if (floor.protection_type or 'none'):lower() ~= 'none' then
                protectedCount = protectedCount + 1
            end
        end
        return {
            groups    = Cache.groupCount,
            elevators = Cache.elevatorCount,
            floors    = Cache.floorCount,
            protected = protectedCount,
        }
    end)

    -- POST get single elevator detail
    exports.httpmanager:registerEndpoint('elevators/get-elevator', function(data)
        local elevatorId = tonumber(data.body and data.body.elevatorId)
        if not elevatorId then return { error = 'missing elevatorId' } end

        local elevator = Cache.elevators[elevatorId]
        if not elevator then return { error = 'not_found' } end

        local group = Cache.groups[elevator.group_id]
        local floors = Cache.GetFloorsSorted(elevatorId)

        return {
            elevator = elevator,
            group    = group,
            floors   = floors,
        }
    end)

    -- POST create group
    exports.httpmanager:registerEndpoint('elevators/create-group', function(data)
        local b = data.body or {}
        if not b.name or not b.label then return { error = 'missing fields' } end

        local id = MySQL.insert.await(
            'INSERT INTO webcom_elevator_groups (name, label, description, color, created_by) VALUES (?, ?, ?, ?, ?)',
            { b.name, b.label, b.description, b.color or Config.DefaultColor, b.created_by }
        )
        Cache.Refresh()
        return { ok = true, id = id }
    end)

    -- POST update group
    exports.httpmanager:registerEndpoint('elevators/update-group', function(data)
        local b = data.body or {}
        local groupId = tonumber(b.groupId)
        if not groupId then return { error = 'missing groupId' } end

        MySQL.update.await(
            'UPDATE webcom_elevator_groups SET label = ?, description = ?, color = ? WHERE id = ?',
            { b.label, b.description, b.color, groupId }
        )
        Cache.Refresh()
        return { ok = true }
    end)

    -- POST delete group (cascades elevators + floors)
    exports.httpmanager:registerEndpoint('elevators/delete-group', function(data)
        local groupId = tonumber(data.body and data.body.groupId)
        if not groupId then return { error = 'missing groupId' } end

        MySQL.query.await('DELETE FROM webcom_elevator_groups WHERE id = ?', { groupId })
        Cache.Refresh()
        return { ok = true }
    end)

    -- POST create elevator
    exports.httpmanager:registerEndpoint('elevators/create-elevator', function(data)
        local b = data.body or {}
        if not b.groupId or not b.name or not b.label then return { error = 'missing fields' } end

        local id = MySQL.insert.await([[
            INSERT INTO webcom_elevators (group_id, name, label, navigation_mode, interaction_type, cooldown_ms, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], { b.groupId, b.name, b.label, b.navigationMode or 'list', b.interactionType or 'target', b.cooldownMs or 5000, b.created_by })

        -- Insert floors if provided
        if b.floors and type(b.floors) == 'table' then
            for i, f in ipairs(b.floors) do
                MySQL.insert.await([[
                    INSERT INTO webcom_elevator_floors (elevator_id, floor_number, label, position, interaction_point, protection_type, protection_data)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ]], {
                    id, tonumber(f.floorNumber) or i, f.label or '',
                    json.encode(f.position or {}),
                    f.interactionPoint and json.encode(f.interactionPoint) or nil,
                    f.protectionType or 'none',
                    f.protectionData and json.encode(f.protectionData) or nil,
                })
            end
        end

        Cache.Refresh()
        TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
        return { ok = true, id = id }
    end)

    -- POST update elevator
    exports.httpmanager:registerEndpoint('elevators/update-elevator', function(data)
        local b = data.body or {}
        local elevId = tonumber(b.elevatorId)
        if not elevId then return { error = 'missing elevatorId' } end

        MySQL.update.await([[
            UPDATE webcom_elevators SET label = ?, navigation_mode = ?, interaction_type = ?, cooldown_ms = ?, is_active = ?
            WHERE id = ?
        ]], { b.label, b.navigationMode, b.interactionType, b.cooldownMs, b.isActive and 1 or 0, elevId })

        Cache.Refresh()
        TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
        return { ok = true }
    end)

    -- POST delete elevator (cascades floors)
    exports.httpmanager:registerEndpoint('elevators/delete-elevator', function(data)
        local elevId = tonumber(data.body and data.body.elevatorId)
        if not elevId then return { error = 'missing elevatorId' } end

        MySQL.query.await('DELETE FROM webcom_elevators WHERE id = ?', { elevId })
        Cache.Refresh()
        TriggerClientEvent('webcom_elevators:cl:dataRefresh', -1)
        return { ok = true }
    end)

    end)

    if not epOk then
        print('^1[webcom_elevators]^0 Endpoint registration failed: ' .. tostring(epErr))
        return
    end

    print('^2[webcom_elevators]^0 Dashboard endpoints registered')
end)

-- ─── Build Full Data Payload ────────────────────────────

function _buildFullElevatorData()
    local groupsArr = {}
    for _, group in pairs(Cache.groups) do
        local elevators = Cache.GetElevatorsInGroup(group.id)
        local elevatorsArr = {}
        for _, elev in ipairs(elevators) do
            local floors = Cache.GetFloorsSorted(elev.id)
            elevatorsArr[#elevatorsArr + 1] = {
                id              = elev.id,
                name            = elev.name,
                label           = elev.label,
                navigationMode  = elev.navigation_mode,
                interactionType = elev.interaction_type,
                cooldownMs      = elev.cooldown_ms,
                isActive        = elev.is_active,
                floors          = floors,
                floorCount      = #floors,
            }
        end

        groupsArr[#groupsArr + 1] = {
            id            = group.id,
            name          = group.name,
            label         = group.label,
            description   = group.description,
            color         = group.color,
            elevators     = elevatorsArr,
            elevatorCount = #elevatorsArr,
        }
    end

    return { groups = groupsArr }
end

-- ─── Widget Push Thread ─────────────────────────────────

CreateThread(function()
    waitReady()

    local statToken = Config.Widgets['elevator-stats']
    if not statToken or statToken == 'PASTE_TOKEN_HERE' then return end
    if not Config.WebcomBaseUrl or not Config.ServerId then return end

    while true do
        Wait(Config.PushIntervalMs)
        if not isReady then goto continue end

        local protectedCount = 0
        for _, floor in pairs(Cache.floors) do
            if floor.protection_type ~= ProtectionType.NONE then
                protectedCount = protectedCount + 1
            end
        end

        pcall(function()
            exports.httpmanager:pushWidget('elevator-stats', {
                groups    = Cache.groupCount,
                elevators = Cache.elevatorCount,
                floors    = Cache.floorCount,
                protected = protectedCount,
            })
        end)

        ::continue::
    end
end)
