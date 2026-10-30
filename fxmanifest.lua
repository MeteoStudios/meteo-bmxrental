fx_version 'cerulean'
game 'gta5'

name 'meteo-bmxrental'
description 'BMX rental docks with animated delivery and return'
author 'Meteo Studios'
version '1.0.0'
copyright 'Copyright (c) 2026 Meteo Studios. All rights reserved.'
-- Website: https://meteostudios.net
-- Discord: https://discord.gg/9kMhSUfuRm

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/utils.lua',
}

client_scripts {
    'bridge/cl_bridge.lua',
    'client/cl_main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/sv_bridge.lua',
    'server/sv_main.lua',
}

files {
    'locales/*.json',
}

data_file 'DLC_ITYP_REQUEST' 'stream/meteo_prop_bmxdock.ytyp'

lua54 'yes'

escrow_ignore {
    'shared/config.lua',
    -- source access
    '*.lua',
    'bridge/*.lua',
    'client/*.lua',
    'server/*.lua',
    'shared/*.lua',
}
