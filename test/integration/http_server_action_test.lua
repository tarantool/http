local fio = require('fio')
local fiber = require('fiber')
local socket = require('socket')
local t = require('luatest')
local http_client = require('http.client')
local http_server = require('http.server')

local helpers = require('test.helpers')

local g = t.group()

g.before_test('test_stop_basic', function()
    g.base_host = '127.0.0.1'
    g.base_port = 8080
    g.httpd = http_server.new(g.base_host, g.base_port, {
        app_dir = helpers.path,
    })
    g.httpd:start()
end)

g.after_test('test_stop_basic', function()
    helpers.retrying({}, function()
        local conn = socket.tcp_connect(g.base_host, g.base_port)
        return conn ~= nil
    end)
    fio.rmdir(helpers.path)
end)

g.before_test('test_stop_with_open_connection', function()
    g.base_host = '127.0.0.1'
    g.base_port = 8080
    g.base_uri = ('http://%s:%s'):format(g.base_host, g.base_port)
    g.httpd = http_server.new(g.base_host, g.base_port, {
        app_dir = helpers.path,
    })
    g.httpd:start()
end)

g.after_test('test_stop_with_open_connection', function()
    helpers.retrying({}, function()
        local r = http_client.request('GET', g.base_uri)
        return r == nil
    end)
    fio.rmdir(helpers.path)
end)

g.before_test('test_stop_with_custom_handler', function()
    g.base_host = '127.0.0.1'
    g.base_port = 8080
    g.base_uri = ('http://%s:%s'):format(g.base_host, g.base_port)
    g.httpd = http_server.new(g.base_host, g.base_port, {
        app_dir = helpers.path,
    })
    g.httpd:start()
end)

g.after_test('test_stop_with_custom_handler', function()
    helpers.retrying({}, function()
        local r = http_client.request('GET', g.base_uri)
        return r == nil
    end)
    fio.rmdir(helpers.path)
end)

g.test_stop_basic = function()
    local resp = g.httpd:stop()
    t.assert_not_equals(resp, nil)
    t.assert_type(resp, 'table')
    -- Make sure response is for http server that we started before.
    t.assert_equals(resp.port, g.base_port)
    t.assert_equals(resp.host, g.base_host)
end

g.test_stop_with_open_connection = function()
    local httpd = g.httpd
    httpd:route({
        method = 'GET',
        path = '/test/json',
    }, 'test#json')

    -- Open connection to the web server.
    local resp = http_client.get(g.base_uri)
    t.assert_not_equals(resp, nil)

    -- Stop server.
    resp = httpd:stop()
    t.assert_not_equals(resp, nil)
    t.assert_type(resp, 'table')
    -- Make sure response is for http server that we started before.
    t.assert_equals(resp.port, g.base_port)
    t.assert_equals(resp.host, g.base_host)
end

g.test_stop_with_custom_handler = function()
    g.httpd:route({
        path = '/'
    }, function ()
        return {
            status = 200, body = 'hello'
        }
    end)
    fiber.sleep(0.1)
    local resp = g.httpd:stop()
    -- Make sure response is for http server that we started before.
    t.assert_equals(resp.port, g.base_port)
    t.assert_equals(resp.host, g.base_host)
end
