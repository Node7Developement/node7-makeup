fx_version 'cerulean'
game 'rdr3'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'NODE7 Development Studios'
description 'Standalone Node7 makeup and native facial customization using barber chairs.'
version '1.6.0'

lua54 'yes'

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    'shared/features.lua',
    'shared/overlays.lua'
}

client_scripts {
    'client/cosmetics.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

files {
    'html/index.html',
    'html/reset.css',
    'html/style.css',
    'html/app.js',
    'data/beards.json'
}

dependencies {
    'node7-core',
    'oxmysql'
}
