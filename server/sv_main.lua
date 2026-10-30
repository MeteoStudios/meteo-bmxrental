local docks = {}
local busy = {}
local pending = {}
local bikes = {}
local rentals = {}

local function notify(src, msg, type)
    Bridge.Notify(src, msg, type or 'primary')
end

local function isAdmin(src)
    return Bridge.HasPermission(src, Config.adminPermission)
end

local function dockCoords(dock)
    return vec3(dock.x, dock.y, dock.z)
end

local function nearDock(src, dock, range)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - dockCoords(dock)) <= range
end

local function publishDocks()
    local list = {}
    for _, dock in pairs(docks) do list[#list + 1] = dock end
    GlobalState[Dock.globalKey] = list
end

local function broadcast(dock, event, ...)
    local at = dockCoords(dock)
    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped ~= 0 and #(GetEntityCoords(ped) - at) <= Config.renderDistance + 20.0 then
            TriggerClientEvent(event, tonumber(id), ...)
        end
    end
end

local function removePapers(src, keepPlate)
    local ok, items = pcall(function()
        return exports.ox_inventory:Search(src, 'slots', Config.papersItem)
    end)
    if not ok or type(items) ~= 'table' then return end

    for _, item in pairs(items) do
        if not keepPlate or not item.metadata or item.metadata.plate ~= keepPlate then
            exports.ox_inventory:RemoveItem(src, Config.papersItem, item.count, nil, item.slot)
        end
    end
end

local function canAfford(src, amount)
    return Bridge.GetMoney(src, 'cash') >= amount or Bridge.GetMoney(src, 'bank') >= amount
end

local function takePayment(src, amount)
    for _, account in ipairs({ 'cash', 'bank' }) do
        if Bridge.GetMoney(src, account) >= amount and Bridge.RemoveMoney(src, account, amount, 'bmx-rental') then
            return account
        end
    end
end

local function total(bike)
    return bike.price + bike.deposit
end

local function hasLiveRental(cid)
    local bike = rentals[cid]
    return bike ~= nil and bike.entity ~= nil and DoesEntityExist(bike.entity)
end

local function endBike(bike, refund, deleteDelay)
    if bike.ended then return end
    bike.ended = true

    local entity = bike.entity
    if entity then
        bikes[entity] = nil
        if deleteDelay then
            SetTimeout(deleteDelay, function()
                if DoesEntityExist(entity) then DeleteEntity(entity) end
            end)
        elseif DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end

    local owner = bike.owner
    if owner then
        if rentals[owner.cid] == bike then rentals[owner.cid] = nil end

        if Bridge.GetCitizenId(owner.source) == owner.cid then
            removePapers(owner.source)
            if refund and refund > 0 then
                Bridge.AddMoney(owner.source, owner.account, refund, 'bmx-rental-refund')
            end
            TriggerClientEvent('meteo-bmxrental:client:ended', owner.source)
        end
    end

    DebugPrint('Bike ended', bike.plate, 'refund', refund or 0)
end

local function sameModel(entity, model)
    return GetEntityModel(entity) % 0x100000000 == joaat(model) % 0x100000000
end

local function collect(bike, dock, refund)
    busy[dock.id] = true

    local yaw = (GetEntityHeading(bike.entity) - dock.rz + 540.0) % 360.0 - 180.0
    local flip = math.abs(yaw) > 90.0 and 180.0 or 0.0

    broadcast(dock, 'meteo-bmxrental:client:collect', dock.id, bike.model, flip, bike.colors)

    endBike(bike, refund, 200)

    SetTimeout(Dock.clipMs.collect_up + Dock.clipMs.collect_down + 500, function()
        busy[dock.id] = nil
    end)
end

local function checkClaim(bike)
    if bike.ended or bike.owner or not DoesEntityExist(bike.entity) then return end

    local dock = docks[bike.dock]
    if not dock then return end

    if GetPedInVehicleSeat(bike.entity, -1) ~= 0 or busy[dock.id] then
        SetTimeout(5000, function() checkClaim(bike) end)
        return
    end

    notify(bike.requester, locale('not_claimed'), 'error')
    collect(bike, dock)
end

local function deliver(bike, dock)
    broadcast(dock, 'meteo-bmxrental:client:deliver', dock.id, bike.model, bike.requester, bike.colors)

    Wait(Dock.clipMs.deliver_up + Dock.clipMs.deliver_down + 3000)

    if pending[dock.id] == bike then
        pending[dock.id] = nil
        notify(bike.requester, locale('rent_failed'), 'error')
    end
    busy[dock.id] = nil
end

RegisterNetEvent('meteo-bmxrental:server:delivered', function(dockId, netId)
    local src = source
    local bike = pending[dockId]
    local dock = docks[dockId]
    if type(netId) ~= 'number' or not bike or not dock or bike.requester ~= src then return end

    local entity = 0
    local timeout = GetGameTimer() + 2000
    repeat
        entity = NetworkGetEntityFromNetworkId(netId)
        if entity ~= 0 and DoesEntityExist(entity) then break end
        Wait(50)
    until GetGameTimer() > timeout
    if entity == 0 or not DoesEntityExist(entity) or bikes[entity] then return end

    if not sameModel(entity, bike.model) then return end

    if pending[dockId] ~= bike or #(GetEntityCoords(entity) - dockCoords(dock)) > 3.0 then
        DeleteEntity(entity)
        return
    end

    pending[dockId] = nil
    bike.entity = entity
    bikes[entity] = bike

    SetEntityOrphanMode(entity, 2)
    FreezeEntityPosition(entity, true)
    SetVehicleNumberPlateText(entity, bike.plate)
    Entity(entity).state:set(Dock.stateKey, { dock = dockId, plate = bike.plate }, true)

    broadcast(dock, 'meteo-bmxrental:client:delivered', dockId, netId)
    SetTimeout(Config.claimTime * 1000, function() checkClaim(bike) end)
    DebugPrint('Delivered', bike.plate, 'netId', netId)
end)

lib.callback.register('meteo-bmxrental:server:isAdmin', function(src)
    return isAdmin(src)
end)

lib.callback.register('meteo-bmxrental:server:rent', function(src, dockId, index)
    local cid = Bridge.GetCitizenId(src)
    local dock = docks[dockId]
    local config = Config.bikes[index]
    if not cid or not dock or not config or not nearDock(src, dock, 5.0) then return false end
    if busy[dockId] then return false, locale('dock_busy') end

    for _, bike in pairs(bikes) do
        if bike.dock == dockId and not bike.owner then return false, locale('bike_waiting') end
    end

    if hasLiveRental(cid) then return false, locale('already_renting') end

    local bike = {
        dock = dockId,
        requester = src,
        model = config.model,
        label = config.label,
        price = config.price or 0,
        deposit = config.deposit,
        plate = ('BMX%05d'):format(math.random(0, 99999)),

        colors = config.colors or { math.random(0, 159), math.random(0, 159), 0, 0 },
    }

    if not canAfford(src, total(bike)) then
        return false, locale('not_enough_money', Config.currencySymbol, total(bike))
    end

    pending[dockId] = bike
    busy[dockId] = true

    DebugPrint('Requested', bike.plate, 'at dock', dockId, 'by', src)
    CreateThread(function() deliver(bike, dock) end)
    return true
end)

RegisterNetEvent('meteo-bmxrental:server:claim', function(netId)
    local src = source
    local entity = NetworkGetEntityFromNetworkId(netId)
    local bike = entity ~= 0 and bikes[entity]
    if not bike or bike.owner or bike.claiming then return end

    local ped = GetPlayerPed(src)
    local cid = Bridge.GetCitizenId(src)
    if not cid or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(entity)) > 5.0 then return end

    bike.claiming = true
    local account, reason
    if hasLiveRental(cid) then
        reason = locale('already_renting')
    else
        account = takePayment(src, total(bike))
        if not account then reason = locale('not_enough_money', Config.currencySymbol, total(bike)) end
    end
    bike.claiming = nil

    if reason or bike.ended then
        if account then Bridge.AddMoney(src, account, total(bike), 'bmx-rental-refund') end
        if reason then notify(src, reason, 'error') end
        TriggerClientEvent('meteo-bmxrental:client:kick', src, netId)
        return
    end

    if rentals[cid] then endBike(rentals[cid]) end

    bike.owner = { cid = cid, source = src, account = account }
    rentals[cid] = bike
    FreezeEntityPosition(entity, false)
    Entity(entity).state:set(Dock.stateKey, { dock = bike.dock, plate = bike.plate, owned = true }, true)

    local given, why = exports.ox_inventory:AddItem(src, Config.papersItem, 1, {
        plate = bike.plate,
        description = locale('papers_description', bike.label, bike.plate, Config.currencySymbol, bike.deposit),
    })

    if not given then DebugPrint('Papers not given:', why) end

    TriggerClientEvent('meteo-bmxrental:client:claimed', src, netId)
    notify(src, locale('claimed', Config.currencySymbol, total(bike), Config.currencySymbol, bike.deposit), 'success')
    DebugPrint('Claimed', bike.plate, 'by', src)
end)

lib.callback.register('meteo-bmxrental:server:return', function(src, dockId)
    local cid = Bridge.GetCitizenId(src)
    local dock = docks[dockId]
    if not cid or not dock or not nearDock(src, dock, 5.0) then return false end

    local bike = rentals[cid]
    if not bike then return false, locale('no_rental') end
    if busy[dockId] then return false, locale('dock_busy') end

    if not DoesEntityExist(bike.entity) then
        endBike(bike)
        return false, locale('bike_lost')
    end

    local pos = GetEntityCoords(bike.entity)
    if #(pos.xy - vec2(dock.x, dock.y)) > Dock.returnRadius or math.abs(pos.z - dock.z) > 2.0 then
        return false, locale('park_on_dock')
    end
    if GetPedInVehicleSeat(bike.entity, -1) ~= 0 then
        return false, locale('get_off_bike')
    end

    collect(bike, dock, bike.deposit)
    return true, locale('returned', Config.currencySymbol, bike.deposit)
end)

lib.callback.register('meteo-bmxrental:server:addDock', function(src, coords, rot)
    if not isAdmin(src) then return false end
    if type(coords) ~= 'vector3' or type(rot) ~= 'vector3' then return false end

    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - coords) > 40.0 then return false end

    local id = MySQL.insert.await('INSERT INTO meteo_bmxrental_docks (x, y, z, rx, ry, rz) VALUES (?, ?, ?, ?, ?, ?)', {
        coords.x, coords.y, coords.z, rot.x, rot.y, rot.z,
    })
    if not id then return false end

    docks[id] = { id = id, x = coords.x, y = coords.y, z = coords.z, rx = rot.x, ry = rot.y, rz = rot.z }
    publishDocks()
    DebugPrint('Dock added', id)
    return true
end)

lib.callback.register('meteo-bmxrental:server:removeDock', function(src, dockId)
    if not isAdmin(src) or not docks[dockId] then return false end

    MySQL.query.await('DELETE FROM meteo_bmxrental_docks WHERE id = ?', { dockId })
    docks[dockId] = nil
    busy[dockId] = nil
    pending[dockId] = nil
    publishDocks()
    DebugPrint('Dock removed', dockId)
    return true
end)

AddEventHandler('entityRemoved', function(entity)
    local bike = bikes[entity]
    if not bike then return end

    if bike.owner then notify(bike.owner.source, locale('bike_lost'), 'error') end
    endBike(bike)
end)

local function endBySource(src)
    for _, bike in pairs(rentals) do
        if bike.owner.source == src then
            endBike(bike)
            return
        end
    end
end

Bridge.OnPlayerUnload(endBySource)

AddEventHandler('playerDropped', function()
    endBySource(source)
end)

Bridge.OnPlayerLoaded(function(src, cid)

    SetTimeout(5000, function()
        local bike = rentals[cid]
        removePapers(src, bike and bike.plate)
    end)
end)

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `meteo_bmxrental_docks` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `rx` DOUBLE NOT NULL DEFAULT 0,
            `ry` DOUBLE NOT NULL DEFAULT 0,
            `rz` DOUBLE NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    for _, row in ipairs(MySQL.query.await('SELECT * FROM meteo_bmxrental_docks') or {}) do
        docks[row.id] = { id = row.id, x = row.x, y = row.y, z = row.z, rx = row.rx, ry = row.ry, rz = row.rz }
    end
    publishDocks()

    for _, src in ipairs(Bridge.GetPlayers()) do
        removePapers(src)
    end

    DebugPrint('Loaded', #GlobalState[Dock.globalKey], 'docks')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, bike in pairs(bikes) do
        endBike(bike, bike.deposit)
    end
end)
