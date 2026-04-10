-- ═══════════════════════════════════════════════════════════
--  cl_main.lua – Core Client: Elevator Interaction + NUI Bridge
--  Handles floor selection, teleportation, fade-to-black
-- ═══════════════════════════════════════════════════════════

local currentElevator = nil  -- currently open elevator data
elevatorList = {}            -- cached list of elevators (global for cl_dui)
local activeZones = {}       -- zone names we've created (for cleanup)
local isNuiOpen = false
local clientCooldown = 0     -- visual-only cooldown timestamp

-- ─── Initialize: Request Elevators ──────────────────────

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('webcom_elevators:sv:getElevators')
end)

-- Receive elevator list
RegisterNetEvent('webcom_elevators:cl:receiveElevators', function(elevators)
    elevatorList = elevators or {}
    _setupInteractions()
end)

-- Refresh trigger (after admin CRUD)
RegisterNetEvent('webcom_elevators:cl:dataRefresh', function()
    TriggerServerEvent('webcom_elevators:sv:getElevators')
end)

-- ─── Interaction Setup (ox_target or markers) ───────────

function _setupInteractions()
    -- Remove previously created zones
    for _, zoneName in ipairs(activeZones) do
        pcall(function() exports.ox_target:removeZone(zoneName) end)
    end
    activeZones = {}

    for _, elevator in ipairs(elevatorList) do
        for _, floor in ipairs(elevator.floors) do
            local point = floor.interactionPoint or floor.position
            if type(point) == 'string' then
                point = SafeJsonDecode(point) or {}
            end

            if point and point.x then
                if Config.InteractionMethod == 'target' then
                    local zoneName = 'webcom_elev_' .. elevator.id .. '_f' .. floor.id
                    local floorRef = floor
                    local elevRef = elevator
                    exports.ox_target:addSphereZone({
                        name = zoneName,
                        coords = vector3(point.x, point.y, point.z),
                        radius = 1.5,
                        options = {
                            {
                                label = elevator.label .. ' - ' .. floor.label,
                                icon = 'fas fa-elevator',
                                onSelect = function()
                                    OnFloorInteract(elevRef, floorRef)
                                end,
                            },
                        },
                    })
                    activeZones[#activeZones + 1] = zoneName
                end
            end
        end
    end
end

-- ─── Marker Fallback (if not using ox_target) ───────────

if Config.InteractionMethod == 'marker' then
    CreateThread(function()
        while true do
            Wait(0)
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local nearFloor = nil
            local nearElevator = nil
            local nearDistSq = 6.25 -- 2.5^2

            for _, elevator in ipairs(elevatorList) do
                for _, floor in ipairs(elevator.floors) do
                    local point = floor.interactionPoint or floor.position
                    if type(point) == 'string' then
                        point = SafeJsonDecode(point) or {}
                    end
                    if point and point.x then
                        local distSq = DistSq3D(pos.x, pos.y, pos.z, point.x, point.y, point.z)
                        if distSq < nearDistSq then
                            nearDistSq = distSq
                            nearFloor = floor
                            nearElevator = elevator

                            DrawMarker(Config.MarkerType, point.x, point.y, point.z - 0.95,
                                0, 0, 0, 0, 0, 0,
                                Config.MarkerScale.x, Config.MarkerScale.y, Config.MarkerScale.z,
                                Config.MarkerColor.r, Config.MarkerColor.g, Config.MarkerColor.b, Config.MarkerColor.a,
                                false, false, 2, false, nil, nil, false)
                        end
                    end
                end
            end

            if nearFloor and nearElevator then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringKeyboardDisplay('~g~[E]~w~ ' .. nearElevator.label)
                EndTextCommandDisplayHelp(0, false, false, -1)

                if IsControlJustReleased(0, 38) then
                    OnFloorInteract(nearElevator, nearFloor)
                end
            end

            if not nearFloor then
                Wait(500)
            end
        end
    end)
end

-- ─── Floor Interaction ──────────────────────────────────

function OnFloorInteract(elevator, currentFloor)
    if isNuiOpen then return end

    -- Client-side cooldown check (visual only, server enforces real)
    if GetGameTimer() < clientCooldown then
        lib.notify({
            title = 'Aufzug',
            description = 'Bitte warten...',
            type = 'error',
            duration = 2000,
        })
        return
    end

    currentElevator = elevator

    _openNui('elevator', {
        elevator = elevator,
        currentFloor = currentFloor,
    })
end

-- ─── Teleport Result Handler ────────────────────────────

RegisterNetEvent('webcom_elevators:cl:teleportResult', function(ok, reason, data)
    if ok and data and data.position then
        -- Close NUI immediately
        _closeNui()

        -- Set client cooldown
        clientCooldown = GetGameTimer() + (currentElevator and currentElevator.cooldownMs or Config.Cooldown.DefaultMs)

        -- Perform fade-to-black teleport
        DoTeleport(data.position, data.floorLabel, data.elevatorLabel)
    else
        -- Send error to NUI
        local msg = _translateReason(reason)
        if data and data.remaining then
            local secs = math.ceil(data.remaining / 1000)
            msg = msg .. ' (' .. secs .. 's)'
        end
        SendNUIMessage({
            type = 'teleportError',
            reason = reason,
            message = msg,
        })
    end
end)

-- ─── Teleport with Fade-to-Black ────────────────────────

function DoTeleport(position, floorLabel, elevatorLabel)
    local ped = PlayerPedId()

    -- Fade out
    DoScreenFadeOut(Config.Teleport.FadeDurationMs)
    Wait(Config.Teleport.FadeDurationMs)

    -- Teleport
    SetEntityCoords(ped, position.x, position.y, position.z, false, false, false, false)
    if position.h then
        SetEntityHeading(ped, position.h)
    end

    -- Hold black screen briefly
    Wait(Config.Teleport.HoldDurationMs)

    -- Fade in
    DoScreenFadeIn(Config.Teleport.FadeDurationMs)

    -- Arrival sound
    if Config.Teleport.ArrivalSound then
        PlaySoundFrontend(-1, Config.Teleport.SoundName, Config.Teleport.SoundRef, true)
    end

    -- Notify
    lib.notify({
        title = elevatorLabel or 'Aufzug',
        description = floorLabel or 'Angekommen',
        type = 'success',
        duration = 3000,
    })
end

-- ─── NUI Bridge ─────────────────────────────────────────

function _openNui(view, data)
    isNuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        type = 'open',
        view = view,
        data = data or {},
    })
end

function _closeNui()
    isNuiOpen = false
    isAdminOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
    currentElevator = nil
end

-- ─── Reason Translation ─────────────────────────────────

function _translateReason(reason)
    local reasons = {
        invalid_floor      = 'Ungültige Etage',
        invalid_elevator   = 'Ungültiger Aufzug',
        cooldown           = 'Bitte warten',
        pin_required       = 'PIN erforderlich',
        wrong_pin          = 'Falsche PIN',
        password_required  = 'Passwort erforderlich',
        wrong_password     = 'Falsches Passwort',
        wrong_job          = 'Kein Zugang (Job)',
        insufficient_rank  = 'Rang nicht ausreichend',
        missing_item       = 'Benötigtes Item fehlt',
        unknown_protection = 'Unbekannter Schutz',
        invalid_protection = 'Schutzkonfiguration fehlerhaft',
    }
    return reasons[reason] or reason or 'Unbekannter Fehler'
end

-- ─── Resource Cleanup ───────────────────────────────────

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end

    -- Remove all zones
    for _, zoneName in ipairs(activeZones) do
        pcall(function() exports.ox_target:removeZone(zoneName) end)
    end

    -- Close NUI
    if isNuiOpen then
        _closeNui()
    end
end)
