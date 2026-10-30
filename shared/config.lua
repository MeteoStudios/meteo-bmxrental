Config = {}

Config.debug = false
Config.framework = 'auto'  -- 'auto', 'qbox', 'qbcore'

Config.adminPermission = 'admin'  -- can place and remove docks
Config.placeCommand = 'bmxdock'

Config.papersItem = 'meteo_bmxpapers'
Config.currencySymbol = '$'

Config.renderDistance = 20.0  -- dock prop spawns within this
Config.claimTime = 60         -- seconds to get on before it goes back
Config.bikeHeight = 0.15      -- lifts the bike onto the pad

Config.blip = {
    enabled = true,
    sprite = 226,
    color = 5,
    scale = 0.6,
}

-- Any bike that fits the pod works. price is kept, deposit comes back on return
Config.bikes = {
    { model = 'bmx', label = 'BMX', price = 25, deposit = 150 },
}
