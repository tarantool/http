local t = require('luatest')
local http_client = require('http.client')
local json = require('json')

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

g.test_test = function()
    local r = http_client.get(helpers.base_uri .. '/test')
    t.assert_equals(r.status, 200, '/test code')

    t.assert_equals(r.proto[1], 1, '/test http 1.1')
    t.assert_equals(r.proto[2], 1, '/test http 1.1')
    t.assert_equals(r.reason, 'Ok', '/test reason')
    t.assert_equals(string.match(r.body, 'title: 123'), 'title: 123', '/test body')
end

g.test_404 = function()
    local r = http_client.get(helpers.base_uri .. '/test404')
    t.assert_equals(r.status, 404, '/test404 code')
    -- broken in built-in tarantool/http
    --t.assert_equals(r.reason, 'Not found', '/test404 reason')
end

g.test_absent = function()
    local r = http_client.get(helpers.base_uri .. '/absent')
    t.assert_equals(r.status, 500, '/absent code')
    --t.assert_equals(r.reason, 'Internal server error', '/absent reason')
    t.assert_equals(string.match(r.body, 'load module'), 'load module', '/absent body')
end

g.test_ctx_action = function()
    local r = http_client.get(helpers.base_uri .. '/ctxaction')
    t.assert_equals(r.status, 200, '/ctxaction code')
    t.assert_equals(r.reason, 'Ok', '/ctxaction reason')
    t.assert_equals(string.match(r.body, 'Hello, Tarantool'), 'Hello, Tarantool',
                    '/ctxaction body')
    t.assert_equals(string.match(r.body, 'action: action'), 'action: action',
                    '/ctxaction body action')
    t.assert_equals(string.match(r.body, 'controller: module[.]controller'),
                    'controller: module.controller', '/ctxaction body controller')
end

g.test_ctx_action_invalid = function()
    local r = http_client.get(helpers.base_uri .. '/ctxaction.invalid')
    t.assert_equals(r.status, 404, '/ctxaction.invalid code') -- WTF?
    --t.assert_equals(r.reason, 'Ok', '/ctxaction.invalid reason')
    t.assert_equals(r.body, nil, '/ctxaction.invalid body')
end

g.test_static_file = function()
    local r = http_client.get(helpers.base_uri .. '/hello.html')
    t.assert_equals(r.status, 200, '/hello.html code')
    t.assert_equals(r.reason, 'Ok', '/hello.html reason')
    t.assert_equals(string.match(r.body, 'static html'), 'static html',
        '/hello.html body')
end

g.test_absent_action = function()
    local r = http_client.get(helpers.base_uri .. '/absentaction')
    t.assert_equals(r.status, 500, '/absentaction 500')
    --t.assert_equals(r.reason, 'Unknown', '/absentaction reason')
    t.assert_equals(string.match(r.body, 'contain function'), 'contain function',
                   '/absentaction body')
end

g.test_helper = function()
    local r = http_client.get(helpers.base_uri .. '/helper')
    t.assert_equals(r.status, 200, 'helper 200')
    t.assert_equals(r.reason, 'Ok', 'helper reason')
    t.assert_equals(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')
end

g.test_500 = function()
    local httpd = g.httpd
    local r = http_client.get(helpers.base_uri .. '/helper?abc')
    t.assert_equals(r.status, 200, 'helper?abc 200')
    t.assert_equals(r.reason, 'Ok', 'helper?abc reason')
    t.assert_equals(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')

    httpd:route({
        path = '/die',
        file = 'helper.html.el'
    }, function()
        error(123)
    end)

    local r = http_client.get(helpers.base_uri .. '/die')
    t.assert_equals(r.status, 500, 'die 500')
    --t.assert_equals(r.reason, 'Unknown', 'die reason')
end

g.test_server_request_10 = function()
    local httpd = g.httpd
    httpd:route({
        path = '/info'
    }, function(cx)
        return cx:render({ json = cx.peer })
    end)

    local r = json.decode(http_client.get(helpers.base_uri .. '/info').body)
    t.assert_equals(r.host, helpers.base_host, 'peer.host')
    t.assert_type(r.port, 'number', 'peer.port')
end

g.test_POST = function()
    local httpd = g.httpd
    local r = httpd:route({
        method = 'POST',
        path = '/dit',
        file = 'helper.html.el'
    }, function(tx)
        return tx:render({text = 'POST = ' .. tx:read()})
    end)
    t.assert_type(r, 'table', ':route')
end

-- GET/POST at one route.
g.test_GET_and_POST = function()
    local httpd = g.httpd
    local r = httpd:route({
        method = 'POST',
        path = '/dit',
        file = 'helper.html.el'
    }, function(tx)
        return tx:render({text = 'POST = ' .. tx:read()})
    end)
    t.assert_type(r, 'table', 'add POST method')

    r = httpd:route({
        method = 'GET',
        path = '/dit',
        file = 'helper.html.el'
    }, function(tx)
        return tx:render({text = 'GET = ' .. tx:read()})
    end)
    t.assert_type(r, 'table', 'add GET method')

    r = http_client.request('POST', helpers.base_uri .. '/dit', 'test')
    t.assert_equals(r.body, 'POST = test', 'POST reply')
    r = http_client.request('GET', helpers.base_uri .. '/dit')
    t.assert_equals(r.body, 'GET = ', 'GET reply')

    local r = http_client.request('GET', helpers.base_uri .. '/dit')
    t.assert_equals(r.body, 'GET = ', 'GET reply')

    local r = http_client.request('POST', helpers.base_uri .. '/dit', 'test')
    t.assert_equals(r.body, 'POST = test', 'POST reply')
end

-- test GET parameters.
g.test_GET_params = function()
    local httpd = g.httpd

    local r = httpd:route({
        method = 'GET',
        path = '/param',
        file = 'helper.html.el'
    }, function(tx)
        local params = ""
        for k,v in pairs(tx:param()) do
            params = params .. k .. "=" .. v
        end
        return tx:render({text = params .. tx:read()})
    end)
    t.assert_type(r, 'table', 'add GET method')

    r = http_client.request('GET', helpers.base_uri .. '/param?a=1')
    t.assert_equals(r.body, 'a=1', 'GET reply parameter')

    r = http_client.request('GET', helpers.base_uri .. '/param?a+a=1')
    t.assert_equals(r.body, 'a a=1', 'GET reply parameter name with plus')

    r = http_client.request('GET', helpers.base_uri .. '/param?a=1+1')
    t.assert_equals(r.body, 'a=1 1', 'GET reply parameter value with plus')
end

g.test_DELETE = function()
    local httpd = g.httpd
    local r = httpd:route({
        method = 'DELETE',
        path = '/dit',
        file = 'helper.html.el'
    }, function(tx)
        return tx:render({text = 'DELETE = ' .. tx:read()})
    end)
    t.assert_type(r, 'table', 'add DELETE method')

    local r = http_client.request('DELETE', helpers.base_uri .. '/dit', 'test1')
    t.assert_equals(r.body, 'DELETE = test1', 'DELETE reply')
end

g.test_PATCH = function()
    local httpd = g.httpd
    local r = httpd:route({
        method = 'PATCH',
        path = '/dit',
        file = 'helper.html.el'
    }, function(tx)
        return tx:render({text = 'PATCH = ' .. tx:read()})
    end )
    t.assert_type(r, 'table', 'add PATCH method')

    local r = http_client.request('PATCH', helpers.base_uri .. '/dit', 'test2')
    t.assert_equals(r.body, 'PATCH = test2', 'PATCH reply')
end

g.test_chunked_encoding = function()
    local httpd = g.httpd
    httpd:route({
        path = '/chunked'
    }, function(self)
        return self:iterate(ipairs({'chunked', 'encoding', 't\r\nest'}))
    end)

    -- HTTP client currently doesn't support chunked encoding.
    local r = http_client.get(helpers.base_uri .. '/chunked')
    t.assert_equals(r.status, 200, 'chunked 200')
    t.assert_equals(r.headers['transfer-encoding'], 'chunked', 'chunked headers')
    t.assert_equals(r.body, 'chunkedencodingt\r\nest', 'chunked body')
end

-- Get raw cookie value (Günter -> Günter).
g.test_get_cookie = function()
    local cookie = 'Günter'
    local httpd = g.httpd
    httpd:route({
        path = '/receive_cookie'
    }, function(req)
        local name = req:cookie('name', {
            raw = true
        })
        return req:render({
            text = ('name=%s'):format(name)
        })
    end)

    local r = http_client.get(helpers.base_uri .. '/receive_cookie', {
        headers = {
            cookie = 'name=' .. cookie,
        }
    })

    t.assert_equals(r.status, 200, 'response status')
    t.assert_equals(r.body, 'name=' .. cookie, 'body with raw cookie')
end

-- Get escaped cookie (G%C3%BCnter -> Günter).
g.test_get_escaped_cookie = function()
    local str_escaped = 'G%C3%BCnter'
    local str_non_escaped = 'Günter'
    local httpd = g.httpd
    httpd:route({
        path = '/receive_cookie'
    }, function(req)
        local name = req:cookie('name')
        return req:render({
            text = ('name=%s'):format(name)
        })
    end)

    local r = http_client.get(helpers.base_uri .. '/receive_cookie', {
        headers = {
            cookie = 'name=' .. str_escaped,
        }
    })

    t.assert_equals(r.status, 200, 'response status')
    t.assert_equals(r.body, 'name=' .. str_non_escaped, 'body with escaped cookie')
end

-- Set escaped cookie (Günter -> G%C3%BCnter).
g.test_set_escaped_cookie = function(g)
    local str_escaped = 'G%C3%BCnter'
    local str_non_escaped = 'Günter'

    local httpd = g.httpd
    httpd:route({
        path = '/cookie'
    }, function(req)
        local resp = req:render({
            text = ''
        })
        resp:setcookie({
            name = 'name',
            value = str_non_escaped
        })
        return resp
    end)

    local r = http_client.get(helpers.base_uri .. '/cookie')
    t.assert_equals(r.status, 200, 'response status')
    t.assert_equals(r.headers['set-cookie'], 'name=' .. str_escaped, 'header with escaped cookie')
end

-- Set raw cookie (Günter -> Günter).
g.test_set_raw_cookie = function(g)
    local cookie = 'Günter'
    local httpd = g.httpd
    httpd:route({
        path = '/cookie'
    }, function(req)
        local resp = req:render({
            text = ''
        })
        resp:setcookie({
            name = 'name',
            value = cookie
        }, {
            raw = true
        })
        return resp
    end)

    local r = http_client.get(helpers.base_uri .. '/cookie')
    t.assert_equals(r.status, 200, 'response status')
    t.assert_equals(r.headers['set-cookie'], 'name=' .. cookie, 'header with raw cookie')
end

-- Request object methods.
g.test_request_object_methods = function()
    local httpd = g.httpd
    httpd:route({
        path = '/check_req_methods_for_json',
        method = 'POST'
    }, function(req)
        return {
            headers = {},
            body = json.encode({
                request_line = req:request_line(),
                read_cached = req:read_cached(),
                json = req:json(),
                post_param_for_kind = req:post_param('kind'),
            }),
            status = 200,
        }
    end)

    httpd:route({
        path = '/check_req_methods',
        method = 'POST'
    }, function(req)
        return {
            headers = {},
            body = json.encode({
                request_line = req:request_line(),
                read_cached = req:read_cached(),
            }),
            status = 200,
        }
    end)

    local r = http_client.post(
        helpers.base_uri .. '/check_req_methods_for_json',
        '{"kind": "json"}', {
            headers = {
                ['Content-type'] = 'application/json',
                ['X-test-header'] = 'test-value'
            }
    })
    t.assert_equals(r.status, 200, 'status')

    local parsed_body = json.decode(r.body)
    t.assert_equals(parsed_body.request_line,
        'POST /check_req_methods_for_json? HTTP/1.1', 'req.request_line')
    t.assert_equals(parsed_body.read_cached,
        '{"kind": "json"}', 'json req:read_cached()')
    t.assert_equals(parsed_body.json, {
        kind = 'json'
    }, 'req:json()')
    t.assert_equals(parsed_body.post_param_for_kind,
        'json', 'req:post_param()')

    local r = http_client.post(
        helpers.base_uri .. '/check_req_methods',
        'hello mister'
    )
    t.assert_equals(r.status, 200, 'status')
    local parsed_body = json.decode(r.body)
    t.assert_equals(parsed_body.read_cached, 'hello mister',
        'non-json req:read_cached()')
end

g.test_content_type_header_with_render = function()
    local httpd = g.httpd
    httpd:route({
        method = 'GET',
        path = '/content_type',
        file = 'helper.html.el'
    }, function(tx)
        return tx:render()
    end)

    local r = http_client.get(helpers.base_uri .. '/content_type')
    t.assert_equals(r.status, 200)
    t.assert_equals(r.headers['content-type'], 'text/html; charset=utf-8', 'content-type header')
end

g.test_content_type_header_without_render = function()
    local httpd = g.httpd
    httpd:route({
        path = '/content_type'
    }, function() end)
    local r = http_client.get(helpers.base_uri .. '/content_type')
    t.assert_equals(r.status, 200)
    t.assert_equals(r.headers['content-type'], 'text/plain; charset=utf-8', 'content-type header')
end
