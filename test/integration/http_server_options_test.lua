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
