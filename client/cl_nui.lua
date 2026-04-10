-- ═══════════════════════════════════════════════════════════
--  cl_nui.lua – NUI Callback Handlers
--  Routes NUI → Lua function calls
-- ═══════════════════════════════════════════════════════════

-- ─── Close UI ───────────────────────────────────────────

RegisterNUICallback('close', function(data, cb)
    _closeNui()
    CancelPointSelection()
    cb({ ok = true })
end)

-- ─── Floor Selection / Teleport ─────────────────────────

RegisterNUICallback('selectFloor', function(data, cb)
    if not data.floorId then return cb({ ok = false }) end
    -- Direct teleport (no protection or already validated)
    TriggerServerEvent('webcom_elevators:sv:requestTeleport', data.floorId, data.inputData or {})
    cb({ ok = true })
end)

RegisterNUICallback('submitPin', function(data, cb)
    if not data.floorId or not data.pin then return cb({ ok = false }) end
    -- Validate PIN via callback, then teleport
    local valid = lib.callback.await('webcom_elevators:validatePin', false, data.floorId, data.pin)
    if valid then
        TriggerServerEvent('webcom_elevators:sv:requestTeleport', data.floorId, { pin = data.pin })
    end
    cb({ ok = true, valid = valid })
end)

RegisterNUICallback('submitPassword', function(data, cb)
    if not data.floorId or not data.password then return cb({ ok = false }) end
    local valid = lib.callback.await('webcom_elevators:validatePassword', false, data.floorId, data.password)
    if valid then
        TriggerServerEvent('webcom_elevators:sv:requestTeleport', data.floorId, { password = data.password })
    end
    cb({ ok = true, valid = valid })
end)

-- ─── Admin: Group CRUD ──────────────────────────────────

RegisterNUICallback('createGroup', function(data, cb)
    if not data.name then return cb({ ok = false }) end
    TriggerServerEvent('webcom_elevators:sv:createGroup', data)
    cb({ ok = true })
end)

RegisterNUICallback('updateGroup', function(data, cb)
    if not data.id then return cb({ ok = false }) end
    TriggerServerEvent('webcom_elevators:sv:updateGroup', data.id, {
        label = data.label,
        description = data.description,
        color = data.color,
    })
    cb({ ok = true })
end)

RegisterNUICallback('deleteGroup', function(data, cb)
    if not data.id then return cb({ ok = false }) end
    TriggerServerEvent('webcom_elevators:sv:deleteGroup', data.id)
    cb({ ok = true })
end)

-- ─── Admin: Elevator CRUD ───────────────────────────────

RegisterNUICallback('createElevator', function(data, cb)
    if not data.name then return cb({ ok = false }) end
    TriggerServerEvent('webcom_elevators:sv:createElevator', data)
    cb({ ok = true })
end)

RegisterNUICallback('updateElevator', function(data, cb)
    if not data.id then return cb({ ok = false }) end
    TriggerServerEvent('webcom_elevators:sv:updateElevator', data.id, data)
    cb({ ok = true })
end)

RegisterNUICallback('deleteElevator', function(data, cb)
    if not data.id then return cb({ ok = false }) end
    TriggerServerEvent('webcom_elevators:sv:deleteElevator', data.id)
    cb({ ok = true })
end)

RegisterNUICallback('toggleElevator', function(data, cb)
    if not data.id then return cb({ ok = false }) end
    TriggerServerEvent('webcom_elevators:sv:toggleElevator', data.id)
    cb({ ok = true })
end)

-- ─── Admin: Floor CRUD ──────────────────────────────────

RegisterNUICallback('addFloor', function(data, cb)
    if not data.elevatorId or not data.floor then return cb({ ok = false }) end
    TriggerServerEvent('webcom_elevators:sv:addFloor', data.elevatorId, data.floor)
    cb({ ok = true })
end)

RegisterNUICallback('updateFloor', function(data, cb)
    if not data.id then return cb({ ok = false }) end
    TriggerServerEvent('webcom_elevators:sv:updateFloor', data.id, data)
    cb({ ok = true })
end)

RegisterNUICallback('deleteFloor', function(data, cb)
    if not data.id then return cb({ ok = false }) end
    TriggerServerEvent('webcom_elevators:sv:deleteFloor', data.id)
    cb({ ok = true })
end)

-- ─── Admin: Point Selection ─────────────────────────────

RegisterNUICallback('selectPoint', function(data, cb)
    HandleSelectPoint(data.pointType or 'position', data.context or {})
    cb({ ok = true })
end)

-- ─── Admin: Teleport to Position ────────────────────────

RegisterNUICallback('adminTeleport', function(data, cb)
    if not data.position then return cb({ ok = false }) end
    TriggerServerEvent('webcom_elevators:sv:adminTeleport', data.position)
    cb({ ok = true })
end)

-- ─── Admin: Refresh Data ────────────────────────────────

RegisterNUICallback('adminRefresh', function(data, cb)
    TriggerServerEvent('webcom_elevators:sv:adminGetData')
    cb({ ok = true })
end)
