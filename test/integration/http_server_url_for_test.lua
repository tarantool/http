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

g.test_server_url_for = function()
    local httpd = g.httpd
    t.assert_equals(httpd:url_for('abcdef'), '/abcdef', '/abcdef')
    t.assert_equals(httpd:url_for('test'), '/abc//', '/abc//')
    t.assert_equals(httpd:url_for('test', { cde = 'cde_v', def = 'def_v' }),
                   '/abc/cde_v/def_v', '/abc/cde_v/def_v')
    t.assert_equals(httpd:url_for('star', { def = '/def_v' }),
                   '/abb/def_v/cde', '/abb/def_v/cde')
    t.assert_equals(httpd:url_for('star', { def = '/def_v' }, { a = 'b', c = 'd' }),
                   '/abb/def_v/cde?a=b&c=d', '/abb/def_v/cde?a=b&c=d')
end
