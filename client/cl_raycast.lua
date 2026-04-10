-- ═══════════════════════════════════════════════════════════
--  cl_raycast.lua – Raycast Point Selection for Admin
--  Uses an invisible ped as placement preview
-- ═══════════════════════════════════════════════════════════

local isSelecting = false
local selectionCallback = nil
local previewPed = 0
local previewModel = `mp_m_freemode_01`  -- male freemode ped

--- Start point selection mode (player aims crosshair, confirms with E)
--- Shows a transparent ped at the aimed position as preview
---@param cb function(coords) Called with selected coordinates or nil if cancelled
function StartPointSelection(cb)
    if isSelecting then return end
    isSelecting = true
    selectionCallback = cb

    CreateThread(function()
        -- Disable NUI while selecting
        SetNuiFocus(false, false)

        -- Load preview model
        RequestModel(previewModel)
        local t = 0
        while not HasModelLoaded(previewModel) and t < 3000 do Wait(10); t = t + 10 end

        -- Create preview ped (invisible to others, non-interactive)
        local playerPed = PlayerPedId()
        local pPos = GetEntityCoords(playerPed)
        previewPed = CreatePed(26, previewModel, pPos.x, pPos.y, pPos.z - 50.0, 0.0, false, false)
        SetModelAsNoLongerNeeded(previewModel)

        if DoesEntityExist(previewPed) then
            SetEntityAlpha(previewPed, 150, false)
            SetEntityInvincible(previewPed, true)
            SetBlockingOfNonTemporaryEvents(previewPed, true)
            FreezeEntityPosition(previewPed, true)
            SetEntityCollision(previewPed, false, false)
            SetPedCanRagdoll(previewPed, false)
            SetEntityCompletelyDisableCollision(previewPed, false, false)
        end

        while isSelecting do
            Wait(0)

            local hit, coords = _doRaycast()

            if hit and coords then
                local heading = GetEntityHeading(PlayerPedId())

                -- Move preview ped to aimed position
                if DoesEntityExist(previewPed) then
                    SetEntityCoords(previewPed, coords.x, coords.y, coords.z, false, false, false, false)
                    SetEntityHeading(previewPed, heading)
                    SetEntityAlpha(previewPed, 150, false)
                end

                -- Draw instruction
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringKeyboardDisplay('~g~[E]~w~ Position bestätigen  ~r~[Backspace]~w~ Abbrechen')
                EndTextCommandDisplayHelp(0, false, false, -1)

                -- E key = confirm
                if IsControlJustReleased(0, 38) then
                    isSelecting = false
                    _cleanupPreview()
                    if selectionCallback then
                        selectionCallback({
                            x = math.floor(coords.x * 100) / 100,
                            y = math.floor(coords.y * 100) / 100,
                            z = math.floor(coords.z * 100) / 100,
                            h = math.floor(heading * 100) / 100,
                        })
                    end
                    selectionCallback = nil
                    return
                end
            end

            -- Backspace = cancel
            if IsControlJustReleased(0, 177) then
                isSelecting = false
                _cleanupPreview()
                if selectionCallback then
                    selectionCallback(nil)
                end
                selectionCallback = nil
                return
            end
        end

        _cleanupPreview()
    end)
end

--- Cleanup preview ped
function _cleanupPreview()
    if DoesEntityExist(previewPed) then
        DeleteEntity(previewPed)
    end
    previewPed = 0
end

--- Cancel any active point selection
function CancelPointSelection()
    isSelecting = false
    _cleanupPreview()
    selectionCallback = nil
end

--- Is point selection active?
function IsSelectingPoint()
    return isSelecting
end

-- ─── Internal Raycast ───────────────────────────────────

function _doRaycast()
    local ped = PlayerPedId()
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)

    local forward = _rotToDir(camRot)
    local dest = camCoords + forward * 50.0

    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z,
        dest.x, dest.y, dest.z, 17, ped, 0)
    local _, hit, endCoords, _, _ = GetShapeTestResult(ray)

    return hit == 1, endCoords
end

function _rotToDir(rot)
    local rX = rot.x * math.pi / 180.0
    local rZ = rot.z * math.pi / 180.0
    local absX = math.abs(math.cos(rX))
    return vector3(
        -math.sin(rZ) * absX,
        math.cos(rZ) * absX,
        math.sin(rX)
    )
end
