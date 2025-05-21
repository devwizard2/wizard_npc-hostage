local followingPeds = {}
local hostagedPeds = {}

-- Blacklisted ped models
local blacklistedModels = {
    [`a_m_m_farmer_01`] = true,
    [`csb_tomcasino`] = true,
    [`a_m_m_business_01`] = true,
    [`a_m_m_business_02`] = true,
    [`s_m_m_doctor_01`] = true,
    [`ig_claypain`] = true,
}

function isBlacklistedPed(ped)
    local model = GetEntityModel(ped)
    return blacklistedModels[model] or false
end

function isHuman(ped)
    local pedType = GetPedType(ped)
    return pedType == 4 or pedType == 5
end

function isArmed()
    local weapon = GetSelectedPedWeapon(PlayerPedId())
    return weapon ~= `WEAPON_UNARMED`
end

function loadAnim(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(0) end
end

function handsUp(ped)
    loadAnim("missminuteman_1ig_2")
    TaskPlayAnim(ped, "missminuteman_1ig_2", "handsup_base", 8.0, -8, -1, 49, 0, false, false, false)
end

function DisableSeatShuffle(vehicle)
    if GetPedInVehicleSeat(vehicle, 0) == PlayerPedId() then
        SetPedConfigFlag(PlayerPedId(), 184, true)
    end
end

function DisableVehicleSeat(vehicle, seatIndex)
    CreateThread(function()
        while DoesEntityExist(vehicle) do
            SetVehicleDoorCanBreak(vehicle, 0, false)
            DisableSeatShuffle(vehicle)
            SetPedCanBeDraggedOut(PlayerPedId(), false)
            SetVehicleExclusiveDriver(vehicle, PlayerPedId(), true)
            SetVehicleDoorsLockedForNonScriptPlayers(vehicle, true)
            Wait(1000)
        end
    end)
end

function registerTarget(ped)
    if not NetworkGetEntityIsNetworked(ped) then
        NetworkRegisterEntityAsNetworked(ped)
    end

    local pedNet = PedToNet(ped)
    if pedNet == 0 then return end

    local id = 'hostage:' .. pedNet

    hostagedPeds[pedNet] = hostagedPeds[pedNet] or { following = false, owner = GetPlayerServerId(PlayerId()) }

    exports.ox_target:addLocalEntity(ped, {
        {
            label = 'Let Go',
            icon = 'fa-solid fa-person-walking-dashed-line-arrow-right',
            name = id .. ':letgo',
            onSelect = function()
                if hostagedPeds[pedNet].owner ~= GetPlayerServerId(PlayerId()) then return end

                ClearPedTasksImmediately(ped)
                FreezeEntityPosition(ped, false)
                SetBlockingOfNonTemporaryEvents(ped, false)
                TaskSmartFleePed(ped, PlayerPedId(), 100.0, -1, false, false)
                SetPedFleeAttributes(ped, 0, true)
                SetPedKeepTask(ped, true)
                followingPeds[pedNet] = nil
                hostagedPeds[pedNet] = nil
                exports.ox_target:removeLocalEntity(ped, id .. ':letgo')
                exports.ox_target:removeLocalEntity(ped, id .. ':follow')
            end
        },
        {
            label = hostagedPeds[pedNet].following and 'Stop Following' or 'Follow',
            icon = 'fa-solid fa-person-walking-arrow-loop-left',
            name = id .. ':follow',
            onSelect = function()
                if hostagedPeds[pedNet].owner ~= GetPlayerServerId(PlayerId()) then return end

                if hostagedPeds[pedNet].following then
                    ClearPedTasks(ped)
                    Wait(500)
                    ClearPedTasks(ped)
                    TaskStandStill(ped, -1)
                    handsUp(ped)
                    hostagedPeds[pedNet].following = false
                    followingPeds[pedNet] = nil
                else
                    ClearPedTasks(ped)
                    FreezeEntityPosition(ped, false)
                    TaskFollowToOffsetOfEntity(ped, PlayerPedId(), 0.0, -1.0, 0.0, 3.0, -1, 1.0, true)
                    SetPedMoveRateOverride(ped, 1.1)
                    SetPedPathCanUseLadders(ped, false)
                    SetPedPathCanUseClimbovers(ped, true)
                    hostagedPeds[pedNet].following = true
                    followingPeds[pedNet] = ped
                end

                exports.ox_target:removeLocalEntity(ped, id .. ':follow')
                registerTarget(ped)
            end
        }
    })
end

CreateThread(function()
    while true do
        Wait(500)
        local player = PlayerPedId()
        if isArmed() then
            local coords = GetEntityCoords(player)
            for _, ped in pairs(GetGamePool('CPed')) do
                if DoesEntityExist(ped)
                and not IsPedAPlayer(ped)
                and not IsPedDeadOrDying(ped)
                and #(GetEntityCoords(ped) - coords) < 7.0
                and isHuman(ped)
                and not isBlacklistedPed(ped) then

                    if not NetworkGetEntityIsNetworked(ped) then
                        NetworkRegisterEntityAsNetworked(ped)
                    end

                    local pedNet = PedToNet(ped)

                    -- ? Prevent other players from taking over
                    if hostagedPeds[pedNet] and hostagedPeds[pedNet].owner ~= GetPlayerServerId(PlayerId()) then
                        goto continue
                    end

                    if HasEntityClearLosToEntity(player, ped, 17) and IsPlayerFreeAimingAtEntity(PlayerId(), ped) then
                        if IsPedInAnyVehicle(ped, false) then
                            local veh = GetVehiclePedIsIn(ped, false)
                            TaskLeaveVehicle(ped, veh, 0)
                            while IsPedInAnyVehicle(ped, false) do Wait(100) end
                        end

                        ClearPedTasksImmediately(ped)
                        SetBlockingOfNonTemporaryEvents(ped, true)
                        FreezeEntityPosition(ped, true)
                        SetPedFleeAttributes(ped, 0, false)
                        TaskStandStill(ped, -1)
                        handsUp(ped)
                        hostagedPeds[pedNet] = { following = false, owner = GetPlayerServerId(PlayerId()) }
                        registerTarget(ped)
                    end
                end
                ::continue::
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)

        local player = PlayerPedId()
        local veh = GetVehiclePedIsIn(player, false)

        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == player then
            for netId, ped in pairs(followingPeds) do
                if DoesEntityExist(ped)
                and not IsPedInAnyVehicle(ped, false)
                and not IsPedGettingIntoAVehicle(ped)
                and not IsPedDeadOrDying(ped, true) then

                    local seatCount = GetVehicleModelNumberOfSeats(GetEntityModel(veh))
                    for seat = 0, seatCount - 2 do
                        if IsVehicleSeatFree(veh, seat) then
                            TaskEnterVehicle(ped, veh, 10000, seat, 1.0, 1, 0)
                            break
                        end
                    end
                end
            end
        end
    end
end)

CreateThread(function()
    local wasInVehicle = false
    local lastVehicle = nil

    while true do
        Wait(500)

        local player = PlayerPedId()
        local inVehicle = IsPedInAnyVehicle(player, false)

        if inVehicle then
            local veh = GetVehiclePedIsIn(player, false)
            if GetPedInVehicleSeat(veh, -1) == player then
                wasInVehicle = true
                lastVehicle = veh
            end
        elseif wasInVehicle and lastVehicle ~= nil then
            for netId, ped in pairs(followingPeds) do
                if DoesEntityExist(ped)
                and IsPedInAnyVehicle(ped, false)
                and GetVehiclePedIsIn(ped, false) == lastVehicle then
                    TaskLeaveVehicle(ped, lastVehicle, 0)

                    CreateThread(function()
                        while IsPedInAnyVehicle(ped, false) do
                            Wait(100)
                        end

                        TaskStandStill(ped, -1)
                        FreezeEntityPosition(ped, true)
                        handsUp(ped)

                        local pedNet = PedToNet(ped)
                        if hostagedPeds[pedNet] then
                            hostagedPeds[pedNet].following = false
                        end
                        followingPeds[pedNet] = nil
                        registerTarget(ped)
                    end)
                end
            end

            SetVehicleExclusiveDriver(lastVehicle, 0, false)
            SetVehicleDoorsLockedForNonScriptPlayers(lastVehicle, false)

            wasInVehicle = false
            lastVehicle = nil
        end
    end
end)

local expectedResourceName = "wizard_npc-hostage"
local currentResourceName = GetCurrentResourceName()
if currentResourceName ~= expectedResourceName then
print("^1Resource renamed! Change it as it was! |wizard_npc-hostage|^0")
Citizen.Wait(5000)
return
end
