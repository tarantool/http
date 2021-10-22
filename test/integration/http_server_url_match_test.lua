local t = require('luatest')

local helpers = require('test.helpers')

local g = t.group()

g.before_each(function()
    g.httpd = helpers.cfgserv()
    g.httpd:start()
end)

g.after_each(function()
    helpers.teardown(g.httpd)
end)

g.test_server_url_match = function()
    local httpd = g.httpd
    t.assert_type(httpd, 'table', 'httpd object')
    t.assert_not_equals(httpd, nil)
    t.assert_is(httpd:match('GET', '/'), nil)
    t.assert_equals(httpd:match('GET', '/abc').endpoint.path, '/abc', '/abc')
    t.assert_equals(#httpd:match('GET', '/abc').stash, 0, '/abc')
    t.assert_equals(httpd:match('GET', '/abc/123').endpoint.path, '/abc/:cde', '/abc/123')
    t.assert_equals(httpd:match('GET', '/abc/123').stash.cde, '123', '/abc/123')
    t.assert_equals(httpd:match('GET', '/abc/123/122').endpoint.path, '/abc/:cde/:def',
                   '/abc/123/122')
    t.assert_equals(httpd:match('GET', '/abc/123/122').stash.def, '122',
                   '/abc/123/122')
    t.assert_equals(httpd:match('GET', '/abc/123/122').stash.cde, '123',
                   '/abc/123/122')
    t.assert_equals(httpd:match('GET', '/abc_123-122').endpoint.path, '/abc_:cde_def',
                   '/abc_123-122')
    t.assert_equals(httpd:match('GET', '/abc_123-122').stash.cde_def, '123-122',
                   '/abc_123-122')
    t.assert_equals(httpd:match('GET', '/abc-123-def').endpoint.path, '/abc-:cde-def',
                   '/abc-123-def')
    t.assert_equals(httpd:match('GET', '/abc-123-def').stash.cde, '123',
                   '/abc-123-def')
    t.assert_equals(httpd:match('GET', '/aba-123-dea/1/2/3').endpoint.path,
                   '/aba*def', '/aba-123-dea/1/2/3')
    t.assert_equals(httpd:match('GET', '/aba-123-dea/1/2/3').stash.def,
                   '-123-dea/1/2/3', '/aba-123-dea/1/2/3')
    t.assert_equals(httpd:match('GET', '/abb-123-dea/1/2/3/cde').endpoint.path,
                   '/abb*def/cde', '/abb-123-dea/1/2/3/cde')
    t.assert_equals(httpd:match('GET', '/abb-123-dea/1/2/3/cde').stash.def,
                   '-123-dea/1/2/3', '/abb-123-dea/1/2/3/cde')
    t.assert_equals(httpd:match('GET', '/banners/1wulc.z8kiy.6p5e3').stash.token,
                   '1wulc.z8kiy.6p5e3', 'stash with dots')
end
