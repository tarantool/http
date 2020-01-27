local fio = require('fio')
local t = require('luatest')
local http_server = require('http.server')
local http_router = require('http.router')
local ngx_server = require('http.nginx_server')

local helper = {}

helper.base_port = 12345
helper.base_host = '127.0.0.1'
helper.base_uri = ('http://%s:%s/'):format(helper.base_host, helper.base_port)

helper.is_nginx_test = function ()
    local server_type = os.getenv('SERVER_TYPE') or 'builtin'
    return server_type:lower() == 'nginx'
end

helper.is_builtin_test = function ()
    return not helper.is_nginx_test()
end

local function choose_server()
    local log_requests = true
    local log_errors = true

    if helper.is_nginx_test() then
        -- host and port are for SERVER_NAME, SERVER_PORT only.
        -- TODO: are they required?

        return ngx_server.new({
            host = helper.base_host,
            port = helper.base_port,
            tnt_method = 'nginx_entrypoint',
            log_requests = log_requests,
            log_errors = log_errors,
        })
    end

    return http_server.new(helper.base_host, helper.base_port, {
        log_requests = log_requests,
        log_errors = log_errors
    })
end

helper.cfgserv = function ()
    local path = os.getenv('LUA_SOURCE_DIR') or './'
    path = fio.pathjoin(path, 'test')

    local httpd = choose_server()
    local router = http_router.new({app_dir = path})
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
                              :helper('helper_title', function(_, a) return 'Hello, ' .. a end)
                              :route({path = '/helper', file = 'helper.html.el'})
                              :route({ path = '/test', file = 'test.html.el' },
        function(cx) return cx:render({ title = 'title: 123' }) end)
    httpd:set_router(router)
    return httpd, router
end

t.before_suite(function()
    box.cfg{listen = '127.0.0.1:3301'}
    box.schema.user.grant(
        'guest', 'read,write,execute', 'universe', nil, {if_not_exists = true}
    )
end)

return helper
