Bridge = {}

if GetFramework() == 'qbox' then
    function Bridge.Notify(msg, type)
        exports.qbx_core:Notify(msg, type == 'primary' and 'inform' or type)
    end
else
    local QBCore = exports['qb-core']:GetCoreObject()

    function Bridge.Notify(msg, type)
        QBCore.Functions.Notify(msg, type)
    end
end

function Bridge.OnPlayerLoaded(cb)
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', cb)
end

function Bridge.OnPlayerUnload(cb)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', cb)
end

function Bridge.IsLoggedIn()
    return LocalPlayer.state.isLoggedIn
end
