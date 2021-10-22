local t = require('luatest')
local http_client = require('http.client')
local http_server = require('http.server')

local helpers = require('test.helpers')

local g = t.group()

g.before_test('test_server_custom_logger', function()
    g.httpd = http_server.new(helpers.base_host, helpers.base_port, {
        log_requests = helpers.custom_logger.info,
        log_errors = helpers.custom_logger.error
    })
    g.httpd:route({
        path='/'
    }, function(_) end)
    g.httpd:route({
        path='/error'
    }, function(_) error('Some error...') end)
    g.httpd:start()
end)

g.after_test('test_server_custom_logger', function()
    helpers.teardown(g.httpd)
end)

g.before_test('test_log_errors_off', function()
    g.httpd = http_server.new(helpers.base_host, helpers.base_port, {
        log_errors = false
    })
    g.httpd:start()
end)

g.after_test('test_log_errors_off', function()
    helpers.teardown(g.httpd)
end)

g.before_test('test_route_custom_logger', function()
    g.httpd = http_server.new(helpers.base_host, helpers.base_port, {
        log_requests = true,
        log_errors = true
    })
    g.httpd:start()
end)

g.after_test('test_route_custom_logger', function()
    helpers.teardown(g.httpd)
end)

g.before_test('test_log_requests_off', function()
    g.httpd = http_server.new(helpers.base_host, helpers.base_port, {
        log_requests = false
    })
    g.httpd:start()
end)

g.after_test('test_log_requests_off', function()
    helpers.teardown(g.httpd)
end)

-- Setting log option for server instance.
g.test_server_custom_logger = function()
    http_client.get(helpers.base_uri)
    t.assert_equals(helpers.find_msg_in_log_queue('GET /'), {
        log_lvl = 'info',
        msg = 'GET /'
    }, "Route should logging requests in custom logger if it's presents")
    helpers.clear_log_queue()

    http_client.get(helpers.base_uri .. '/error')
    --[[
    t.assert_str_contains(helpers.find_msg_in_log_queue('Some error...', false),
        "Route should logging error in custom logger if it's presents")
    ]]
    helpers.clear_log_queue()
end

-- Setting log options for route.
g.test_log_options = function()
    local httpd = http_server.new(helpers.base_host, helpers.base_port, {
        log_requests = true,
        log_errors = false
    })
    local dummy_logger = function() end

    local ok, err = pcall(httpd.route, httpd, {
        path = '/',
        log_requests = 3
    })
    t.assert_equals(ok, false, "Route logger can't be a log_level digit")
    t.assert_str_contains(err, "'log_requests' option should be a function",
        'route() should return error message in case of incorrect logger option')

    ok, err = pcall(httpd.route, httpd, {
        path = '/',
        log_requests = {
            info = dummy_logger
        }
    })
    t.assert_equals(ok, false, "Route logger can't be a table")
    t.assert_str_contains(err, "'log_requests' option should be a function",
        'route() should return error message in case of incorrect logger option')

    local ok, err = pcall(httpd.route, httpd, {
        path = '/',
        log_errors = 3
    })
    t.assert_equals(ok, false, "Route error logger can't be a log_level digit")
    t.assert_str_contains(err, "'log_errors' option should be a function",
        "route() should return error message in case of incorrect logger option")

    ok, err = pcall(httpd.route, httpd, {
        path = '/',
        log_errors = {
            error = dummy_logger
        }
    })
    t.assert_equals(ok, false, "Route error logger can't be a table")
    t.assert_str_contains(err, "'log_errors' option should be a function",
        'route() should return error message in case of incorrect log_errors option')
end

-- Log output with custom loggers on route.
g.test_route_custom_logger = function()
    local httpd = g.httpd
    httpd:route({
        path = '/',
        log_requests = helpers.custom_logger.info,
        log_errors = helpers.custom_logger.error
    }, function(_) end)
    http_client.get(helpers.base_uri)
    t.assert_equals(helpers.find_msg_in_log_queue('GET /'), {
        log_lvl = 'info',
        msg = 'GET /'
    }, "Route should logging requests in custom logger if it's presents")
    helpers.clear_log_queue()

    httpd.routes = {}
    httpd:route({
        path = '/',
        log_requests = helpers.custom_logger.info,
        log_errors = helpers.custom_logger.error
    }, function(_)
        error('User business logic exception...')
    end)
    http_client.get('127.0.0.1:12345')
    --test:is_deeply(helpers.find_msg_in_log_queue('GET /'), {
    --  log_lvl = 'info',
    --  msg = 'GET /'
    --}, "Route should logging request and error in case of route exception")
    --test:ok(helpers.find_msg_in_log_queue('User business logic exception...', false),
    --        "Route should logging error custom logger if it's presents in case of route exception")
    helpers.clear_log_queue()
end

-- Log route requests with turned off 'log_requests' option.
g.test_log_requests_off = function()
    local httpd = g.httpd
    httpd:route({
        path = '/',
        log_requests = helpers.custom_logger.info
    }, function(_) end)
    http_client.get(helpers.base_uri)
    --test:is_deeply(helpers.find_msg_in_log_queue('GET /'), {
    --  log_lvl = 'info',
    --  msg = 'GET /'
    --}, "Route can override logging requests if the http server have turned off 'log_requests' option")
    helpers.clear_log_queue()
end

-- Log route requests with turned off 'log_errors' option.
g.test_log_errors_off = function()
    local httpd = g.httpd
    httpd:route({
        path = '/',
        log_errors = helpers.custom_logger.error
    }, function(_)
        error('User business logic exception...')
    end)
    http_client.get(helpers.base_uri)
    --t.assert_str_contains(helpers.find_msg_in_log_queue('User business logic exception...', false),
    --    "Route can override logging requests if the http server have turned off 'log_errors' option")
    helpers.clear_log_queue()
end
