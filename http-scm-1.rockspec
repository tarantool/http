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
external_dependencies = {
    TARANTOOL = {
        header = "tarantool/module.h"
    }
}
build = {
    type = 'builtin',

    modules = {
        ['http.client'] = 'http/client.lua',
        ['http.codes'] = 'http/codes.lua',
        ['http.lib'] = {
            sources = 'http/lib.c',
            incdirs = {
                "$(TARANTOOL_INCDIR)"
            }
        },
        ['http.mime_types'] = 'http/mime_types.lua',
        ['http.plugins.json'] = 'plugins/json.lua',
        ['http.plugins.jsonrpc.client'] = 'plugins/jsonrpc/client.lua',
        ['http.plugins.jsonrpc.server'] = 'plugins/jsonrpc/server.lua',
        ['http.plugins.msgpack'] = 'plugins/msgpack.lua',
        ['http.server'] = 'http/server.lua',
    }
}

-- vim: syntax=lua
