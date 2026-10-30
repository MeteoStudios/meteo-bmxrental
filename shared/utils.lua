function DebugPrint(...)
    if not Config.debug then return end

    local msg = {}
    for _, v in ipairs({...}) do
        msg[#msg + 1] = tostring(v)
    end

    print('^6[METEO BMXRENTAL]^0 ' .. table.concat(msg, ', '))
end

function GetFramework()
    if Config.framework == 'qbox' or Config.framework == 'qbcore' then
        return Config.framework
    end
    if GetResourceState('qbx_core') == 'started' then return 'qbox' end
    return 'qbcore'
end

Dock = {
    pad = 'meteo_prop_bmxdock',
    pod = 'meteo_prop_bmxdock_pod',
    dict = 'meteo_prop_bmxdock_anim',
    clipMs = { deliver_up = 3667, deliver_down = 2333, collect_up = 2333, collect_down = 3600 },
    bikeZ = 0.3375,
    returnRadius = 1.5,
    stateKey = 'meteo_bmxrental',
    globalKey = 'meteo_bmxrental_docks',
}
