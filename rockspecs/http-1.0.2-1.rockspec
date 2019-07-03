package = 'http'
version = '1.0.2-1'
source  = {
    url    = 'git://github.com/get-net/http.git',
    branch = 'request-change',
    tag    = 'request-change'
}
description = {
    summary  = "HTTP server for Tarantool",
    homepage = 'https://github.com/get-net/http/',
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
        ['http.lib'] = {
            sources = 'http/lib.c',
            incdirs = {
                "$(TARANTOOL_INCDIR)"
            }
        },
        ['http.server'] = 'http/server.lua',
        ['http.mime_types'] = 'http/mime_types.lua',
        ['http.codes'] = 'http/codes.lua',
    }
}

-- vim: syntax=lua
