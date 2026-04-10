fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'webcom_elevators'
author 'WebCom'
description 'Elevator / Teleport System with Admin UI, Floor Protection & Dashboard Sync'
version '1.0.0'

dependency 'oxmysql'
dependency 'ox_lib'

webcom_module_name 'elevators'
webcom_module_version '1.0.0'
webcom_module_capabilities '["elevator.manage","elevator.admin"]'

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/enums.lua',
    'shared/utils.lua',
    'config.lua',
}

client_scripts {
    'client/cl_raycast.lua',
    'client/cl_admin.lua',
    'client/cl_nui.lua',
    'client/cl_dui.lua',
    'client/cl_elevator_dui.lua',
    'client/cl_main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_bridge.lua',
    'server/sv_cache.lua',
    'server/sv_permissions.lua',
    'server/sv_dashboard.lua',
    'server/sv_main.lua',
}

files {
    'html/index.html',
    'html/dui.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/dui/*.html',
}
