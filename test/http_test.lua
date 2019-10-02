#!/usr/bin/env tarantool

local t = require('luatest')
local g = t.group('http')
local tap = require('tap')
local fio = require('fio')
local http_lib = require('http.lib')
local http_client = require('http.client')
local http_server = require('http.server')
local ngx_server = require('http.nginx_server')
local http_router = require('http.router')
local json = require('json')
local urilib = require('uri')

-- fix tap and http logs interleaving.
--
-- tap module writes to stdout,
-- http-server logs to stderr.
-- this results in non-synchronized output.
--
-- somehow redirecting stdout to stderr doesn't
-- remove buffering of tap logs (at least on OSX).
-- Monkeypatching to the rescue!

local orig_iowrite = io.write
package.loaded['io'].write = function(...)
    orig_iowrite(...)
    io.flush()
end

g.before_all = function()
    box.cfg{listen = '127.0.0.1:3301'}  -- luacheck: ignore
    box.schema.user.grant(              -- luacheck: ignore
        'guest', 'read,write,execute', 'universe', nil, {if_not_exists = true}
    )
end

g.test_split_uri = function()
    local function check(uri, rhs)
        local lhs = urilib.parse(uri)
        local extra = { lhs = lhs, rhs = rhs }
        if lhs.query == '' then
            lhs.query = nil
        end
        t.assertEquals(lhs.scheme, rhs.scheme, uri.." scheme", extra)
        t.assertEquals(lhs.host, rhs.host, uri.." host", extra)
        t.assertEquals(lhs.service, rhs.service, uri.." service", extra)
        t.assertEquals(lhs.path, rhs.path, uri.." path", extra)
        t.assertEquals(lhs.query, rhs.query, uri.." query", extra)
    end
    check('http://abc', { scheme = 'http', host = 'abc'})
    check('http://abc/', { scheme = 'http', host = 'abc', path ='/'})
    check('http://abc?', { scheme = 'http', host = 'abc'})
    check('http://abc/?', { scheme = 'http', host = 'abc', path ='/'})
    check('http://abc/?', { scheme = 'http', host = 'abc', path ='/'})
    check('http://abc:123', { scheme = 'http', host = 'abc', service = '123' })
    check('http://abc:123?', { scheme = 'http', host = 'abc', service = '123'})
    check('http://abc:123?query', { scheme = 'http', host = 'abc',
                                    service = '123', query = 'query'})
    check('http://domain.subdomain.com:service?query', { scheme = 'http',
                                                         host = 'domain.subdomain.com', service = 'service', query = 'query'})
    check('google.com', { host = 'google.com'})
    check('google.com?query', { host = 'google.com', query = 'query'})
    check('google.com/abc?query', { host = 'google.com', path = '/abc',
                                    query = 'query'})
    check('https://google.com:443/abc?query', { scheme = 'https',
                                                host = 'google.com', service = '443', path = '/abc', query = 'query'})
end

g.test_template = function()
    t.assertEquals(http_lib.template("<% for i = 1, cnt do %> <%= abc %> <% end %>",
                                     {abc = '1 <3>&" ', cnt = 3}),
                   ' 1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;  ',
                   "tmpl1")
    t.assertEquals(http_lib.template("<% for i = 1, cnt do %> <%= ab %> <% end %>",
                                     {abc = '1 <3>&" ', cnt = 3}),
                   ' nil  nil  nil ', "tmpl2")
    local r, msg = pcall(http_lib.template, "<% ab() %>", {ab = '1'})
    t.assertTrue(r == false and msg:match("call local 'ab'") ~= nil, "bad template")

    -- gh-18: rendered tempate is truncated
    local template = [[
<html>
<body>
    <table border="1">
    % for i,v in pairs(t) do
    <tr>
    <td><%= i %></td>
    <td><%= v %></td>
    </tr>
    % end
    </table>
</body>
</html>
]]

    local tt = {}
    for i=1, 100 do
        tt[i] = string.rep('#', i)
    end

    local rendered, code = http_lib.template(template, { t = tt })
    t.assertTrue(#rendered > 10000, "rendered size")
    t.assertEquals(rendered:sub(#rendered - 7, #rendered - 1), "</html>", "rendered eof")
end

g.test_parse_request = function(test)

    t.assertEquals(http_lib._parse_request('abc'),
                   { error = 'Broken request line', headers = {} }, 'broken request')



    t.assertEquals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").path,
        '/',
        'path'
    )
    t.assertEquals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").proto,
        {1,1},
        'proto'
    )
    t.assertEquals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").headers,
        {host = 's.com'},
        'host'
    )
    t.assertEquals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").method,
        'GET',
        'method'
    )
    t.assertEquals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").query,
        '',
        'query'
    )
end

g.test_params = function(test)
    t.assertEquals(http_lib.params(), {}, 'nil string')
    t.assertEquals(http_lib.params(''), {}, 'empty string')
    t.assertEquals(http_lib.params('a'), {a = ''}, 'separate literal')
    t.assertEquals(http_lib.params('a=b'), {a = 'b'}, 'one variable')
    t.assertEquals(http_lib.params('a=b&b=cde'), {a = 'b', b = 'cde'}, 'some')
    t.assertEquals(http_lib.params('a=b&b=cde&a=1'),
                   {a = { 'b', '1' }, b = 'cde'}, 'array')
end

local function is_nginx_test()
    local server_type = os.getenv('SERVER_TYPE') or 'builtin'
    return server_type:lower() == 'nginx'
end

local function is_builtin_test()
    return not is_nginx_test()
end

local function choose_server()
    local log_requests = true
    local log_errors = true

    if is_nginx_test() then
        -- host and port are for SERVER_NAME, SERVER_PORT only.
        -- TODO: are they required?

        return ngx_server.new({
                host = '127.0.0.1',
                port = 12345,
                tnt_method = 'nginx_entrypoint',
                log_requests = log_requests,
                log_errors = log_errors,
        })
    end

    return http_server.new('127.0.0.1', 12345, {
                               log_requests = log_requests,
                               log_errors = log_errors
    })
end

local function cfgserv()
    local path = os.getenv('LUA_SOURCE_DIR') or './'
    path = fio.pathjoin(path, 'test')

    local httpd = choose_server()
    local router = http_router.new({app_dir = path})
        :route({path = '/abc/:cde/:def', name = 'test'}, function() end)
        :route({path = '/abc'}, function() end)
        :route({path = '/ctxaction'}, 'module.controller#action')
        :route({path = '/absentaction'}, 'module.controller#absent')
        :route({path = '/absent'}, 'module.absent#action')
        :route({path = '/abc/:cde'}, function() end)
        :route({path = '/abc_:cde_def'}, function() end)
        :route({path = '/abc-:cde-def'}, function() end)
        :route({path = '/aba*def'}, function() end)
        :route({path = '/abb*def/cde', name = 'star'}, function() end)
        :route({path = '/banners/:token'})
        :helper('helper_title', function(self, a) return 'Hello, ' .. a end)
        :route({path = '/helper', file = 'helper.html.el'})
        :route({ path = '/test', file = 'test.html.el' },
            function(cx) return cx:render({ title = 'title: 123' }) end)
    httpd:set_router(router)
    return httpd, router
end

g.test_server_url_match = function(test)
    local httpd, router = cfgserv()
    t.assertIsTable(httpd, "httpd object")
    t.assertIsNil(router:match('GET', '/'))
    t.assertEquals(router:match('GET', '/abc').endpoint.path, "/abc", "/abc")
    t.assertEquals(#router:match('GET', '/abc').stash, 0, "/abc")
    t.assertEquals(router:match('GET', '/abc/123').endpoint.path, "/abc/:cde", "/abc/123")
    t.assertEquals(router:match('GET', '/abc/123').stash.cde, "123", "/abc/123")
    t.assertEquals(router:match('GET', '/abc/123/122').endpoint.path, "/abc/:cde/:def",
                   "/abc/123/122")
    t.assertEquals(router:match('GET', '/abc/123/122').stash.def, "122",
                   "/abc/123/122")
    t.assertEquals(router:match('GET', '/abc/123/122').stash.cde, "123",
                   "/abc/123/122")
    t.assertEquals(router:match('GET', '/abc_123-122').endpoint.path, "/abc_:cde_def",
                   "/abc_123-122")
    t.assertEquals(router:match('GET', '/abc_123-122').stash.cde_def, "123-122",
                   "/abc_123-122")
    t.assertEquals(router:match('GET', '/abc-123-def').endpoint.path, "/abc-:cde-def",
                   "/abc-123-def")
    t.assertEquals(router:match('GET', '/abc-123-def').stash.cde, "123",
                   "/abc-123-def")
    t.assertEquals(router:match('GET', '/aba-123-dea/1/2/3').endpoint.path,
                   "/aba*def", '/aba-123-dea/1/2/3')
    t.assertEquals(router:match('GET', '/aba-123-dea/1/2/3').stash.def,
                   "-123-dea/1/2/3", '/aba-123-dea/1/2/3')
    t.assertEquals(router:match('GET', '/abb-123-dea/1/2/3/cde').endpoint.path,
                   "/abb*def/cde", '/abb-123-dea/1/2/3/cde')
    t.assertEquals(router:match('GET', '/abb-123-dea/1/2/3/cde').stash.def,
                   "-123-dea/1/2/3", '/abb-123-dea/1/2/3/cde')
    t.assertEquals(router:match('GET', '/banners/1wulc.z8kiy.6p5e3').stash.token,
                   '1wulc.z8kiy.6p5e3', "stash with dots")
end


g.test_server_url_for = function()
    local httpd, router = cfgserv()
    t.assertEquals(router:url_for('abcdef'), '/abcdef', '/abcdef')
    t.assertEquals(router:url_for('test'), '/abc//', '/abc//')
    t.assertEquals(router:url_for('test', { cde = 'cde_v', def = 'def_v' }),
                   '/abc/cde_v/def_v', '/abc/cde_v/def_v')
    t.assertEquals(router:url_for('star', { def = '/def_v' }),
                   '/abb/def_v/cde', '/abb/def_v/cde')
    t.assertEquals(router:url_for('star', { def = '/def_v' }, { a = 'b', c = 'd' }),
                   '/abb/def_v/cde?a=b&c=d', '/abb/def_v/cde?a=b&c=d')
end

g.test_server_requests = function()
    local httpd, router = cfgserv()
    httpd:start()

    local r = http_client.get('http://127.0.0.1:12345/test')
    t.assertEquals(r.status, 200, '/test code')

    t.assertEquals(r.proto[1], 1, '/test http 1.1')
    t.assertEquals(r.proto[2], 1, '/test http 1.1')
    t.assertEquals(r.reason, 'Ok', '/test reason')
    t.assertEquals(string.match(r.body, 'title: 123'), 'title: 123', '/test body')

    local r = http_client.get('http://127.0.0.1:12345/test404')
    t.assertEquals(r.status, 404, '/test404 code')
    -- broken in built-in tarantool/http
    --t.assertEquals(r.reason, 'Not found', '/test404 reason')

    local r = http_client.get('http://127.0.0.1:12345/absent')
    t.assertEquals(r.status, 500, '/absent code')
    --t.assertEquals(r.reason, 'Internal server error', '/absent reason')
    t.assertEquals(string.match(r.body, 'load module'), 'load module', '/absent body')

    local r = http_client.get('http://127.0.0.1:12345/ctxaction')
    t.assertEquals(r.status, 200, '/ctxaction code')
    t.assertEquals(r.reason, 'Ok', '/ctxaction reason')
    t.assertEquals(string.match(r.body, 'Hello, Tarantool'), 'Hello, Tarantool',
                   '/ctxaction body')
    t.assertEquals(string.match(r.body, 'action: action'), 'action: action',
                   '/ctxaction body action')
    t.assertEquals(string.match(r.body, 'controller: module[.]controller'),
                   'controller: module.controller', '/ctxaction body controller')

    local r = http_client.get('http://127.0.0.1:12345/ctxaction.invalid')
    t.assertEquals(r.status, 404, '/ctxaction.invalid code') -- WTF?
    --t.assertEquals(r.reason, 'Not found', '/ctxaction.invalid reason')
    --t.assertEquals(r.body, '', '/ctxaction.invalid body')

    local r = http_client.get('http://127.0.0.1:12345/hello.html')
    t.assertEquals(r.status, 200, '/hello.html code')
    t.assertEquals(r.reason, 'Ok', '/hello.html reason')
    t.assertEquals(string.match(r.body, 'static html'), 'static html',
                   '/hello.html body')

    local r = http_client.get('http://127.0.0.1:12345/absentaction')
    t.assertEquals(r.status, 500, '/absentaction 500')
    --t.assertEquals(r.reason, 'Internal server error', '/absentaction reason')
    t.assertEquals(string.match(r.body, 'contain function'), 'contain function',
                   '/absentaction body')

    local r = http_client.get('http://127.0.0.1:12345/helper')
    t.assertEquals(r.status, 200, 'helper 200')
    t.assertEquals(r.reason, 'Ok', 'helper reason')
    t.assertEquals(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')

    local r = http_client.get('http://127.0.0.1:12345/helper?abc')
    t.assertEquals(r.status, 200, 'helper?abc 200')
    t.assertEquals(r.reason, 'Ok', 'helper?abc reason')
    t.assertEquals(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')

    router:route({path = '/die', file = 'helper.html.el'},
        function() error(123) end )

    local r = http_client.get('http://127.0.0.1:12345/die')
    t.assertEquals(r.status, 500, 'die 500')
    --t.assertEquals(r.reason, 'Internal server error', 'die reason')

    router:route({ path = '/info' }, function(cx)
            return cx:render({ json = cx:peer() })
    end)

    local r = json.decode(http_client.get('http://127.0.0.1:12345/info').body)
    t.assertEquals(r.host, '127.0.0.1', 'peer.host')
    t.assertIsNumber(r.port, 'peer.port')

    local r = router:route({method = 'POST', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'POST = ' .. tx:read()})
    end)
    t.assertIsTable(r, ':route')


    -- GET/POST at one route
    r = router:route({method = 'POST', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'POST = ' .. tx:read()})
    end)
    t.assertIsTable(r, 'add POST method')

    r = router:route({method = 'GET', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'GET = ' .. tx:read()})
    end )
    t.assertIsTable(r, 'add GET method')

    r = router:route({method = 'DELETE', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'DELETE = ' .. tx:read()})
    end )
    t.assertIsTable(r, 'add DELETE method')

    r = router:route({method = 'PATCH', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'PATCH = ' .. tx:read()})
    end )
    t.assertIsTable(r, 'add PATCH method')

    -- TODO
    r = http_client.request('POST', 'http://127.0.0.1:12345/dit', 'test')
    t.assertEquals(r.body, 'POST = test', 'POST reply')

    r = http_client.request('GET', 'http://127.0.0.1:12345/dit')
    t.assertEquals(r.body, 'GET = ', 'GET reply')

    r = http_client.request('DELETE', 'http://127.0.0.1:12345/dit', 'test1')
    t.assertEquals(r.body, 'DELETE = test1', 'DELETE reply')

    r = http_client.request('PATCH', 'http://127.0.0.1:12345/dit', 'test2')
    t.assertEquals(r.body, 'PATCH = test2', 'PATCH reply')

    router:route({path = '/chunked'}, function(self)
            return self:iterate(ipairs({'chunked', 'encoding', 't\r\nest'}))
    end)

    -- http client currently doesn't support chunked encoding
    local r = http_client.get('http://127.0.0.1:12345/chunked')
    t.assertEquals(r.status, 200, 'chunked 200')
    t.assertEquals(r.headers['transfer-encoding'], 'chunked', 'chunked headers')
    t.assertEquals(r.body, 'chunkedencodingt\r\nest', 'chunked body')

    -- get cookie
    router:route({path = '/receive_cookie'}, function(req)
            local foo = req:cookie('foo')
            local baz = req:cookie('baz')
            return req:render({
                    text = ('foo=%s; baz=%s'):format(foo, baz)
            })
    end)
    local r = http_client.get('http://127.0.0.1:12345/receive_cookie', {
                                  headers = {
                                      cookie = 'foo=bar; baz=feez',
                                  }
    })
    t.assertEquals(r.status, 200, 'status')
    t.assertEquals(r.body, 'foo=bar; baz=feez', 'body')

    -- cookie
    router:route({path = '/cookie'}, function(req)
            local resp = req:render({text = ''})
            resp:setcookie({ name = 'test', value = 'tost',
                             expires = '+1y', path = '/abc' })
            resp:setcookie({ name = 'xxx', value = 'yyy' })
            return resp
    end)
    local r = http_client.get('http://127.0.0.1:12345/cookie')
    t.assertEquals(r.status, 200, 'status')
    t.assertTrue(r.headers['set-cookie'] ~= nil, "header")


    -- request object with GET method
    router:route({path = '/check_req_properties'}, function(req)
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
    local r = http_client.get(
        'http://127.0.0.1:12345/check_req_properties?foo=1&bar=2', {
            headers = {
                ['X-test-header'] = 'test-value'
            }
    })
    t.assertEquals(r.status, 200, 'status')

    local parsed_body = json.decode(r.body)
    t.assertEquals(parsed_body.headers['x-test-header'], 'test-value', 'req.headers')
    t.assertEquals(parsed_body.method, 'GET', 'req.method')
    t.assertEquals(parsed_body.path, '/check_req_properties', 'req.path')
    t.assertEquals(parsed_body.query, 'foo=1&bar=2', 'req.query')
    t.assertEquals(parsed_body.query_param_bar, '2', 'req:query_param()')
    t.assertEquals(parsed_body.proto, {1, 1}, 'req.proto')

    -- request object methods
    router:route({path = '/check_req_methods_for_json', method = 'POST'}, function(req)
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
    router:route({path = '/check_req_methods', method = 'POST'}, function(req)
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
        'http://127.0.0.1:12345/check_req_methods_for_json',
        '{"kind": "json"}', {
            headers = {
                ['Content-type'] = 'application/json',
                ['X-test-header'] = 'test-value'
            }
    })
    t.assertEquals(r.status, 200, 'status')

    local parsed_body = json.decode(r.body)
    t.assertEquals(parsed_body.request_line, 'POST /check_req_methods_for_json HTTP/1.1', 'req.request_line')
    t.assertEquals(parsed_body.read_cached, '{"kind": "json"}', 'json req:read_cached()')
    t.assertEquals(parsed_body.json, {kind = "json"}, 'req:json()')
    t.assertEquals(parsed_body.post_param_for_kind, "json", 'req:post_param()')

    r = http_client.post(
        'http://127.0.0.1:12345/check_req_methods',
        'hello mister'
    )
    t.assertEquals(r.status, 200, 'status')
    parsed_body = json.decode(r.body)
    t.assertEquals(parsed_body.read_cached, 'hello mister', 'non-json req:read_cached()')

    if is_builtin_test() then
        router:route({ path = '/post', method = 'POST'}, function(req)
                local t = {
                    #req:read("\n");
                    #req:read(10);
                    #req:read({ size = 10, delimiter = "\n"});
                    #req:read("\n");
                    #req:read();
                    #req:read();
                    #req:read();
                }
                return req:render({json = t})
        end)
        local bodyf = os.getenv('LUA_SOURCE_DIR') or './'
        bodyf = io.open(fio.pathjoin(bodyf, 'test/public/lorem.txt'))
        local body = bodyf:read('*a')
        bodyf:close()
        local r = http_client.post('http://127.0.0.1:12345/post', body)
        t.assertEquals(r.status, 200, 'status')
        t.assertEquals(json.decode(r.body), { 541,10,10,458,1375,0,0 },
                       'req:read() results')
    else
        t.assertTrue(true, 'post body - ignore on NGINX')
    end

    -- hijacking
    if is_builtin_test() then
        -- 0. create a route (simplest) in which env:hijack() is called,
        --    and then do ping-pong.
        router:route({method = 'POST', path = '/upgrade'}, function(req)
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
        t.assertTrue(sock ~= nil, 'HTTP client connection established')

        -- 2. over raw-socket send HTTP POST (to get it routed to route)
        local upgrade_request = 'POST /upgrade HTTP/1.1\r\nConnection: upgrade\r\n\r\n'
        local bytessent = sock:write(upgrade_request)
        t.assertEquals(bytessent, #upgrade_request, 'upgrade request sent fully')

        -- 3. send ping, receive pong
        t.assertEquals(sock:read(5), 'ready', 'server is ready')
        sock:write('ping')
        t.assertEquals(sock:read(4), 'pong', 'pong receieved')
    else
        t.assertTrue(true, 'HTTP client connection established - ignored on NGINX')
        t.assertTrue(true, 'upgrade request sent fully - ignored on NGINX')
        t.assertTrue(true, 'server is ready - ignored on NGINX')
        t.assertTrue(true, 'pong received - ignored on NGINX')
    end

    -- prioritization of more specific routes
    router:route({method = 'GET', path = '*stashname'}, function(_)
            return {
                status = 200,
                body = 'GET *',
            }
    end)
    local r = http_client.get('http://127.0.0.1:12345/a/b/c')
    t.assertEquals(r.status, 200, '/a/b/c request returns 200')
    t.assertEquals(r.body, 'GET *', 'GET * matches')

    router:route({method = 'ANY', path = '/a/:foo/:bar'}, function(_)
            return {
                status = 200,
                body = 'ANY /a/:foo/:bar',
            }
    end)
    local r = http_client.get('http://127.0.0.1:12345/a/b/c')
    t.assertEquals(r.status, 200, '/a/b/c request returns 200')
    t.assertEquals(
        r.body,
        'ANY /a/:foo/:bar',
        '# of stashes matched doesnt matter - only # of known symbols by the route matters'
    )

    httpd:stop()
end

g.test_middleware = function()
    local httpd, router = cfgserv()

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

    local ok = router:use(add_helloworld_to_response, {
                              name = 'hello_world',
                              path = '/.*',
                              method = {'GET', 'POST'},
    })
    t.assertTrue(ok, 'hello_world middleware added successfully')

    local middlewares_ordered = router.middleware:ordered()
    t.assertEquals(#middlewares_ordered, 1, 'one middleware is registered')

    ok = router:use(add_helloworld_before_to_response, {
                        name = 'hello_world_before',
                        path = '/.*',
                        method = 'ANY',
                        before = 'hello_world',
    })
    t.assertTrue(ok, 'hello_world_before middleware added successfully')

    middlewares_ordered = router.middleware:ordered()
    t.assertEquals(#middlewares_ordered, 2, 'both middlewares are registered')
    t.assertEquals(middlewares_ordered[1].name, 'hello_world_before',
                   'hello_world_before is first')
    t.assertEquals(middlewares_ordered[2].name, 'hello_world',
                   'hello_world is last')

    local apple_handler = function()
        return {status = 200, body = json.encode({kind = 'apple'})}
    end

    local orange_handler = function()
        return {status = 200, body = json.encode({kind = 'orange'})}
    end

    router:route(
        {
            method = 'GET',
            path = '/fruits/apple',
        },
        apple_handler
    )
    router:route(
        {
            method = 'GET',
            path = '/fruits/orange',
        },
        orange_handler
    )

    httpd:start()

    local r = http_client.get(
        'http://127.0.0.1:12345/fruits/apple'
    )
    t.assertEquals(r.status, 200, 'status')
    require('log').info('DEBUG: /fruits/apple response: %s', r.body)
    local parsed_body = json.decode(r.body)
    t.assertEquals(parsed_body.kind, 'apple', 'body is correct')
    t.assertEquals(parsed_body.message, 'hello world! (before)', 'hello_world middleware invoked last')

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

    ok = router:use(swap_orange_and_apple, {
                        preroute = true,
                        name = 'swap_orange_and_apple',
    })
    t.assertTrue(ok, 'swap_orange_and_apple middleware added successfully')

    r = http_client.get(
        'http://127.0.0.1:12345/fruits/apple'
    )
    t.assertEquals(r.status, 200, 'status')
    parsed_body = json.decode(r.body)
    t.assertEquals(parsed_body.kind, 'orange', 'route swapped from apple handler to orange')

    httpd:stop()
end
