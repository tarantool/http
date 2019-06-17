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
        ['http.server'] = 'http/server/init.lua',
        ['http.server.tsgi_adapter'] = 'http/server/tsgi_adapter.lua',
        ['http.nginx_server'] = 'http/nginx_server/init.lua',
        ['http.router'] = 'http/router/init.lua',
        ['http.router.fs'] = 'http/router/fs.lua',
        ['http.router.matching'] = 'http/router/matching.lua',
        ['http.router.middleware'] = 'http/router/middleware.lua',
        ['http.router.request'] = 'http/router/request.lua',
        ['http.router.response'] = 'http/router/response.lua',
        ['http.router.trie'] = 'http/router/trie.lua',
        ['http.tsgi'] = 'http/tsgi.lua',
        ['http.utils'] = 'http/utils.lua',
        ['http.mime_types'] = 'http/mime_types.lua',
        ['http.codes'] = 'http/codes.lua',
    }
}

-- vim: syntax=lua
