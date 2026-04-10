-- ═══════════════════════════════════════════════════════════
--  sv_cache.lua – In-Memory Caching Layer
--  Provides O(1) lookups for elevator data
--  All reads come from cache (zero DB hits during gameplay)
-- ═══════════════════════════════════════════════════════════

Cache = {}

-- ─── Data stores ────────────────────────────────────────
Cache.groups     = {}   -- id → group data
Cache.elevators  = {}   -- id → elevator data
Cache.floors     = {}   -- id → floor data

-- ─── Lookup maps ────────────────────────────────────────
Cache.elevatorsByGroup = {}  -- groupId → { elevatorId = true, ... }
Cache.floorsByElevator = {}  -- elevatorId → { floorId = true, ... }
Cache.floorsByPosition = {}  -- "x:y:z" → floor data (for proximity lookup)

-- ─── Counts ─────────────────────────────────────────────
Cache.groupCount    = 0
Cache.elevatorCount = 0
Cache.floorCount    = 0

-- ═══════════════════════════════════════════════════════════
--  INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function Cache.Initialize()
    Cache.LoadGroups()
    Cache.LoadElevators()
    Cache.LoadFloors()

    print('^2[webcom_elevators]^0 Cache loaded: '
        .. Cache.groupCount .. ' groups, '
        .. Cache.elevatorCount .. ' elevators, '
        .. Cache.floorCount .. ' floors')
end

-- ═══════════════════════════════════════════════════════════
--  GROUP CACHE
-- ═══════════════════════════════════════════════════════════

function Cache.LoadGroups()
    local rows = MySQL.query.await('SELECT * FROM webcom_elevator_groups')
    Cache.groups = {}
    Cache.groupCount = 0
    if not rows then return end

    for _, row in ipairs(rows) do
        Cache.groups[row.id] = {
            id          = row.id,
            name        = row.name,
            label       = row.label,
            description = row.description,
            color       = row.color or Config.DefaultColor,
            created_by  = row.created_by,
            created_at  = row.created_at,
        }
        Cache.groupCount = Cache.groupCount + 1
    end
end

-- ═══════════════════════════════════════════════════════════
--  ELEVATOR CACHE
-- ═══════════════════════════════════════════════════════════

function Cache.LoadElevators()
    local rows = MySQL.query.await('SELECT * FROM webcom_elevators')
    Cache.elevators = {}
    Cache.elevatorsByGroup = {}
    Cache.elevatorCount = 0
    if not rows then return end

    for _, row in ipairs(rows) do
        local elevator = {
            id               = row.id,
            group_id         = row.group_id,
            name             = row.name,
            label            = row.label,
            navigation_mode  = row.navigation_mode or 'list',
            interaction_type = row.interaction_type or 'target',
            cooldown_ms      = row.cooldown_ms or 5000,
            is_active        = (row.is_active == 1 or row.is_active == true),
            created_by       = row.created_by,
        }
        Cache.elevators[elevator.id] = elevator
        Cache.elevatorCount = Cache.elevatorCount + 1

        -- Group lookup
        if not Cache.elevatorsByGroup[elevator.group_id] then
            Cache.elevatorsByGroup[elevator.group_id] = {}
        end
        Cache.elevatorsByGroup[elevator.group_id][elevator.id] = true
    end
end

-- ═══════════════════════════════════════════════════════════
--  FLOOR CACHE
-- ═══════════════════════════════════════════════════════════

function Cache.LoadFloors()
    local rows = MySQL.query.await('SELECT * FROM webcom_elevator_floors')
    Cache.floors = {}
    Cache.floorsByElevator = {}
    Cache.floorsByPosition = {}
    Cache.floorCount = 0
    if not rows then return end

    for _, row in ipairs(rows) do
        local floor = Cache._parseFloorRow(row)
        Cache.floors[floor.id] = floor
        Cache.floorCount = Cache.floorCount + 1

        -- Elevator lookup
        if not Cache.floorsByElevator[floor.elevator_id] then
            Cache.floorsByElevator[floor.elevator_id] = {}
        end
        Cache.floorsByElevator[floor.elevator_id][floor.id] = true

        -- Position lookup for proximity (using interaction_point or position)
        local pos = floor.interaction_point or floor.position
        if pos and pos.x then
            local key = string.format('%.0f:%.0f:%.0f', pos.x, pos.y, pos.z)
            Cache.floorsByPosition[key] = floor
        end
    end
end

function Cache._parseFloorRow(row)
    local position = row.position
    if type(position) == 'string' then
        position = SafeJsonDecode(position) or {}
    end

    local interactionPoint = row.interaction_point
    if type(interactionPoint) == 'string' then
        interactionPoint = SafeJsonDecode(interactionPoint)
    end

    local protectionData = row.protection_data
    if type(protectionData) == 'string' then
        protectionData = SafeJsonDecode(protectionData)
    end

    return {
        id               = row.id,
        elevator_id      = row.elevator_id,
        floor_number     = row.floor_number,
        label            = row.label,
        position         = position,
        interaction_point = interactionPoint,
        protection_type  = row.protection_type or 'none',
        protection_data  = protectionData,
        is_active        = (row.is_active == 1 or row.is_active == true),
    }
end

-- ═══════════════════════════════════════════════════════════
--  ACCESSORS
-- ═══════════════════════════════════════════════════════════

--- Get all floors for an elevator, sorted by floor_number
---@param elevatorId number
---@return table[]
function Cache.GetFloorsSorted(elevatorId)
    local floorIds = Cache.floorsByElevator[elevatorId]
    if not floorIds then return {} end

    local result = {}
    for floorId in pairs(floorIds) do
        local floor = Cache.floors[floorId]
        if floor and floor.is_active then
            result[#result + 1] = floor
        end
    end

    table.sort(result, function(a, b)
        return a.floor_number < b.floor_number
    end)

    return result
end

--- Get all elevators in a group
---@param groupId number
---@return table[]
function Cache.GetElevatorsInGroup(groupId)
    local elevIds = Cache.elevatorsByGroup[groupId]
    if not elevIds then return {} end

    local result = {}
    for elevId in pairs(elevIds) do
        local elev = Cache.elevators[elevId]
        if elev then
            result[#result + 1] = elev
        end
    end

    table.sort(result, function(a, b)
        return a.label < b.label
    end)

    return result
end

--- Get elevator count per group
---@param groupId number
---@return number
function Cache.GetElevatorCount(groupId)
    local elevIds = Cache.elevatorsByGroup[groupId]
    if not elevIds then return 0 end
    local count = 0
    for _ in pairs(elevIds) do count = count + 1 end
    return count
end

--- Get floor count per elevator
---@param elevatorId number
---@return number
function Cache.GetFloorCount(elevatorId)
    local floorIds = Cache.floorsByElevator[elevatorId]
    if not floorIds then return 0 end
    local count = 0
    for _ in pairs(floorIds) do count = count + 1 end
    return count
end

-- ═══════════════════════════════════════════════════════════
--  CACHE REFRESH (after admin CRUD operations)
-- ═══════════════════════════════════════════════════════════

function Cache.Refresh()
    Cache.LoadGroups()
    Cache.LoadElevators()
    Cache.LoadFloors()
end

function Cache.RefreshGroup(groupId)
    -- Just reload everything for simplicity and consistency
    Cache.Refresh()
end

function Cache.RefreshElevator(elevatorId)
    Cache.Refresh()
end
