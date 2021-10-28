package = 'http'
version = 'scm-1'
source  = {
    url    = 'git://github.com/tarantool/http.git',
    branch = 'master',
}
description = {
    summary  = "HTTP server for Tarantool",
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
