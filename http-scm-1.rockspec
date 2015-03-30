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
        ['http.lib'] = 'http/lib.c',
        ['http.client'] = 'http/client.lua',
        ['http.server'] = 'http/server.lua',
        ['http.mime_types'] = 'http/mime_types.lua',
        ['http.codes'] = 'http/codes.lua',
        ['http.plugins.msgpack'] = 'plugins/msgpack.lua',
        ['http.plugins.json'] = 'plugins/json.lua',
        ['http.plugins.jsonrpc'] = 'plugins/jsonrpc.lua',
    }
}

-- vim: syntax=lua
