local docks = {}
local points = {}
local wanted = {}
local pads = {}
local blips = {}
local animEnts = {}
local delivered = {}
local restPose

local isLoaded, isAdmin, hasRental, placing = false, false, false, false

local PLACE_DISTANCE = 25.0
local PLACE_BLOCKED = { 14, 15, 24, 25, 36, 257, 263 }

local function notify(msg, type)
    Bridge.Notify(msg, type or 'primary')
end

local function loadModel(name)
    local hash = type(name) == 'number' and name or joaat(name)
    if not IsModelInCdimage(hash) then return end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function loadDict()
    RequestAnimDict(Dock.dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(Dock.dict) and GetGameTimer() < timeout do Wait(0) end
    return HasAnimDictLoaded(Dock.dict)
end

local function removeAnimEnt(entity)
    animEnts[entity] = nil
    if DoesEntityExist(entity) then DeleteEntity(entity) end
end

local function bikeBone(pod)
    local idx = GetEntityBoneIndexByName(pod, 'bike')
    return idx == -1 and 4 or idx
end

local function playAndWait(pod, clip)
    PlayEntityAnim(pod, clip, Dock.dict, 1000.0, false, true, false, 0.0, 0)
    Wait(Dock.clipMs[clip] + 50)
end

local function shiftZ(entity, dz)
    if not DoesEntityExist(entity) then return end
    local c = GetEntityCoords(entity)
    SetEntityCoordsNoOffset(entity, c.x, c.y, c.z + dz, false, false, false)
end

local function spawnPod(dock)
    local hash = loadModel(Dock.pod)
    if not hash then return end
    local pod = CreateObjectNoOffset(hash, dock.x, dock.y, dock.z, false, false, false)
    SetEntityRotation(pod, dock.rx, dock.ry, dock.rz, 2, true)
    FreezeEntityPosition(pod, true)
    SetEntityCollision(pod, false, false)
    SetModelAsNoLongerNeeded(hash)
    animEnts[pod] = true
    return pod
end

local function paint(veh, colors)
    if type(colors) ~= 'table' then return end
    SetVehicleColours(veh, colors[1] or 0, colors[2] or 0)
    SetVehicleExtraColours(veh, colors[3] or 0, colors[4] or 0)
end

local function spawnCopy(model, coords, heading, colors)
    local hash = loadModel(model)
    if not hash then return end
    local copy = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, false, false)
    SetModelAsNoLongerNeeded(hash)
    paint(copy, colors)
    SetEntityCollision(copy, false, false)
    FreezeEntityPosition(copy, true)
    animEnts[copy] = true
    return copy
end

local function onPad(pad, entity, radius)
    local c, q = GetEntityCoords(pad), GetEntityCoords(entity)
    return #(q.xy - c.xy) < radius and math.abs(q.z - c.z) < 2.0
end

local function hatchBlocked(pad)
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if onPad(pad, veh, 0.9) then return true end
    end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if onPad(pad, ped, 0.8) then return true end
    end
    return false
end

local function spawnRealBike(id, model, copy, colors)
    local hash = loadModel(model)
    if not hash then return end

    local pos, rot = GetEntityCoords(copy), GetEntityRotation(copy, 2)
    local veh = CreateVehicle(hash, pos.x, pos.y, pos.z, rot.z, true, false)
    SetModelAsNoLongerNeeded(hash)

    local timeout = GetGameTimer() + 2000
    while not NetworkGetEntityIsNetworked(veh) and GetGameTimer() < timeout do Wait(0) end
    if not NetworkGetEntityIsNetworked(veh) then
        DeleteEntity(veh)
        return
    end

    SetEntityCoordsNoOffset(veh, pos.x, pos.y, pos.z, false, false, false)
    SetEntityRotation(veh, rot.x, rot.y, rot.z, 2, true)
    FreezeEntityPosition(veh, true)
    paint(veh, colors)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    TriggerServerEvent('meteo-bmxrental:server:delivered', id, NetworkGetNetworkIdFromEntity(veh))
end

RegisterNetEvent('meteo-bmxrental:client:deliver', function(id, model, renter, colors)
    local dock, pad = docks[id], pads[id]
    if not dock or not pad then return end
    delivered[id] = nil

    local pod = loadDict() and spawnPod(dock)
    local copy = pod and spawnCopy(model, vec3(dock.x, dock.y, dock.z - 1.0), dock.rz, colors)
    if not copy then
        if pod then removeAnimEnt(pod) end
        return
    end

    AttachEntityToEntity(copy, pod, bikeBone(pod), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    playAndWait(pod, 'deliver_up')
    DetachEntity(copy, true, false)
    FreezeEntityPosition(copy, true)
    playAndWait(pod, 'deliver_down')
    removeAnimEnt(pod)

    shiftZ(copy, Config.bikeHeight)

    if DoesEntityExist(pad) then
        restPose = GetOffsetFromEntityGivenWorldCoords(pad, GetEntityCoords(copy))
    end

    if renter == cache.serverId then
        spawnRealBike(id, model, copy, colors)
        removeAnimEnt(copy)
    else

        CreateThread(function()
            local timeout = GetGameTimer() + 3000
            while GetGameTimer() < timeout do
                local netId = delivered[id]
                if netId and NetworkDoesNetworkIdExist(netId) and DoesEntityExist(NetToVeh(netId)) then break end
                Wait(100)
            end
            delivered[id] = nil
            removeAnimEnt(copy)
        end)
    end
end)

RegisterNetEvent('meteo-bmxrental:client:delivered', function(id, netId)
    delivered[id] = netId
end)

RegisterNetEvent('meteo-bmxrental:client:collect', function(id, model, flip, colors)
    local dock, pad = docks[id], pads[id]
    if not dock or not pad then return end

    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if Entity(veh).state[Dock.stateKey] and onPad(pad, veh, Dock.returnRadius + 0.5) then
            SetEntityVisible(veh, false, false)
            SetEntityCollision(veh, false, false)
        end
    end

    local offset = restPose or vec3(0.0, 0.0, Dock.bikeZ + Config.bikeHeight)
    local yaw = dock.rz + flip
    local at = GetOffsetFromEntityInWorldCoords(pad, offset.x, offset.y, offset.z)

    local pod = loadDict() and spawnPod(dock)
    local copy = pod and spawnCopy(model, at, yaw, colors)
    if not copy then
        if pod then removeAnimEnt(pod) end
        return
    end

    SetEntityCoordsNoOffset(copy, at.x, at.y, at.z, false, false, false)
    SetEntityRotation(copy, dock.rx, dock.ry, yaw, 2, true)
    playAndWait(pod, 'collect_up')

    shiftZ(copy, -Config.bikeHeight)

    local bone = bikeBone(pod)
    local rel = (yaw - GetEntityBoneRotation(pod, bone).z + 540.0) % 360.0 - 180.0
    local turn = math.abs(rel) > 90.0 and 180.0 or 0.0
    AttachEntityToEntity(copy, pod, bone, 0.0, 0.0, 0.0, 0.0, 0.0, turn, false, false, false, false, 2, true)
    playAndWait(pod, 'collect_down')
    removeAnimEnt(copy)
    removeAnimEnt(pod)
end)

RegisterNetEvent('meteo-bmxrental:client:ended', function()
    hasRental = false
end)

lib.onCache('vehicle', function(veh)
    if not veh then return end
    local state = Entity(veh).state[Dock.stateKey]
    if not state or state.owned then return end
    TriggerServerEvent('meteo-bmxrental:server:claim', VehToNet(veh))
end)

RegisterNetEvent('meteo-bmxrental:client:claimed', function(netId)
    hasRental = true
    local veh = NetToVeh(netId)
    if veh ~= 0 then FreezeEntityPosition(veh, false) end
end)

RegisterNetEvent('meteo-bmxrental:client:kick', function(netId)
    local veh = NetToVeh(netId)
    if veh ~= 0 and cache.vehicle == veh then TaskLeaveVehicle(cache.ped, veh, 0) end
end)

local function rent(id, index)
    local pad = pads[id]
    if not pad then return end
    if hatchBlocked(pad) then
        notify(locale('dock_blocked'), 'error')
        return
    end

    local ok, msg = lib.callback.await('meteo-bmxrental:server:rent', false, id, index)
    if ok then
        notify(locale('rent_started'), 'success')
    else
        notify(msg or locale('rent_failed'), 'error')
    end
end

local function openMenu(id)
    local options = {}
    for i, bike in ipairs(Config.bikes) do
        local price = bike.price or 0
        options[#options + 1] = {
            title = locale('menu_bike', bike.label, Config.currencySymbol, bike.deposit + price),
            description = locale('menu_cost', Config.currencySymbol, price, Config.currencySymbol, bike.deposit),
            icon = 'bicycle',
            image = bike.image or ('https://docs.fivem.net/vehicles/%s.webp'):format(bike.model),
            onSelect = function() rent(id, i) end,
        }
    end

    lib.registerContext({ id = 'meteo_bmxrental_menu', title = locale('menu_title'), options = options })
    lib.showContext('meteo_bmxrental_menu')
end

local function returnBike(id)
    local ok, msg = lib.callback.await('meteo-bmxrental:server:return', false, id)
    notify(msg or locale('return_failed'), ok and 'success' or 'error')
end

local function deleteDock(id)
    local answer = lib.alertDialog({
        header = locale('remove_confirm_title'),
        content = locale('remove_confirm_text', id),
        centered = true,
        cancel = true,
    })
    if answer ~= 'confirm' then return end

    if lib.callback.await('meteo-bmxrental:server:removeDock', false, id) then
        notify(locale('dock_removed'), 'success')
    end
end

local function targetOptions(id)
    return {
        {
            name = 'meteo_bmxrental_rent',
            icon = 'fas fa-bicycle',
            label = locale('target_rent'),
            distance = 2.0,
            canInteract = function() return not hasRental end,
            onSelect = function() openMenu(id) end,
        },
        {
            name = 'meteo_bmxrental_return',
            icon = 'fas fa-rotate-left',
            label = locale('target_return'),
            distance = 2.0,
            canInteract = function() return hasRental end,
            onSelect = function() returnBike(id) end,
        },
        {
            name = 'meteo_bmxrental_remove',
            icon = 'fas fa-trash',
            label = locale('target_remove'),
            distance = 2.0,
            canInteract = function() return isAdmin end,
            onSelect = function() deleteDock(id) end,
        },
    }
end

local function spawnPad(id)
    local dock = docks[id]
    if not dock or pads[id] then return end

    local hash = loadModel(Dock.pad)
    if not hash then
        DebugPrint('Pad model missing')
        return
    end

    if not wanted[id] or docks[id] ~= dock or pads[id] then return end

    local pad = CreateObjectNoOffset(hash, dock.x, dock.y, dock.z, false, false, false)
    SetEntityRotation(pad, dock.rx, dock.ry, dock.rz, 2, true)
    FreezeEntityPosition(pad, true)
    SetModelAsNoLongerNeeded(hash)

    exports.ox_target:addLocalEntity(pad, targetOptions(id))
    pads[id] = pad
    DebugPrint('Dock in range', id)
end

local function despawnPad(id)
    local pad = pads[id]
    if not pad then return end
    pcall(function() exports.ox_target:removeLocalEntity(pad) end)
    if DoesEntityExist(pad) then DeleteEntity(pad) end
    pads[id] = nil
    DebugPrint('Dock out of range', id)
end

local function createDock(id)
    local dock = docks[id]

    local point = lib.points.new({
        coords = vec3(dock.x, dock.y, dock.z),
        distance = Config.renderDistance,
    })
    function point:onEnter()
        wanted[id] = true
        CreateThread(function() spawnPad(id) end)
    end
    function point:onExit()
        wanted[id] = nil
        despawnPad(id)
    end
    points[id] = point

    if Config.blip.enabled then
        local blip = AddBlipForCoord(dock.x, dock.y, dock.z)
        SetBlipSprite(blip, Config.blip.sprite)
        SetBlipColour(blip, Config.blip.color)
        SetBlipScale(blip, Config.blip.scale + 0.0)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(locale('blip_name'))
        EndTextCommandSetBlipName(blip)
        blips[id] = blip
    end
end

local function teardownDock(id)
    wanted[id] = nil
    despawnPad(id)
    if points[id] then points[id]:remove() end
    if blips[id] and DoesBlipExist(blips[id]) then RemoveBlip(blips[id]) end
    points[id], blips[id], docks[id], delivered[id] = nil, nil, nil, nil
end

local function applyDocks(list)
    local seen = {}
    for _, dock in ipairs(list or {}) do
        seen[dock.id] = true
        if not docks[dock.id] then
            docks[dock.id] = dock
            createDock(dock.id)
        end
    end
    for id in pairs(docks) do
        if not seen[id] then teardownDock(id) end
    end
end

AddStateBagChangeHandler(Dock.globalKey, 'global', function(_, _, value)
    if isLoaded then applyDocks(value) end
end)

local function aimPoint()
    local cam = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local pitch = math.abs(math.cos(rx))
    local to = cam + vec3(-math.sin(rz) * pitch, math.cos(rz) * pitch, math.sin(rx)) * PLACE_DISTANCE
    local ray = StartShapeTestRay(cam.x, cam.y, cam.z, to.x, to.y, to.z, 17, cache.ped, 0)
    local _, hit, coords = GetShapeTestResult(ray)
    return hit == 1 or hit == true, coords
end

local wheelReadyAt = 0
local function wheelNotch()
    if GetGameTimer() < wheelReadyAt then return 0 end
    local notch = 0
    if IsControlPressed(0, 241) or IsDisabledControlPressed(0, 241) then
        notch = 1
    elseif IsControlPressed(0, 242) or IsDisabledControlPressed(0, 242) then
        notch = -1
    end
    if notch ~= 0 then wheelReadyAt = GetGameTimer() + 80 end
    return notch
end

local function placeDock()
    if placing then return end

    local hash = loadModel(Dock.pad)
    if not hash then return end

    placing = true
    local start = GetEntityCoords(cache.ped)
    local ghost = CreateObjectNoOffset(hash, start.x, start.y, start.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAlpha(ghost, 160, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)

    local heading, height = GetEntityHeading(cache.ped), 0.0
    local coords, rot, shown

    local function seat(at)
        SetEntityCoordsNoOffset(ghost, at.x, at.y, at.z, false, false, false)
        SetEntityRotation(ghost, 0.0, 0.0, heading, 2, true)
        PlaceObjectOnGroundProperly(ghost)
        if height ~= 0.0 then
            local c = GetEntityCoords(ghost)
            SetEntityCoordsNoOffset(ghost, c.x, c.y, c.z + height, false, false, false)
        end
    end

    while placing do
        Wait(0)

        DisablePlayerFiring(cache.playerId, true)
        for i = 1, #PLACE_BLOCKED do DisableControlAction(0, PLACE_BLOCKED[i], true) end

        local notch = wheelNotch()
        if notch ~= 0 then
            if IsControlPressed(0, 21) then
                height = height + notch * 0.05
            elseif IsDisabledControlPressed(0, 36) then
                heading = (heading + notch) % 360.0
            else
                heading = (heading + notch * 5.0) % 360.0
            end
        end

        local text = locale('place_help', math.floor(heading + 0.5) % 360, height)
        if text ~= shown then
            lib.showTextUI(text, { position = 'left-center' })
            shown = text
        end

        local hit, at = aimPoint()
        SetEntityVisible(ghost, hit, false)
        if hit then
            seat(at)
            if IsDisabledControlJustPressed(0, 24) then
                coords, rot = GetEntityCoords(ghost), GetEntityRotation(ghost, 2)
                break
            end
        end

        if IsControlJustReleased(0, 38) then
            seat(GetEntityCoords(cache.ped))
            coords, rot = GetEntityCoords(ghost), GetEntityRotation(ghost, 2)
            break
        end

        if IsDisabledControlJustPressed(0, 25) or IsControlJustReleased(0, 177) then break end
    end

    DeleteEntity(ghost)
    lib.hideTextUI()
    placing = false
    if not coords then return end

    if lib.callback.await('meteo-bmxrental:server:addDock', false, coords, rot) then
        notify(locale('dock_placed'), 'success')
    else
        notify(locale('dock_place_failed'), 'error')
    end
end

local function openDockMenu(id)
    local dock = docks[id]
    if not dock then return end

    lib.registerContext({
        id = 'meteo_bmxrental_dock',
        title = locale('manage_dock', id),
        menu = 'meteo_bmxrental_manage',
        options = {
            {
                title = locale('manage_teleport'),
                icon = 'location-arrow',
                onSelect = function()
                    local h = math.rad(dock.rz)
                    SetEntityCoords(cache.ped, dock.x + math.cos(h) * 1.5, dock.y + math.sin(h) * 1.5, dock.z, false, false, false, false)
                end,
            },
            {
                title = locale('manage_waypoint'),
                icon = 'map-pin',
                onSelect = function() SetNewWaypoint(dock.x, dock.y) end,
            },
            {
                title = locale('manage_remove'),
                icon = 'trash',
                iconColor = '#e03131',
                onSelect = function() deleteDock(id) end,
            },
        },
    })
    lib.showContext('meteo_bmxrental_dock')
end

local function openManage()
    if placing or not isLoaded then return end
    if not lib.callback.await('meteo-bmxrental:server:isAdmin', false) then
        notify(locale('no_permission'), 'error')
        return
    end

    local here = GetEntityCoords(cache.ped)
    local list = {}
    for id, dock in pairs(docks) do
        list[#list + 1] = { id = id, distance = #(here - vec3(dock.x, dock.y, dock.z)) }
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)

    local options = {
        {
            title = locale('manage_place'),
            icon = 'plus',
            onSelect = function() CreateThread(placeDock) end,
        },
    }
    for _, entry in ipairs(list) do
        options[#options + 1] = {
            title = locale('manage_dock', entry.id),
            description = locale('manage_distance', math.floor(entry.distance)),
            icon = 'bicycle',
            arrow = true,
            onSelect = function() openDockMenu(entry.id) end,
        }
    end

    lib.registerContext({ id = 'meteo_bmxrental_manage', title = locale('manage_title'), options = options })
    lib.showContext('meteo_bmxrental_manage')
end

RegisterCommand(Config.placeCommand, openManage, false)

local function initialize()
    if isLoaded then return end
    isLoaded = true
    isAdmin = lib.callback.await('meteo-bmxrental:server:isAdmin', false) == true
    applyDocks(GlobalState[Dock.globalKey])
end

local function cleanup()
    if placing then lib.hideTextUI() end
    isLoaded, hasRental, placing = false, false, false
    for id in pairs(docks) do teardownDock(id) end
    for entity in pairs(animEnts) do removeAnimEnt(entity) end
end

Bridge.OnPlayerLoaded(initialize)
Bridge.OnPlayerUnload(cleanup)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(1000)
    if Bridge.IsLoggedIn() then initialize() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanup()
end)
