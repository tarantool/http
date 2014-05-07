package = 'http'
version = 'scm-1'
source  = {
    url    = 'git://github.com/tarantool/http.git',
    branch = 'master',
}
description = {
    summary  = "Tarantool module for HTTP client/server.",
    homepage = 'https://github.com/tarantool/http/',
    license  = 'BSD',
}
dependencies = {
    'lua >= 5.1'
}
build = {
    type = 'builtin',

    modules = {
        ['box.http.lib'] = 'src/lib.c',
        ['box.http.client'] = 'src/client.lua',
        ['box.http.server'] = 'src/server.lua',
        ['box.http.mime_types'] = 'src/mime_types.lua',
        ['box.http.codes'] = 'src/codes.lua',
    },
    c99 = true,
}

-- vim: syntax=lua
