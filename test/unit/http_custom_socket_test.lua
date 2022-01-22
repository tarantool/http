local t = require('luatest')
local http_server = require('http.server')

local g = t.group()

g.test_custom_socket = function()
    local is_listening = false

    local function tcp_server(host, port, opts)
        assert(type(opts) == 'table')
        local name = opts.name
        local accept_handler = opts.handler
        local http_server = opts.http_server

        -- Verify arguments.
        t.assert_equals(host, 'host', 'check host')
        t.assert_equals(port, 123, 'check port')

        -- Verify options.
        t.assert_equals(name, 'http', 'check server name')
        t.assert_type(accept_handler, 'function', 'check accept handler')
        t.assert_type(http_server.routes, 'table',
            'http server object is accessible')

        is_listening = true
        return {
            close = function(self)
                is_listening = false
            end
        }
    end

    local myhttp = http_server.new('host', 123)
    myhttp.tcp_server_f = tcp_server
    myhttp:route({path = '/abc'}, function(_) end)
    myhttp:start()
    t.assert_equals(is_listening, true, 'custom socket is actually used')

    -- The key reason why the field is called `tcp_server_f` is
    -- that the HTTP server sets `myhttp.tcp_server` to the TCP
    -- server object. The name clash is harmless for the module,
    -- but may confuse a user, so the `tcp_server_f` was chosen
    -- instead of just `tcp_server`. The `tcp_server_f` field is
    -- guaranteed to remains the same after `myhttp:start()`.
    t.assert_equals(myhttp.tcp_server_f, tcp_server,
        'tcp_server_f field was not changed after :start()')

    myhttp:stop()
    t.assert_equals(is_listening, false, 'custom socket was closed')
end
