local t = require('luatest')
local g = t.group()
local http_client = require('http.client')

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
