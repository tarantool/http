local t = require('luatest')
local g = t.group()
local http_client = require('http.client')
local json = require('json')

local helper = require('test.helper')

g.before_each(function()
    local server, router = helper.cfgserv()
    g.server = server
    g.router = router
    g.server:start()
end)

g.after_each(function()
    g.server:stop()
end)

g.test_route_priority_any = function()
    g.router:route({ path = 'test/*any', method = 'GET' }, function() return {body = 'any'} end)
    t.assert_equals(http_client.get(helper.base_uri .. 'test/some').body, 'any')

    g.router:route({ path = 'test/some', method = 'GET'}, function () return  {body = 'some'} end)
    t.assert_equals(http_client.get(helper.base_uri .. 'test/some').body, 'some')
end

g.test_route_priority_stash = function()
    g.router:route({method = 'GET', path = '*stashname'}, function(_)
        return {
            status = 200,
            body = 'GET *',
        }
    end)
    local r = http_client.get(helper.base_uri .. 'a/b/c')

    t.assert_equals(r.status, 200, '/a/b/c request returns 200')
    t.assert_equals(r.body, 'GET *', 'GET * matches')

    g.router:route({method = 'ANY', path = '/a/:foo/:bar'}, function(_)
        return {
            status = 200,
            body = 'ANY /a/:foo/:bar',
        }
    end)
    r = http_client.get(helper.base_uri .. 'a/b/c')

    t.assert_equals(r.status, 200, '/a/b/c request returns 200')
    t.assert_equals(
        r.body,
        'ANY /a/:foo/:bar',
        '# of stashes matched doesnt matter - only # of known symbols by the route matters'
    )
end

g.test_server_url_match = function()
    t.assert_type(g.server, 'table')
    t.assert_is(g.router:match('GET', '/'), nil)
    t.assert_equals(g.router:match('GET', '/abc').endpoint.path, "/abc", "/abc")
    t.assert_equals(#g.router:match('GET', '/abc').stash, 0, "/abc")
    t.assert_equals(g.router:match('GET', '/abc/123').endpoint.path, "/abc/:cde", "/abc/123")
    t.assert_equals(g.router:match('GET', '/abc/123').stash.cde, "123", "/abc/123")
    t.assert_equals(g.router:match('GET', '/abc/123/122').endpoint.path, "/abc/:cde/:def",
        "/abc/123/122")
    t.assert_equals(g.router:match('GET', '/abc/123/122').stash.def, "122",
        "/abc/123/122")
    t.assert_equals(g.router:match('GET', '/abc/123/122').stash.cde, "123",
        "/abc/123/122")
    t.assert_equals(g.router:match('GET', '/abc_123-122').endpoint.path, "/abc_:cde_def",
        "/abc_123-122")
    t.assert_equals(g.router:match('GET', '/abc_123-122').stash.cde_def, "123-122",
        "/abc_123-122")
    t.assert_equals(g.router:match('GET', '/abc-123-def').endpoint.path, "/abc-:cde-def",
        "/abc-123-def")
    t.assert_equals(g.router:match('GET', '/abc-123-def').stash.cde, "123",
        "/abc-123-def")
    t.assert_equals(g.router:match('GET', '/aba-123-dea/1/2/3').endpoint.path,
        "/aba*def", '/aba-123-dea/1/2/3')
    t.assert_equals(g.router:match('GET', '/aba-123-dea/1/2/3').stash.def,
        "-123-dea/1/2/3", '/aba-123-dea/1/2/3')
    t.assert_equals(g.router:match('GET', '/abb-123-dea/1/2/3/cde').endpoint.path,
        "/abb*def/cde", '/abb-123-dea/1/2/3/cde')
    t.assert_equals(g.router:match('GET', '/abb-123-dea/1/2/3/cde').stash.def,
        "-123-dea/1/2/3", '/abb-123-dea/1/2/3/cde')
    t.assert_equals(g.router:match('GET', '/banners/1wulc.z8kiy.6p5e3').stash.token,
        '1wulc.z8kiy.6p5e3', "stash with dots")
end

g.test_server_url_for = function()
    t.assert_equals(g.router:url_for('abcdef'), '/abcdef', '/abcdef')
    t.assert_equals(g.router:url_for('test'), '/abc//', '/abc//')
    t.assert_equals(g.router:url_for('test', { cde = 'cde_v', def = 'def_v' }),
        '/abc/cde_v/def_v', '/abc/cde_v/def_v')
    t.assert_equals(g.router:url_for('star', { def = '/def_v' }),
        '/abb/def_v/cde', '/abb/def_v/cde')
    t.assert_equals(g.router:url_for('star', { def = '/def_v' }, { a = 'b', c = 'd' }),
        '/abb/def_v/cde?a=b&c=d', '/abb/def_v/cde?a=b&c=d')
end

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
        path = '/.*',
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

    local r = http_client.get(
        'http://127.0.0.1:12345/fruits/apple'
    )
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
