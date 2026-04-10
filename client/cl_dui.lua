-- ═══════════════════════════════════════════════════════════
--  cl_dui.lua – Passive 3D DUI Labels (Elevator Name + Floor)
-- ═══════════════════════════════════════════════════════════

local duiObj = nil
local duiTxd = nil
local duiTxn = 'webcom_elev_dui'
local duiDict = 'webcom_elev_dui_txd'
local duiReady = false
local currentDuiFloor = nil

-- ─── DUI Setup ──────────────────────────────────────────

local function initDui()
    if duiObj then return end

    local url = 'nui://webcom_elevators/html/dui.html'
    duiObj = CreateDui(url, 512, 512)
    if not duiObj then return end

    local handle = GetDuiHandle(duiObj)
    local txd = CreateRuntimeTxd(duiDict)
    duiTxd = CreateRuntimeTextureFromDuiHandle(txd, duiTxn, handle)
    duiReady = true
end

-- ─── Update DUI Content ─────────────────────────────────

local function showDui(elevatorLabel, floorLabel, color)
    if not duiObj then return end
    SendDuiMessage(duiObj, json.encode({
        action = 'show',
        elevatorLabel = elevatorLabel,
        floorLabel = floorLabel,
        color = color or Config.DefaultColor,
    }))
end

local function hideDui()
    if not duiObj then return end
    SendDuiMessage(duiObj, json.encode({ action = 'hide' }))
end

-- ─── Draw DUI in 3D World ───────────────────────────────

local function drawDui3D(x, y, z, scale)
    SetDrawOrigin(x, y, z, 0)
    DrawSprite(duiDict, duiTxn, 0.0, 0.0, scale * 0.5, scale * 0.5, 0.0, 255, 255, 255, 255)
    ClearDrawOrigin()
end

-- ─── Main Proximity Loop ────────────────────────────────

CreateThread(function()
    if not Config.DUI.Enabled then return end

    -- Wait for data
    while #elevatorList == 0 do Wait(1000) end

    initDui()
    if not duiReady then return end

    local showDist = Config.DUI.ShowDistance
    local showDistSq = showDist * showDist
    local duiScale = Config.DUI.Scale

    while true do
        Wait(200)

        local ped = PlayerPedId()
        -- Only show on foot
        if IsPedInAnyVehicle(ped, false) then
            if currentDuiFloor then
                hideDui()
                currentDuiFloor = nil
            end
            goto continue
        end

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
            -- Update content if floor changed
            if currentDuiFloor ~= nearest.id then
                currentDuiFloor = nearest.id
                showDui(nearestElev.label, nearest.label, nearestElev.groupColor)
            end

            -- Fast draw loop while nearby
            local point = nearest.interactionPoint or nearest.position
            if type(point) == 'string' then point = SafeJsonDecode(point) or {} end

            while true do
                Wait(0)
                local p = GetEntityCoords(PlayerPedId())
                local d = DistSq3D(p.x, p.y, p.z, point.x, point.y, point.z)
                if d > showDistSq or IsPedInAnyVehicle(PlayerPedId(), false) then break end

                -- Distance-based scale
                local dist = math.sqrt(d)
                local s = duiScale * (1.0 - (dist / showDist) * 0.3)
                drawDui3D(point.x, point.y, point.z + 1.2, s)
            end

            currentDuiFloor = nil
            hideDui()
        else
            if currentDuiFloor then
                hideDui()
                currentDuiFloor = nil
            end
        end

        ::continue::
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
