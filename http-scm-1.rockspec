package = 'http'
version = 'scm-1'
source  = {
    url    = 'git://github.com/tarantool/http.git',
    branch = 'master',
}
description = {
    summary  = "Tarantool module for HTTP client/server.",
    detailed = 'lalala',
    homepage = 'https://github.com/tarantool/http/',
    license  = 'lalala',
}
dependencies = {
    'lua >= 5.1'
}
build = {
    type = 'builtin',

    modules = {
        ['http.lib'] = 'src/lib.c',
        ['http.client'] = 'src/client.lua',
        ['http.server'] = 'src/server.lua',
        ['http.mime_types'] = 'src/mime_types.lua',
        ['http.codes'] = 'src/codes.lua',
    },
    c99 = true,
}

-- vim: syntax=lua
