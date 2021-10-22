local fio = require('fio')
local http_server = require('http.server')
local http_client = require('http.client')

local helpers = table.copy(require('luatest').helpers)

helpers.base_port = 12345
helpers.base_host = '127.0.0.1'
helpers.base_uri = ('http://%s:%s'):format(helpers.base_host, helpers.base_port)

helpers.cfgserv = function()
    local path = os.getenv('LUA_SOURCE_DIR') or './'
    path = fio.pathjoin(path, 'test')

    local httpd = http_server.new(helpers.base_host, helpers.base_port, {
        app_dir = path,
        log_requests = false,
        log_errors = false
    })
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
    httpd:stop()
    helpers.retrying({}, function()
        local r = http_client.request('GET', helpers.base_uri)
        return r == nil
    end)
end

return helpers
