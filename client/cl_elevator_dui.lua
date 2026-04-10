-- ═══════════════════════════════════════════════════════════
--  cl_elevator_dui.lua – Interactive Floor Selection DUI
--  Shows floor panel in 3D when player enters range
-- ═══════════════════════════════════════════════════════════

local duiObj = nil
local duiTxd = nil
local duiTxn = 'webcom_elev_interact'
local duiDict = 'webcom_elev_interact_txd'
local duiReady = false
local currentActiveFloor = nil
local currentActiveElevator = nil

-- ─── DUI Setup ──────────────────────────────────────────

local function initDui()
    if duiObj then return end

    local url = 'nui://webcom_elevators/html/dui/floor_panel.html'
    duiObj = CreateDui(url, 768, 1024)
    if not duiObj then return end

    local handle = GetDuiHandle(duiObj)
    local txd = CreateRuntimeTxd(duiDict)
    duiTxd = CreateRuntimeTextureFromDuiHandle(txd, duiTxn, handle)
    duiReady = true
end

-- ─── Update Interactive DUI ─────────────────────────────

local function showInteractiveDui(elevator, currentFloor)
    if not duiObj then return end

    local floors = {}
    for _, f in ipairs(elevator.floors) do
        floors[#floors + 1] = {
            id = f.id,
            label = f.label,
            floorNumber = f.floorNumber,
            protectionType = f.protectionType,
            isCurrent = (f.id == currentFloor.id),
        }
    end

    SendDuiMessage(duiObj, json.encode({
        action = 'show',
        elevatorLabel = elevator.label,
        groupColor = elevator.groupColor or Config.DefaultColor,
        currentFloorLabel = currentFloor.label,
        navigationMode = elevator.navigationMode,
        floors = floors,
    }))
end

local function hideInteractiveDui()
    if not duiObj then return end
    SendDuiMessage(duiObj, json.encode({ action = 'hide' }))
end

-- ─── Draw DUI in 3D ────────────────────────────────────

local function drawDui3D(x, y, z, scale)
    SetDrawOrigin(x, y, z, 0)
    DrawSprite(duiDict, duiTxn, 0.0, 0.0, scale * 0.45, scale * 0.6, 0.0, 255, 255, 255, 255)
    ClearDrawOrigin()
end

-- ─── Main Proximity Loop ────────────────────────────────

CreateThread(function()
    if not Config.InteractiveDUI.Enabled then return end

    while #elevatorList == 0 do Wait(1000) end

    initDui()
    if not duiReady then return end

    local showDist = Config.InteractiveDUI.ShowDistance
    local showDistSq = showDist * showDist
    local duiScale = Config.InteractiveDUI.Scale
    local duiHeight = Config.InteractiveDUI.Height

    while true do
        Wait(300)

        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local nearest = nil
        local nearestElev = nil
        local nearestDistSq = showDistSq

        for _, elevator in ipairs(elevatorList) do
            for _, floor in ipairs(elevator.floors) do
                local point = floor.interactionPoint or floor.position
                if type(point) == 'string' then
                    point = SafeJsonDecode(point) or {}
                end
                if point and point.x then
                    local dSq = DistSq3D(pos.x, pos.y, pos.z, point.x, point.y, point.z)
                    if dSq < nearestDistSq then
                        nearestDistSq = dSq
                        nearest = floor
                        nearestElev = elevator
                    end
                end
            end
        end

        if nearest and nearestElev then
            -- Update content if changed
            if currentActiveFloor ~= nearest.id then
                currentActiveFloor = nearest.id
                currentActiveElevator = nearestElev
                showInteractiveDui(nearestElev, nearest)
            end

            -- Fast draw loop
            local point = nearest.interactionPoint or nearest.position
            if type(point) == 'string' then point = SafeJsonDecode(point) or {} end

            while true do
                Wait(0)
                local p = GetEntityCoords(PlayerPedId())
                local d = DistSq3D(p.x, p.y, p.z, point.x, point.y, point.z)
                if d > showDistSq then break end

                drawDui3D(point.x, point.y, point.z + duiHeight, duiScale)
            end

            currentActiveFloor = nil
            currentActiveElevator = nil
            hideInteractiveDui()
        end
    end
end)

-- ─── Cleanup ────────────────────────────────────────────

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if duiObj then
        DestroyDui(duiObj)
        duiObj = nil
    end
end)
