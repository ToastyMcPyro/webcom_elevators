-- ═══════════════════════════════════════════════════════════
--  cl_admin.lua – Admin Panel (Command-based)
-- ═══════════════════════════════════════════════════════════

isAdminOpen = false

-- ─── Open Admin Panel ───────────────────────────────────

function OpenAdminPanel()
    if isAdminOpen then return end

    -- Request all elevator data from server
    TriggerServerEvent('webcom_elevators:sv:adminGetData')
end

-- Receive admin data → open NUI
RegisterNetEvent('webcom_elevators:cl:adminReceiveData', function(data)
    if isAdminOpen then
        -- Already open – just refresh data without resetting the tab
        SendNUIMessage({ type = 'adminData', data = data })
    else
        isAdminOpen = true
        _openNui('admin', data)
    end
end)

-- Admin operation result
RegisterNetEvent('webcom_elevators:cl:adminResult', function(ok, message)
    SendNUIMessage({
        type = 'adminResult',
        ok = ok,
        message = message,
    })

    -- Refresh admin data if successful
    if ok and isAdminOpen then
        TriggerServerEvent('webcom_elevators:sv:adminGetData')
    end
end)

-- Admin teleport to position
RegisterNetEvent('webcom_elevators:cl:adminTeleport', function(position)
    if not position or not position.x then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, position.x, position.y, position.z, false, false, false, false)
    if position.h then
        SetEntityHeading(ped, position.h)
    end
end)

-- ─── Point Selection Handlers (during Creator/Editor) ───

function HandleSelectPoint(pointType, context)
    -- Hide NUI temporarily
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'hide' })

    StartPointSelection(function(coords)
        -- Restore NUI
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'show' })

        if coords then
            SendNUIMessage({
                type = 'pointSelected',
                pointType = pointType,
                context = context,
                point = coords,
            })
        end
    end)
end

-- ─── Command Registration ───────────────────────────────

RegisterCommand(Config.AdminCommand, function()
    OpenAdminPanel()
end, false)

-- ─── Resource Cleanup ───────────────────────────────────

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    CancelPointSelection()
end)
