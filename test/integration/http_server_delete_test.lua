local t = require('luatest')
local http_client = require('http.client')

local helpers = require('test.helpers')

local g = t.group()

g.before_each(function()
    g.httpd = helpers.cfgserv({
        display_errors = true,
    })
    g.httpd:start()
end)

g.after_each(function()
    helpers.teardown(g.httpd)
end)

g.test_delete = function()
    local httpd = g.httpd
    httpd:route({
        path = '/content_type',
        name = 'content_type',
    }, function()
        return {
            status = 200,
        }
    end)

    local r = http_client.get(helpers.base_uri .. '/content_type')
    t.assert_equals(r.status, 200)

    httpd:delete('content_type')

    r = http_client.get(helpers.base_uri .. '/content_type')
    t.assert_equals(r.status, 404)
end
