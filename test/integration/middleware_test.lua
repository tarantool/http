local t = require('luatest')
local g = t.group()
local helper = require('test.helper')
local http_server = require('http.server')
local http_router = require('http.router')

local json = require('json')
local http_client = require('http.client')
local fio = require('fio')


g.before_each(function()
    g.server = http_server.new(helper.base_host, helper.base_port)
    g.router = http_router.new()
    g.server:set_router(g.router)
    g.server:start()
end)

g.after_each(function()
    g.server:stop()
end)

g.test_middleware = function()
    local add_helloworld_before_to_response = function(req)
        local resp = req:next()

        local lua_body = json.decode(resp.body)
        lua_body.message = 'hello world! (before)'
        resp.body = json.encode(lua_body)

        return resp
    end

    local add_helloworld_to_response = function(req)
        local resp = req:next()

        local lua_body = json.decode(resp.body)
        lua_body.message = 'hello world!'
        resp.body = json.encode(lua_body)

        return resp
    end

    local ok = g.router:use(add_helloworld_to_response, {
        name = 'hello_world',
        method = {'GET', 'POST'},
    })
    t.assert(ok, 'hello_world middleware added successfully')

    local middlewares_ordered = g.router.middleware:ordered()
    t.assert_equals(#middlewares_ordered, 1, 'one middleware is registered')

    ok = g.router:use(add_helloworld_before_to_response, {
        name = 'hello_world_before',
        path = '/.*',
        method = 'ANY',
        before = 'hello_world',
    })
    t.assert(ok, 'hello_world_before middleware added successfully')

    middlewares_ordered = g.router.middleware:ordered()
    t.assert_equals(#middlewares_ordered, 2, 'both middlewares are registered')
    t.assert_equals(middlewares_ordered[1].name, 'hello_world_before',
        'hello_world_before is first')
    t.assert_equals(middlewares_ordered[2].name, 'hello_world',
        'hello_world is last')

    local apple_handler = function()
        return {status = 200, body = json.encode({kind = 'apple'})}
    end

    local orange_handler = function()
        return {status = 200, body = json.encode({kind = 'orange'})}
    end

    g.router:route(
        {
            method = 'GET',
            path = '/fruits/apple',
        },
        apple_handler
    )
    g.router:route(
        {
            method = 'GET',
            path = '/fruits/orange',
        },
        orange_handler
    )

    local r = http_client.get(helper.base_uri .. 'fruits/apple')
    t.assert_equals(r.status, 200, 'status')
    require('log').info('DEBUG: /fruits/apple response: %s', r.body)
    local parsed_body = json.decode(r.body)
    t.assert_equals(parsed_body.kind, 'apple', 'body is correct')
    t.assert_equals(parsed_body.message, 'hello world! (before)', 'hello_world middleware invoked last')

    local function swap_orange_and_apple(req)
        local path_info = req['PATH_INFO']
        local log = require('log')
        log.info('swap_orange_and_apple: path_info = %s', path_info)

        if path_info == '/fruits/orange' then
            req['PATH_INFO'] = '/fruits/apple'
        elseif path_info == '/fruits/apple' then
            req['PATH_INFO'] = '/fruits/orange'
        end

        return req:next()
    end

    ok = g.router:use(swap_orange_and_apple, {
        preroute = true,
        name = 'swap_orange_and_apple',
    })
    t.assert(ok, 'swap_orange_and_apple middleware added successfully')

    r = http_client.get(
        'http://127.0.0.1:12345/fruits/apple'
    )
    t.assert_equals(r.status, 200, 'status')
    parsed_body = json.decode(r.body)
    t.assert_equals(parsed_body.kind, 'orange', 'route swapped from apple handler to orange')
end

g.test_middleware_routing = function()
    g.router:route({path = 'some_path'}, function() return {body = 'from_route', status = 200} end)
    g.router:use(function() return {body = 'middleware', status = 200} end)

    for _, path in ipairs({'/', 'some_path', 'abc'}) do
        local r = http_client.get(fio.pathjoin(helper.base_uri, path))
        t.assert_equals(r.status, 200, path)
        t.assert_equals(r.body, 'middleware', path)
    end
end

