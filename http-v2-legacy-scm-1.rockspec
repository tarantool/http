package = 'http-v2-legacy'
version = 'scm-1'
source  = {
    url    = 'git+https://github.com/tarantool/http.git',
    branch = 'http-v2-legacy',
}
description = {
    summary  = "HTTP v2 (legacy) server for Tarantool",
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
