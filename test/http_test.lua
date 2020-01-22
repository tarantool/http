local t = require('luatest')
local g = t.group('http')

local fio = require('fio')
local http_lib = require('http.lib')
local http_client = require('http.client')
local http_server = require('http.server')
local ngx_server = require('http.nginx_server')
local http_router = require('http.router')
local json = require('json')
local urilib = require('uri')

g.before_all = function()
    box.cfg{listen = '127.0.0.1:3301'}
    box.schema.user.grant(
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
        t.assert_equals(lhs.scheme, rhs.scheme, uri.." scheme", extra)
        t.assert_equals(lhs.host, rhs.host, uri.." host", extra)
        t.assert_equals(lhs.service, rhs.service, uri.." service", extra)
        t.assert_equals(lhs.path, rhs.path, uri.." path", extra)
        t.assert_equals(lhs.query, rhs.query, uri.." query", extra)
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
    check('http://domain.subdomain.com:service?query', {
        scheme = 'http',
        host = 'domain.subdomain.com',
        service = 'service',
        query = 'query',
    })
    check('google.com', { host = 'google.com'})
    check('google.com?query', { host = 'google.com', query = 'query'})
    check('google.com/abc?query', { host = 'google.com', path = '/abc',
                                    query = 'query'})
    check('https://google.com:443/abc?query', { scheme = 'https',
                                                host = 'google.com', service = '443', path = '/abc', query = 'query'})
end

g.test_template = function()
    t.assert_equals(http_lib.template("<% for i = 1, cnt do %> <%= abc %> <% end %>",
                                     {abc = '1 <3>&" ', cnt = 3}),
                   ' 1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;  ',
                   "tmpl1")
    t.assert_equals(http_lib.template("<% for i = 1, cnt do %> <%= ab %> <% end %>",
                                     {abc = '1 <3>&" ', cnt = 3}),
                   ' nil  nil  nil ', "tmpl2")
    local r, msg = pcall(http_lib.template, "<% ab() %>", {ab = '1'})
    t.assert(r == false and msg:match("call local 'ab'") ~= nil, "bad template")

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

    local rendered = http_lib.template(template, { t = tt })
    t.assert(#rendered > 10000, "rendered size")
    t.assert_equals(rendered:sub(#rendered - 7, #rendered - 1), "</html>", "rendered eof")
end

g.test_parse_request = function()

    t.assert_equals(http_lib._parse_request('abc'),
                   { error = 'Broken request line', headers = {} }, 'broken request')



    t.assert_equals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").path,
        '/',
        'path'
    )
    t.assert_equals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").proto,
        {1,1},
        'proto'
    )
    t.assert_equals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").headers,
        {host = 's.com'},
        'host'
    )
    t.assert_equals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").method,
        'GET',
        'method'
    )
    t.assert_equals(
        http_lib._parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").query,
        '',
        'query'
    )
end

g.test_params = function()
    t.assert_equals(http_lib.params(), {}, 'nil string')
    t.assert_equals(http_lib.params(''), {}, 'empty string')
    t.assert_equals(http_lib.params('a'), {a = ''}, 'separate literal')
    t.assert_equals(http_lib.params('a=b'), {a = 'b'}, 'one variable')
    t.assert_equals(http_lib.params('a=b&b=cde'), {a = 'b', b = 'cde'}, 'some')
    t.assert_equals(http_lib.params('a=b&b=cde&a=1'),
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
        :helper('helper_title', function(_, a) return 'Hello, ' .. a end)
        :route({path = '/helper', file = 'helper.html.el'})
        :route({ path = '/test', file = 'test.html.el' },
            function(cx) return cx:render({ title = 'title: 123' }) end)
    httpd:set_router(router)
    return httpd, router
end

g.test_server_url_match = function()
    local httpd, router = cfgserv()
    t.assert_type(httpd, 'table')
    t.assert_is(router:match('GET', '/'), nil)
    t.assert_equals(router:match('GET', '/abc').endpoint.path, "/abc", "/abc")
    t.assert_equals(#router:match('GET', '/abc').stash, 0, "/abc")
    t.assert_equals(router:match('GET', '/abc/123').endpoint.path, "/abc/:cde", "/abc/123")
    t.assert_equals(router:match('GET', '/abc/123').stash.cde, "123", "/abc/123")
    t.assert_equals(router:match('GET', '/abc/123/122').endpoint.path, "/abc/:cde/:def",
                   "/abc/123/122")
    t.assert_equals(router:match('GET', '/abc/123/122').stash.def, "122",
                   "/abc/123/122")
    t.assert_equals(router:match('GET', '/abc/123/122').stash.cde, "123",
                   "/abc/123/122")
    t.assert_equals(router:match('GET', '/abc_123-122').endpoint.path, "/abc_:cde_def",
                   "/abc_123-122")
    t.assert_equals(router:match('GET', '/abc_123-122').stash.cde_def, "123-122",
                   "/abc_123-122")
    t.assert_equals(router:match('GET', '/abc-123-def').endpoint.path, "/abc-:cde-def",
                   "/abc-123-def")
    t.assert_equals(router:match('GET', '/abc-123-def').stash.cde, "123",
                   "/abc-123-def")
    t.assert_equals(router:match('GET', '/aba-123-dea/1/2/3').endpoint.path,
                   "/aba*def", '/aba-123-dea/1/2/3')
    t.assert_equals(router:match('GET', '/aba-123-dea/1/2/3').stash.def,
                   "-123-dea/1/2/3", '/aba-123-dea/1/2/3')
    t.assert_equals(router:match('GET', '/abb-123-dea/1/2/3/cde').endpoint.path,
                   "/abb*def/cde", '/abb-123-dea/1/2/3/cde')
    t.assert_equals(router:match('GET', '/abb-123-dea/1/2/3/cde').stash.def,
                   "-123-dea/1/2/3", '/abb-123-dea/1/2/3/cde')
    t.assert_equals(router:match('GET', '/banners/1wulc.z8kiy.6p5e3').stash.token,
                   '1wulc.z8kiy.6p5e3', "stash with dots")
end


g.test_server_url_for = function()
    local _, router = cfgserv()
    t.assert_equals(router:url_for('abcdef'), '/abcdef', '/abcdef')
    t.assert_equals(router:url_for('test'), '/abc//', '/abc//')
    t.assert_equals(router:url_for('test', { cde = 'cde_v', def = 'def_v' }),
                   '/abc/cde_v/def_v', '/abc/cde_v/def_v')
    t.assert_equals(router:url_for('star', { def = '/def_v' }),
                   '/abb/def_v/cde', '/abb/def_v/cde')
    t.assert_equals(router:url_for('star', { def = '/def_v' }, { a = 'b', c = 'd' }),
                   '/abb/def_v/cde?a=b&c=d', '/abb/def_v/cde?a=b&c=d')
end

g.test_redirect_to = function()
    local server, router = cfgserv()
    server:set_router(router)
    server:start()
    router:route({path = '/from', method = 'GET'}, function (req) return req:redirect_to('/to') end)
    router:route({path = '/to', method = 'GET'}, function () return {body = "OK"} end)
    local r = http_client.get('http://127.0.0.1:12345/from')
    t.assert_equals(r.status, 200)
    t.assert_equals(r.body, "OK")
    server:stop()
end

g.test_request_method = function()
    local server, router = cfgserv()
    server:start()

    router:route({path = '/method_old', method = 'GET'}, function (req) return  {body = req.method} end)
    local r = http_client.get('http://127.0.0.1:12345/method_old')
    t.assert_equals(r.body, "GET")
    server:stop()
end

g.test_request_path = function()
    local server, router = cfgserv()
    server:set_router(router)
    server:start()

    router:route({path = '/path', method = 'GET'}, function (req) return  {body = req.path} end)
    local r = http_client.get('http://127.0.0.1:12345/path')
    t.assert_equals(r.body, "/path")
    server:stop()
end

g.test_request_query = function()
    local server, router = cfgserv()
    server:set_router(router)
    server:start()

    router:route({path = '/query', method = 'GET'}, function (req) return  {body = req.query} end)
    local r = http_client.get('http://127.0.0.1:12345/query?a=1&b=1&c=1')
    t.assert_equals(r.body, "a=1&b=1&c=1")
    server:stop()
end

g.test_request_proto = function()
    local server, router = cfgserv()
    server:set_router(router)
    server:start()

    router:route({path = '/proto', method = 'GET'}, function (req) return  {body = json.encode(req.proto)} end)
    local r = http_client.get('http://127.0.0.1:12345/proto')
    t.assert_equals(r.body, "[1,1]")
    server:stop()
end

g.test_request_peer = function()
    local server, router = cfgserv()
    server:set_router(router)
    server:start()

    router:route({path = '/peer', method = 'GET'}, function (req) return  {body = json.encode(req.peer)} end)
    local r = http_client.get('http://127.0.0.1:12345/peer')
    local resp = json.decode(r.body)
    t.assert_is_not(resp.host, nil)
    t.assert_is_not(resp.family, nil)
    t.assert_is_not(resp.port, nil)
    server:stop()
end

g.test_request_headers = function()
    local server, router = cfgserv()
    server:set_router(router)
    server:start()

    router:route({path = '/headers', method = 'GET'}, function (req) return  {body = json.encode(req.headers)} end)
    local r = http_client.get('http://127.0.0.1:12345/headers')
    local resp = json.decode(r.body)
    t.assert_is_not(resp.accept, nil)
    t.assert_is_not(resp.connection, nil)
    t.assert_is_not(resp.host, nil)
    server:stop()
end



g.test_server_requests = function()
    local httpd, router = cfgserv()
    httpd:start()

    local r = http_client.get('http://127.0.0.1:12345/test')
    t.assert_equals(r.status, 200, '/test code')

    t.assert_equals(r.proto[1], 1, '/test http 1.1')
    t.assert_equals(r.proto[2], 1, '/test http 1.1')
    t.assert_equals(r.reason, 'Ok', '/test reason')
    t.assert_equals(string.match(r.body, 'title: 123'), 'title: 123', '/test body')

    r = http_client.get('http://127.0.0.1:12345/test404')
    t.assert_equals(r.status, 404, '/test404 code')
    -- broken in built-in tarantool/http
    --t.assert_equals(r.reason, 'Not found', '/test404 reason')

    r = http_client.get('http://127.0.0.1:12345/absent')
    t.assert_equals(r.status, 500, '/absent code')
    --t.assert_equals(r.reason, 'Internal server error', '/absent reason')
    t.assert_equals(string.match(r.body, 'load module'), 'load module', '/absent body')

    r = http_client.get('http://127.0.0.1:12345/ctxaction')
    t.assert_equals(r.status, 200, '/ctxaction code')
    t.assert_equals(r.reason, 'Ok', '/ctxaction reason')
    t.assert_equals(string.match(r.body, 'Hello, Tarantool'), 'Hello, Tarantool',
                   '/ctxaction body')
    t.assert_equals(string.match(r.body, 'action: action'), 'action: action',
                   '/ctxaction body action')
    t.assert_equals(string.match(r.body, 'controller: module[.]controller'),
                   'controller: module.controller', '/ctxaction body controller')

    r = http_client.get('http://127.0.0.1:12345/ctxaction.invalid')
    t.assert_equals(r.status, 404, '/ctxaction.invalid code') -- WTF?
    --t.assert_equals(r.reason, 'Not found', '/ctxaction.invalid reason')
    --t.assert_equals(r.body, '', '/ctxaction.invalid body')

    r = http_client.get('http://127.0.0.1:12345/hello.html')
    t.assert_equals(r.status, 200, '/hello.html code')
    t.assert_equals(r.reason, 'Ok', '/hello.html reason')
    t.assert_equals(string.match(r.body, 'static html'), 'static html',
                   '/hello.html body')

    r = http_client.get('http://127.0.0.1:12345/absentaction')
    t.assert_equals(r.status, 500, '/absentaction 500')
    --t.assert_equals(r.reason, 'Internal server error', '/absentaction reason')
    t.assert_equals(string.match(r.body, 'contain function'), 'contain function',
                   '/absentaction body')

    r = http_client.get('http://127.0.0.1:12345/helper')
    t.assert_equals(r.status, 200, 'helper 200')
    t.assert_equals(r.reason, 'Ok', 'helper reason')
    t.assert_equals(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')

    r = http_client.get('http://127.0.0.1:12345/helper?abc')
    t.assert_equals(r.status, 200, 'helper?abc 200')
    t.assert_equals(r.reason, 'Ok', 'helper?abc reason')
    t.assert_equals(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')

    router:route({path = '/die', file = 'helper.html.el'},
        function() error(123) end )

    r = http_client.get('http://127.0.0.1:12345/die')
    t.assert_equals(r.status, 500, 'die 500')
    --t.assert_equals(r.reason, 'Internal server error', 'die reason')

    router:route({ path = '/info' }, function(cx)
            return cx:render({ json = cx.peer })
    end)

    r = json.decode(http_client.get('http://127.0.0.1:12345/info').body)
    t.assert_equals(r.host, '127.0.0.1', 'peer.host')
    t.assert_type(r.port, 'number')

    r = router:route({method = 'POST', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'POST = ' .. tx:read()})
    end)
    t.assert_type(r, 'table')


    -- GET/POST at one route
    r = router:route({method = 'POST', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'POST = ' .. tx:read()})
    end)
    t.assert_type(r, 'table')

    r = router:route({method = 'GET', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'GET = ' .. tx:read()})
    end )
    t.assert_type(r, 'table')

    r = router:route({method = 'DELETE', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'DELETE = ' .. tx:read()})
    end )
    t.assert_type(r, 'table')

    r = router:route({method = 'PATCH', path = '/dit', file = 'helper.html.el'},
        function(tx)
            return tx:render({text = 'PATCH = ' .. tx:read()})
    end )
    t.assert_type(r, 'table')

    -- TODO
    r = http_client.request('POST', 'http://127.0.0.1:12345/dit', 'test')
    t.assert_equals(r.body, 'POST = test', 'POST reply')

    r = http_client.request('GET', 'http://127.0.0.1:12345/dit')
    t.assert_equals(r.body, 'GET = ', 'GET reply')

    r = http_client.request('DELETE', 'http://127.0.0.1:12345/dit', 'test1')
    t.assert_equals(r.body, 'DELETE = test1', 'DELETE reply')

    r = http_client.request('PATCH', 'http://127.0.0.1:12345/dit', 'test2')
    t.assert_equals(r.body, 'PATCH = test2', 'PATCH reply')

    router:route({path = '/chunked'}, function(self)
            return self:iterate(ipairs({'chunked', 'encoding', 't\r\nest'}))
    end)

    -- http client currently doesn't support chunked encoding
    r = http_client.get('http://127.0.0.1:12345/chunked')
    t.assert_equals(r.status, 200, 'chunked 200')
    t.assert_equals(r.headers['transfer-encoding'], 'chunked', 'chunked headers')
    t.assert_equals(r.body, 'chunkedencodingt\r\nest', 'chunked body')

    -- get cookie
    router:route({path = '/receive_cookie'}, function(req)
            local foo = req:cookie('foo')
            local baz = req:cookie('baz')
            return req:render({
                    text = ('foo=%s; baz=%s'):format(foo, baz)
            })
    end)
    r = http_client.get('http://127.0.0.1:12345/receive_cookie', {
                                  headers = {
                                      cookie = 'foo=bar; baz=feez',
                                  }
    })
    t.assert_equals(r.status, 200, 'status')
    t.assert_equals(r.body, 'foo=bar; baz=feez', 'body')

    -- cookie
    router:route({path = '/cookie'}, function(req)
            local resp = req:render({text = ''})
            resp:setcookie({ name = 'test', value = 'tost',
                             expires = '+1y', path = '/abc' })
            resp:setcookie({ name = 'xxx', value = 'yyy' })
            return resp
    end)
    r = http_client.get('http://127.0.0.1:12345/cookie')
    t.assert_equals(r.status, 200, 'status')
    t.assert(r.headers['set-cookie'] ~= nil, "header")


    -- request object with GET method
    router:route({path = '/check_req_properties'}, function(req)
            return {
                headers = {},
                body = json.encode({
                        headers = req.headers,
                        method = req.method,
                        path = req.path,
                        query = req.query,
                        proto = req.proto,
                        query_param_bar = req:query_param('bar'),
                }),
                status = 200,
            }
    end)
    r = http_client.get(
        'http://127.0.0.1:12345/check_req_properties?foo=1&bar=2', {
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
    t.assert_equals(r.status, 200, 'status')

    parsed_body = json.decode(r.body)
    t.assert_equals(parsed_body.request_line, 'POST /check_req_methods_for_json HTTP/1.1', 'req.request_line')
    t.assert_equals(parsed_body.read_cached, '{"kind": "json"}', 'json req:read_cached()')
    t.assert_equals(parsed_body.json, {kind = "json"}, 'req:json()')
    t.assert_equals(parsed_body.post_param_for_kind, "json", 'req:post_param()')

    r = http_client.post(
        'http://127.0.0.1:12345/check_req_methods',
        'hello mister'
    )
    t.assert_equals(r.status, 200, 'status')
    parsed_body = json.decode(r.body)
    t.assert_equals(parsed_body.read_cached, 'hello mister', 'non-json req:read_cached()')

    if is_builtin_test() then
        router:route({ path = '/post', method = 'POST'}, function(req)
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
        r = http_client.post('http://127.0.0.1:12345/post', body)
        t.assert_equals(r.status, 200, 'status')
        t.assert_equals(json.decode(r.body), { 541,10,10,458,1375,0,0 },
                       'req:read() results')
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

    -- prioritization of more specific routes
    router:route({method = 'GET', path = '*stashname'}, function(_)
            return {
                status = 200,
                body = 'GET *',
            }
    end)
    r = http_client.get('http://127.0.0.1:12345/a/b/c')
    t.assert_equals(r.status, 200, '/a/b/c request returns 200')
    t.assert_equals(r.body, 'GET *', 'GET * matches')

    router:route({method = 'ANY', path = '/a/:foo/:bar'}, function(_)
            return {
                status = 200,
                body = 'ANY /a/:foo/:bar',
            }
    end)
    r = http_client.get('http://127.0.0.1:12345/a/b/c')
    t.assert_equals(r.status, 200, '/a/b/c request returns 200')
    t.assert_equals(
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
    t.assert(ok, 'hello_world middleware added successfully')

    local middlewares_ordered = router.middleware:ordered()
    t.assert_equals(#middlewares_ordered, 1, 'one middleware is registered')

    ok = router:use(add_helloworld_before_to_response, {
                        name = 'hello_world_before',
                        path = '/.*',
                        method = 'ANY',
                        before = 'hello_world',
    })
    t.assert(ok, 'hello_world_before middleware added successfully')

    middlewares_ordered = router.middleware:ordered()
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
    t.assert_equals(r.status, 200, 'status')
    require('log').info('DEBUG: /fruits/apple response: %s', r.body)
    local parsed_body = json.decode(r.body)
    t.assert_equals(parsed_body.kind, 'apple', 'body is correct')
    t.assert_equals(parsed_body.message, 'hello world! (before)', 'hello_world middleware invoked last')

    local function swap_orange_and_apple(req)
        local path_info = req.path
        local log = require('log')
        log.info('swap_orange_and_apple: path_info = %s', path_info)

        if path_info == '/fruits/orange' then
            req.path = '/fruits/apple'
        elseif path_info == '/fruits/apple' then
            req.path = '/fruits/orange'
        end

        return req:next()
    end

    ok = router:use(swap_orange_and_apple, {
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

    httpd:stop()
end
