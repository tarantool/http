local t = require('luatest')
local http_client = require('http.client')

local helpers = require('test.helpers')

local g = t.group()

g.after_each(function()
    helpers.teardown(g.httpd)
end)

g.before_test('test_keepalive_is_allowed', function()
    g.httpd = helpers.cfgserv()
    g.httpd:start()
end)

g.test_keepalive_is_allowed = function()
    local conn_is_opened = false
    local conn_is_closed = false
    g.httpd.internal.preprocess_client_handler = function() conn_is_opened = true end
    g.httpd.internal.postprocess_client_handler = function() conn_is_closed = true end

    -- Set HTTP keepalive headers: Connection:Keep-Alive and
    -- Keep-Alive:timeout=<keepalive_idle>. Otherwise HTTP client will send
    -- "Connection:close".
    local opts = {
        keepalive_idle = 3600,
        keepalive_interval = 3600,
    }
    local r = http_client.new():request('GET', helpers.base_uri .. '/test', nil, opts)
    t.assert_equals(r.status, 200)
    t.assert_equals(r.headers.connection, 'keep-alive')
    t.assert_equals(conn_is_opened, true)
    t.assert_equals(conn_is_closed, false) -- Connection is alive.
end

g.before_test('test_keepalive_is_disallowed', function()
    g.useragent = 'Mozilla/4.0'
    g.httpd = helpers.cfgserv({
        disable_keepalive = { g.useragent },
    })
    g.httpd:start()
end)

g.test_keepalive_is_disallowed = function()
    local conn_is_opened = false
    local conn_is_closed = false
    g.httpd.internal.preprocess_client_handler = function() conn_is_opened = true end
    g.httpd.internal.postprocess_client_handler = function() conn_is_closed = true end

    -- Set HTTP keepalive headers: Connection:Keep-Alive and
    -- Keep-Alive:timeout=<keepalive_idle>. Otherwise HTTP client will send
    -- "Connection:close".
    local opts = {
        headers = {
            ['user-agent'] = g.useragent,
        },
        keepalive_idle = 3600,
        keepalive_interval = 3600,
    }
    local r = http_client.new():request('GET', helpers.base_uri .. '/test', nil, opts)
    t.assert_equals(r.status, 200)
    t.assert_equals(r.headers.connection, 'close')
    t.assert_equals(conn_is_opened, true)
    t.assert_equals(conn_is_closed, true) -- Connection is closed.
end

g.before_test('test_disable_keepalive_is_set', function()
    g.useragent = 'Mozilla/5.0'
    g.httpd = helpers.cfgserv({
        disable_keepalive = { g.useragent },
    })
    g.httpd:start()
end)

g.test_disable_keepalive_is_set = function(g)
    local httpd = g.httpd
    t.assert_equals(httpd.disable_keepalive[g.useragent], true)
end

g.before_test('test_disable_keepalive_default', function()
    g.httpd = helpers.cfgserv()
    g.httpd:start()
end)

g.test_disable_keepalive_default = function(g)
    local httpd = g.httpd
    t.assert_equals(table.getn(httpd.options.disable_keepalive), 0)
end

g.before_test('test_idle_timeout_default', function()
    g.httpd = helpers.cfgserv()
    g.httpd:start()
end)

g.test_idle_timeout_default = function(g)
    local httpd = g.httpd
    t.assert_equals(httpd.options.idle_timeout, 0)
end

g.before_test('test_idle_timeout_is_set', function()
    g.idle_timeout = 0.5
    g.httpd = helpers.cfgserv({
        idle_timeout = g.idle_timeout,
    })
    g.httpd:start()
end)

g.test_idle_timeout_is_set = function(g)
    local conn_is_opened = false
    local conn_is_closed = false
    local httpd = g.httpd
    g.httpd.internal.preprocess_client_handler = function() conn_is_opened = true end
    g.httpd.internal.postprocess_client_handler = function() conn_is_closed = true end

    t.assert_equals(httpd.options.idle_timeout, g.idle_timeout)

    -- Set HTTP keepalive headers: Connection:Keep-Alive and
    -- Keep-Alive:timeout=<keepalive_idle>. Otherwise HTTP client will send
    -- "Connection:close".
    local opts = {
        keepalive_idle = 3600,
        keepalive_interval = 3600,
    }
    local r = http_client.new():request('GET', helpers.base_uri .. '/test', nil, opts)
    t.assert_equals(r.status, 200)
    t.assert_equals(r.headers.connection, 'keep-alive')
    t.assert_equals(conn_is_opened, true)

    helpers.retrying({
        timeout = g.idle_timeout * 2,
    }, function()
        assert(conn_is_closed, 'connection is closed')
    end)
    t.assert_equals(conn_is_closed, true) -- Connection is closed.
end

g.before_test('test_idle_timeout_is_unset', function()
    g.httpd = helpers.cfgserv({})
    g.httpd:start()
end)

g.test_idle_timeout_is_unset = function(g)
    local conn_is_opened = false
    local conn_is_closed = false
    g.httpd.internal.preprocess_client_handler = function() conn_is_opened = true end
    g.httpd.internal.postprocess_client_handler = function() conn_is_closed = true end

    -- Set HTTP keepalive headers: Connection:Keep-Alive and
    -- Keep-Alive:timeout=<keepalive_idle>. Otherwise HTTP client will send
    -- "Connection:close".
    local opts = {
        keepalive_idle = 3600,
        keepalive_interval = 3600,
    }
    local r = http_client.new():request('GET', helpers.base_uri .. '/test', nil, opts)

    -- The server should not close the connection during the keepalive_idle
    -- seconds. We could check that server will close connection after
    -- keepalive_idle seconds, but HTTP server under test does not support
    -- "Keep-Alive: timeout=NUM" header.

    t.assert_equals(r.status, 200)
    t.assert_equals(r.headers.connection, 'keep-alive')
    t.assert_equals(conn_is_opened, true)
    t.assert_equals(conn_is_closed, false) -- Connection is alive.
end
