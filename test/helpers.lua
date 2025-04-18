local fio = require('fio')
local http_server = require('http.server')
local socket = require('socket')

local helpers = table.copy(require('luatest').helpers)

local luatest = require('luatest')
local luatest_utils = require('luatest.utils')

helpers.base_port = 12345
helpers.base_host = '127.0.0.1'
helpers.base_uri = ('http://%s:%s'):format(helpers.base_host, helpers.base_port)
helpers.tls_uri = ('https://%s:%s'):format('localhost', helpers.base_port)

helpers.get_testdir_path = function()
    local path = os.getenv('LUA_SOURCE_DIR') or './'
    return fio.pathjoin(path, 'test')
end

helpers.cfgserv = function(opts)
    local path = helpers.get_testdir_path()

    local opts = opts or {}
    local opts = http_server.internal.extend({
        app_dir = path,
        log_requests = false,
        log_errors = false
    }, opts)

    local httpd = http_server.new(helpers.base_host, helpers.base_port, opts)
        :route({path = '/abc/:cde/:def', name = 'test'}, function() end)
        :route({path = '/abc'}, function() end)
        :route({path = '/ctxaction'}, 'module.controller#action')
        :route({path = '/absentaction'}, 'module.controller#absent')
        :route({path = '/absent'}, 'module.absent#action')
        :route({path = '/abc/:cde'}, function() end)
        :route({path = '/abc_:cde_def'}, function() end)
        :route({path = '/abc-:cde-def'}, function() end)
        :route({path = '/aba*def'}, function() end)
        :route({path = '/abb*def/cde', name = 'star'}, function() end)
        :route({path = '/banners/:token'})
        :helper('helper_title', function(self, a) return 'Hello, ' .. a end)
        :route({path = '/helper', file = 'helper.html.el'})
        :route({path = '/test', file = 'test.html.el' },
            function(cx) return cx:render({ title = 'title: 123' }) end)

    return httpd
end

local log_queue = {}

helpers.clear_log_queue = function()
    log_queue = {}
end

helpers.custom_logger = {
    debug = function() end,
    verbose = function()
        table.insert(log_queue, {
            log_lvl = 'verbose',
        })
    end,
    info = function(...)
        table.insert(log_queue, {
            log_lvl = 'info',
            msg = string.format(...)
        })
    end,
    warn = function(...)
        table.insert(log_queue, {
            log_lvl = 'warn',
            msg = string.format(...)
        })
    end,
    error = function(...)
        table.insert(log_queue, {
            log_lvl = 'error',
            msg = string.format(...)
        })
    end
}

helpers.find_msg_in_log_queue = function(msg, strict)
    for _, log in ipairs(log_queue) do
        if not strict then
            if log.msg:match(msg) then
                return log
            end
        else
            if log.msg == msg then
                return log
            end
        end
    end
end

helpers.teardown = function(httpd)
    local host = httpd.host
    local port = httpd.port
    httpd:stop()
    helpers.retrying({
        timeout = 1,
    }, function()
        local s, _ = socket.tcp_connect(host, port)
        if s ~= nil then
            s:close()
        end
        assert(s == nil, 'http server is stopped')
    end)
end

helpers.is_tarantool3 = function()
    local tarantool_version = luatest_utils.get_tarantool_version()
    return luatest_utils.version_ge(tarantool_version, luatest_utils.version(3, 0, 0))
end

helpers.skip_if_not_tarantool3 = function()
    luatest.skip_if(not helpers.is_tarantool3(), 'Only Tarantool 3 is supported')
end

helpers.update_lua_env_variables = function(server)
    local ROOT = fio.dirname(fio.dirname(fio.abspath(package.search('http.server'))))

    server.env.LUA_PATH = (server.env.LUA_PATH or '') ..
        ROOT .. '/?.lua;' .. ROOT .. '/?/?.lua;' ..
        ROOT .. '/.rocks/share/tarantool/?.lua;' ..
        ROOT .. '/.rocks/share/tarantool/?/init.lua;'
    server.env.LUA_CPATH = (server.env.LUA_CPATH or '') ..
        ROOT .. '/.rocks/lib/tarantool/?.so;' ..
        ROOT .. '/.rocks/lib/tarantool/?/?.so;'
end

return helpers
