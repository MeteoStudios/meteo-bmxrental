Bridge = {}

if GetFramework() == 'qbox' then
    function Bridge.GetCitizenId(src)
        local player = exports.qbx_core:GetPlayer(src)
        return player and player.PlayerData.citizenid
    end

    function Bridge.GetMoney(src, account)
        return exports.qbx_core:GetMoney(src, account) or 0
    end

    function Bridge.RemoveMoney(src, account, amount, reason)
        return exports.qbx_core:RemoveMoney(src, account, amount, reason) == true
    end

    function Bridge.AddMoney(src, account, amount, reason)
        return exports.qbx_core:AddMoney(src, account, amount, reason) == true
    end

    function Bridge.HasPermission(src, permission)
        return IsPlayerAceAllowed(src, permission)
    end

    function Bridge.Notify(src, msg, type)
        exports.qbx_core:Notify(src, msg, type == 'primary' and 'inform' or type)
    end

    function Bridge.GetPlayers()
        local list = {}
        for src in pairs(exports.qbx_core:GetQBPlayers()) do list[#list + 1] = src end
        return list
    end
else
    local QBCore = exports['qb-core']:GetCoreObject()

    function Bridge.GetCitizenId(src)
        local player = QBCore.Functions.GetPlayer(src)
        return player and player.PlayerData.citizenid
    end

    function Bridge.GetMoney(src, account)
        local player = QBCore.Functions.GetPlayer(src)
        return player and player.Functions.GetMoney(account) or 0
    end

    function Bridge.RemoveMoney(src, account, amount, reason)
        local player = QBCore.Functions.GetPlayer(src)
        return player ~= nil and player.Functions.RemoveMoney(account, amount, reason) == true
    end

    function Bridge.AddMoney(src, account, amount, reason)
        local player = QBCore.Functions.GetPlayer(src)
        return player ~= nil and player.Functions.AddMoney(account, amount, reason) == true
    end

    function Bridge.HasPermission(src, permission)
        return QBCore.Functions.HasPermission(src, permission)
    end

    function Bridge.Notify(src, msg, type)
        TriggerClientEvent('QBCore:Notify', src, msg, type)
    end

    function Bridge.GetPlayers()
        local list = {}
        for src in pairs(QBCore.Functions.GetQBPlayers()) do list[#list + 1] = src end
        return list
    end
end

function Bridge.OnPlayerLoaded(cb)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        cb(player.PlayerData.source, player.PlayerData.citizenid)
    end)
end

function Bridge.OnPlayerUnload(cb)
    AddEventHandler('QBCore:Server:OnPlayerUnload', cb)
end
