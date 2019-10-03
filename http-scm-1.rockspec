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
    'lua >= 5.1',
    'checks >= 3.0.1',
}
external_dependencies = {
    TARANTOOL = {
        header = "tarantool/module.h"
    }
}
build = {
    type = 'cmake',

    variables = {
        version = 'scm-1',
        TARANTOOL_DIR = '$(TARANTOOL_DIR)',
        TARANTOOL_INSTALL_LIBDIR = '$(LIBDIR)',
        TARANTOOL_INSTALL_LUADIR = '$(LUADIR)',
    }
}

-- vim: syntax=lua
