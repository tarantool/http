local t = require('luatest')
local g = t.group()

local fio = require('fio')
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

g.test_redirect_to = function()
    g.router:route({path = '/from', method = 'GET'}, function (req) return req:redirect_to('/to') end)
    g.router:route({path = '/to', method = 'GET'}, function () return {body = "OK"} end)
    local r = http_client.get(helper.base_uri .. 'from')
    t.assert_equals(r.status, 200)
    t.assert_equals(r.body, "OK")
end

g.test_get_cookie = function()
    g.router:route({path = '/receive_cookie'}, function(req)
        local foo = req:cookie('foo')
        local baz = req:cookie('baz')
        return req:render({
            text = ('foo=%s; baz=%s'):format(foo, baz)
        })
    end)

    local r = http_client.get(helper.base_uri .. 'receive_cookie', {
        headers = {
            cookie = 'foo=f%3Bf; baz=f%5Cf',
        }
    })

    t.assert_equals(r.status, 200, 'status')
    t.assert_equals(r.body, 'foo=f;f; baz=f\\f', 'body')
end

g.test_get_cookie_raw = function()
    g.router:route({path = '/receive_cookie_raw'}, function(req)
        local foo = req:cookie('foo', {raw = true})
        local baz = req:cookie('baz', {raw = true})
        return req:render({
            text = ('foo=%s; baz=%s'):format(foo, baz)
        })
    end)

    local r = http_client.get(helper.base_uri .. 'receive_cookie_raw', {
        headers = {
            cookie = 'foo=f%3Bf; baz=f%5Cf',
        }
    })

    t.assert_equals(r.status, 200, 'status')
    t.assert_equals(r.body, 'foo=f%3Bf; baz=f%5Cf', 'body')
end

g.test_set_cookie = function()
    g.router:route({path = '/cookie'}, function(req)
        local resp = req:render({text = ''})
        resp:setcookie({ name = 'test', value = 'tost',
                         expires = '+1y', path = '/abc' })
        resp:setcookie({ name = 'xxx', value = 'yyy' })
        return resp
    end)
    local r = http_client.get(helper.base_uri .. 'cookie')
    t.assert_equals(r.status, 200, 'status')
    t.assert(r.headers['set-cookie'] ~= nil, "header")
end

g.test_server_requests = function()
    local r = http_client.get(helper.base_uri .. 'test')
    t.assert_equals(r.status, 200, '/test code')

    t.assert_equals(r.proto[1], 1, '/test http 1.1')
    t.assert_equals(r.proto[2], 1, '/test http 1.1')
    t.assert_equals(r.reason, 'Ok', '/test reason')
    t.assert_equals(string.match(r.body, 'title: 123'), 'title: 123', '/test body')

    r = http_client.get(helper.base_uri .. 'test404')
    t.assert_equals(r.status, 404, '/test404 code')
    -- broken in built-in tarantool/http
    --t.assert_equals(r.reason, 'Not found', '/test404 reason')

    r = http_client.get(helper.base_uri .. 'absent')
    t.assert_equals(r.status, 500, '/absent code')
    --t.assert_equals(r.reason, 'Internal server error', '/absent reason')
    t.assert_equals(string.match(r.body, 'load module'), 'load module', '/absent body')

    r = http_client.get(helper.base_uri .. 'ctxaction')
    t.assert_equals(r.status, 200, '/ctxaction code')
    t.assert_equals(r.reason, 'Ok', '/ctxaction reason')
    t.assert_equals(string.match(r.body, 'Hello, Tarantool'), 'Hello, Tarantool',
                   '/ctxaction body')
    t.assert_equals(string.match(r.body, 'action: action'), 'action: action',
                   '/ctxaction body action')
    t.assert_equals(string.match(r.body, 'controller: module[.]controller'),
                   'controller: module.controller', '/ctxaction body controller')

    r = http_client.get(helper.base_uri .. 'ctxaction.invalid')
    t.assert_equals(r.status, 404, '/ctxaction.invalid code') -- WTF?
    --t.assert_equals(r.reason, 'Not found', '/ctxaction.invalid reason')
    --t.assert_equals(r.body, '', '/ctxaction.invalid body')

    r = http_client.get(helper.base_uri .. 'hello.html')
    t.assert_equals(r.status, 200, '/hello.html code')
    t.assert_equals(r.reason, 'Ok', '/hello.html reason')
    t.assert_equals(string.match(r.body, 'static html'), 'static html',
                   '/hello.html body')

    r = http_client.get(helper.base_uri .. 'absentaction')
    t.assert_equals(r.status, 500, '/absentaction 500')
    --t.assert_equals(r.reason, 'Internal server error', '/absentaction reason')
    t.assert_equals(string.match(r.body, 'contain function'), 'contain function',
                   '/absentaction body')

    r = http_client.get(helper.base_uri .. 'helper')
    t.assert_equals(r.status, 200, 'helper 200')
    t.assert_equals(r.reason, 'Ok', 'helper reason')
    t.assert_equals(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')

    r = http_client.get(helper.base_uri .. 'helper?abc')
    t.assert_equals(r.status, 200, 'helper?abc 200')
    t.assert_equals(r.reason, 'Ok', 'helper?abc reason')
    t.assert_equals(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')

    g.router:route({path = '/die', file = 'helper.html.el'},
        function() error(123) end )

    r = http_client.get(helper.base_uri .. 'die')
    t.assert_equals(r.status, 500, 'die 500')
    --t.assert_equals(r.reason, 'Internal server error', 'die reason')

    g.router:route({ path = '/info' }, function(cx)
            return cx:render({ json = cx:peer() })
    end)

    r = json.decode(http_client.get(helper.base_uri .. 'info').body)
    t.assert_equals(r.host, '127.0.0.1', 'peer.host')
    t.assert_type(r.port, 'number')

    r = g.router:route({method = 'POST', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'POST = ' .. tx:read()})
    end)
    t.assert_type(r, 'table')


    -- GET/POST at one route
    r = g.router:route({method = 'POST', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'POST = ' .. tx:read()})
    end)
    t.assert_type(r, 'table')

    r = g.router:route({method = 'GET', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'GET = ' .. tx:read()})
    end )
    t.assert_type(r, 'table')

    r = g.router:route({method = 'DELETE', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'DELETE = ' .. tx:read()})
    end )
    t.assert_type(r, 'table')

    r = g.router:route({method = 'PATCH', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'PATCH = ' .. tx:read()})
    end )
    t.assert_type(r, 'table')

    -- TODO
    r = http_client.request('POST', helper.base_uri .. 'dit', 'test')
    t.assert_equals(r.body, 'POST = test', 'POST reply')

    r = http_client.request('GET', helper.base_uri .. 'dit')
    t.assert_equals(r.body, 'GET = ', 'GET reply')

    r = http_client.request('DELETE', helper.base_uri .. 'dit', 'test1')
    t.assert_equals(r.body, 'DELETE = test1', 'DELETE reply')

    r = http_client.request('PATCH', helper.base_uri .. 'dit', 'test2')
    t.assert_equals(r.body, 'PATCH = test2', 'PATCH reply')

    g.router:route({path = '/chunked'}, function(self)
            return self:iterate(ipairs({'chunked', 'encoding', 't\r\nest'}))
    end)

    -- http client currently doesn't support chunked encoding
    r = http_client.get(helper.base_uri .. 'chunked')
    t.assert_equals(r.status, 200, 'chunked 200')
    t.assert_equals(r.headers['transfer-encoding'], 'chunked', 'chunked headers')
    t.assert_equals(r.body, 'chunkedencodingt\r\nest', 'chunked body')


    -- request object with GET method
    g.router:route({path = '/check_req_properties'}, function(req)
            return {
                headers = {},
                body = json.encode({
                        headers = req:headers(),
                        method = req:method(),
                        path = req:path(),
                        query = req:query(),
                        proto = req:proto(),
                        query_param_bar = req:query_param('bar'),
                }),
                status = 200,
            }
    end)
    r = http_client.get(
        helper.base_uri .. 'check_req_properties?foo=1&bar=2', {
            headers = {
                ['X-test-header'] = 'test-value'
            }
    })
    t.assert_equals(r.status, 200, 'status')

    local parsed_body = json.decode(r.body)
    t.assert_equals(parsed_body.headers['x-test-header'], 'test-value', 'req.headers')
    t.assert_equals(parsed_body.method, 'GET', 'req.method')
    t.assert_equals(parsed_body.path, '/check_req_properties', 'req.path')
    t.assert_equals(parsed_body.query, 'foo=1&bar=2', 'req.query')
    t.assert_equals(parsed_body.query_param_bar, '2', 'req:query_param()')
    t.assert_equals(parsed_body.proto, {1, 1}, 'req.proto')

    -- request object methods
    g.router:route({path = '/check_req_methods_for_json', method = 'POST'}, function(req)
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
    g.router:route({path = '/check_req_methods', method = 'POST'}, function(req)
            return {
                headers = {},
                body = json.encode({
                        request_line = req:request_line(),
                        read_cached = req:read_cached(),
                }),
                status = 200,
            }
    end)

    r = http_client.post(
        helper.base_uri .. 'check_req_methods_for_json',
        '{"kind": "json"}', {
            headers = {
                ['Content-type'] = 'application/json',
                ['X-test-header'] = 'test-value'
            }
    })
    t.assert_equals(r.status, 200, 'status')

    parsed_body = json.decode(r.body)
    t.assert_equals(parsed_body.request_line, 'POST /check_req_methods_for_json HTTP/1.1', 'req.request_line')
    t.assert_equals(parsed_body.read_cached, '{"kind": "json"}', 'json req:read_cached()')
    t.assert_equals(parsed_body.json, {kind = "json"}, 'req:json()')
    t.assert_equals(parsed_body.post_param_for_kind, "json", 'req:post_param()')

    r = http_client.post(
        helper.base_uri .. 'check_req_methods',
        'hello mister'
    )
    t.assert_equals(r.status, 200, 'status')
    parsed_body = json.decode(r.body)
    t.assert_equals(parsed_body.read_cached, 'hello mister', 'non-json req:read_cached()')

    if helper.is_builtin_test() then
        g.router:route({ path = '/post', method = 'POST'}, function(req)
                return req:render({json = {
                    #req:read("\n");
                    #req:read(10);
                    #req:read({ size = 10, delimiter = "\n"});
                    #req:read("\n");
                    #req:read();
                    #req:read();
                    #req:read();
                }})
        end)
        local bodyf = os.getenv('LUA_SOURCE_DIR') or './'
        bodyf = io.open(fio.pathjoin(bodyf, 'test/public/lorem.txt'))
        local body = bodyf:read('*a')
        bodyf:close()
        r = http_client.post(helper.base_uri .. 'post', body)
        t.assert_equals(r.status, 200, 'status')
        t.assert_equals(json.decode(r.body), { 541,10,10,458,1375,0,0 },
                       'req:read() results')
    end

    -- hijacking
    if helper.is_builtin_test() then
        -- 0. create a route (simplest) in which env:hijack() is called,
        --    and then do ping-pong.
        g.router:route({method = 'POST', path = '/upgrade'}, function(req)
                -- intercept raw socket connection
                local sock = req:hijack()
                assert(sock ~= nil, 'hijacked socket is not empty')

                -- receive ping, send pong
                sock:write('ready')
                local ping = sock:read(4)
                assert(ping == 'ping')
                sock:write('pong')
        end)

        -- 1. set-up socket
        local socket = require('socket')
        local sock = socket.tcp_connect('127.0.0.1', 12345)
        t.assert(sock ~= nil, 'HTTP client connection established')

        -- 2. over raw-socket send HTTP POST (to get it routed to route)
        local upgrade_request = 'POST /upgrade HTTP/1.1\r\nConnection: upgrade\r\n\r\n'
        local bytessent = sock:write(upgrade_request)
        t.assert_equals(bytessent, #upgrade_request, 'upgrade request sent fully')

        -- 3. send ping, receive pong
        t.assert_equals(sock:read(5), 'ready', 'server is ready')
        sock:write('ping')
        t.assert_equals(sock:read(4), 'pong', 'pong receieved')
    end
end
