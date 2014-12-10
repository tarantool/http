#!/usr/bin/env tarantool

package.path = package.path..";../?.lua"
package.cpath = package.cpath..";../?.so"

tap = require('tap')
http_lib = require('http.lib')
http_client = require('http.client')
http_server = require('http.server')
json = require('json')
yaml = require 'yaml'
local urilib = require('uri')

local test = tap.test("http")
test:plan(8)
test:test("split_uri", function(test)
    test:plan(65)
    local function check(uri, rhs)
        local lhs = urilib.parse(uri)
        local extra = { lhs = lhs, rhs = rhs }
        if lhs.query == '' then
            lhs.query = nil
        end
        test:is(lhs.scheme, rhs.scheme, uri.." scheme", extra)
        test:is(lhs.host, rhs.host, uri.." host", extra)
        test:is(lhs.service, rhs.service, uri.." service", extra)
        test:is(lhs.path, rhs.path, uri.." path", extra)
        test:is(lhs.query, rhs.query, uri.." query", extra)
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
end)

test:test("template", function(test)
    test:plan(3)
    test:is(http_lib.template("<% for i = 1, cnt do %> <%= abc %> <% end %>",
        {abc = '1 <3>&" ', cnt = 3}),
        ' 1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;   1 &lt;3&gt;&amp;&quot;  ',
        "tmpl1")
    test:is(http_lib.template("<% for i = 1, cnt do %> <%= ab %> <% end %>",
        {abc = '1 <3>&" ', cnt = 3}),
        ' nil  nil  nil ', "tmpl2")
    local r, msg = pcall(http_lib.template, "<% ab() %>", {ab = '1'})
    test:ok(r == false and msg:match("call local 'ab'") ~= nil, "bad template")
end)

test:test('parse_request', function(test)
    test:plan(6)

    test:isdeeply(http_server.parse_request('abc'),
        { error = 'Broken request line', headers = {} }, 'broken request')



    test:is(
        http_server.parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").path,
        '/',
        'path'
    )
    test:isdeeply(
        http_server.parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").proto,
        {1,1},
        'proto'
    )
    test:isdeeply(
        http_server.parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").headers,
        {host = 's.com'},
        'host'
    )
    test:isdeeply(
        http_server.parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").method,
        'GET',
        'method'
    )
    test:isdeeply(
        http_server.parse_request("GET / HTTP/1.1\nHost: s.com\r\n\r\n").query,
        '',
        'query'
    )
end)

test:test("http request", function(test)
    test:plan(11)
    local r = http_client.get("http://tarantool.org/")
    test:is(r.status, 200, 'mail.ru 200')
    test:is(r.proto[1], 1, 'mail.ru http 1.1')
    test:is(r.proto[2], 1, 'mail.ru http 1.1')
    test:ok(r.body:match("<(html)") ~= nil, "mail.ru is html", r)
    test:ok(tonumber(r.headers["content-length"]) > 0,
        "mail.ru content-length > 0")
    test:is(http_client.get("http://localhost:88/").status, 595, 'timeout')
    local r = http_client.get("http://go.mail.ru/search?fr=main&q=tarantool")
    test:is(r.status, 200, 'go.mail.ru 200')
    test:is(r.proto[1], 1, 'go.mail.ru http 1.1')
    test:is(r.proto[2], 1, 'go.mail.ru http 1.1')
    test:ok(r.body:match("<(html)") ~= nil, "go.mail.ru is html", r)
    test:is(http_client.request("GET", "http://tarantool.org/").status, 200, 'alias')
end)


test:test('params', function(test)
    test:plan(6)
    test:isdeeply(http_lib.params(), {}, 'nil string')
    test:isdeeply(http_lib.params(''), {}, 'empty string')
    test:isdeeply(http_lib.params('a'), {a = ''}, 'separate literal')
    test:isdeeply(http_lib.params('a=b'), {a = 'b'}, 'one variable')
    test:isdeeply(http_lib.params('a=b&b=cde'), {a = 'b', b = 'cde'}, 'some')
    test:isdeeply(http_lib.params('a=b&b=cde&a=1'),
        {a = { 'b', '1' }, b = 'cde'}, 'array')
end)

local function cfgserv()
    local httpd = http_server.new('127.0.0.1', 12345, { app_dir = 'test' })
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
        :helper('helper_title', function(self, a) return 'Hello, ' .. a end)
        :route({path = '/helper', file = 'helper.html.el'})
        :route({ path = '/test', file = 'test.html.el' },
            function(cx) cx:render({ title = 'title: 123' }) end)
    return httpd
end

test:test("server url match", function(test)
    test:plan(17)
    local httpd = cfgserv()
    test:istable(httpd, "httpd object")
    test:isnil(httpd:match('GET', '/'))
    test:is(httpd:match('GET', '/abc').endpoint.path, "/abc", "/abc")
    test:is(#httpd:match('GET', '/abc').stash, 0, "/abc")
    test:is(httpd:match('GET', '/abc/123').endpoint.path, "/abc/:cde", "/abc/123")
    test:is(httpd:match('GET', '/abc/123').stash.cde, "123", "/abc/123")
    test:is(httpd:match('GET', '/abc/123/122').endpoint.path, "/abc/:cde/:def",
        "/abc/123/122")
    test:is(httpd:match('GET', '/abc/123/122').stash.def, "122",
        "/abc/123/122")
    test:is(httpd:match('GET', '/abc/123/122').stash.cde, "123",
        "/abc/123/122")
    test:is(httpd:match('GET', '/abc_123-122').endpoint.path, "/abc_:cde_def",
        "/abc_123-122")
    test:is(httpd:match('GET', '/abc_123-122').stash.cde_def, "123-122",
        "/abc_123-122")
    test:is(httpd:match('GET', '/abc-123-def').endpoint.path, "/abc-:cde-def",
        "/abc-123-def")
    test:is(httpd:match('GET', '/abc-123-def').stash.cde, "123",
        "/abc-123-def")
    test:is(httpd:match('GET', '/aba-123-dea/1/2/3').endpoint.path,
        "/aba*def", '/aba-123-dea/1/2/3')
    test:is(httpd:match('GET', '/aba-123-dea/1/2/3').stash.def,
        "-123-dea/1/2/3", '/aba-123-dea/1/2/3')
    test:is(httpd:match('GET', '/abb-123-dea/1/2/3/cde').endpoint.path,
        "/abb*def/cde", '/abb-123-dea/1/2/3/cde')
    test:is(httpd:match('GET', '/abb-123-dea/1/2/3/cde').stash.def,
        "-123-dea/1/2/3", '/abb-123-dea/1/2/3/cde')
end)

test:test("server url_for", function(test)
    test:plan(5)
    local httpd = cfgserv()
    test:is(httpd:url_for('abcdef'), '/abcdef', '/abcdef')
    test:is(httpd:url_for('test'), '/abc//', '/abc//')
    test:is(httpd:url_for('test', { cde = 'cde_v', def = 'def_v' }),
        '/abc/cde_v/def_v', '/abc/cde_v/def_v')
    test:is(httpd:url_for('star', { def = '/def_v' }),
        '/abb/def_v/cde', '/abb/def_v/cde')
    test:is(httpd:url_for('star', { def = '/def_v' }, { a = 'b', c = 'd' }),
        '/abb/def_v/cde?a=b&c=d', '/abb/def_v/cde?a=b&c=d')
end)

test:test("server requests", function(test)
    test:plan(41)
    local httpd = cfgserv()
    httpd:start()
    local r = http_client.get('http://127.0.0.1:12345/test')
    test:is(r.status, 200, 'testserv 200')
    test:is(r.proto[1], 1, 'testserv http 1.1')
    test:is(r.proto[2], 1, 'testserv http 1.1')
    test:is(r.reason, 'Ok', 'testserv reason')
    test:is(string.match(r.body, 'title: 123'), 'title: 123', 'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/test1')
    test:is(r.status, 404, 'testserv 404')
    test:is(r.reason, 'Not found', 'testserv reason')

    local r = http_client.get('http://127.0.0.1:12345/absent')
    test:is(r.status, 500, 'testserv 500')
    test:is(r.reason, 'Internal server error', 'testserv reason')
    test:is(string.match(r.body, 'load module'), 'load module', 'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/ctxaction')
    test:is(r.status, 200, 'testserv 200')
    test:is(r.reason, 'Ok', 'testserv reason')
    test:is(string.match(r.body, 'Hello, Tarantool'), 'Hello, Tarantool',
        'testserv body')
    test:is(string.match(r.body, 'action: action'), 'action: action',
        'testserv body action')
    test:is(string.match(r.body, 'controller: module[.]controller'),
        'controller: module.controller', 'testserv body controller')

    local r = http_client.get('http://127.0.0.1:12345/ctxaction.js')
    test:is(r.status, 200, 'testserv 200')
    test:is(r.reason, 'Ok', 'testserv reason')
    test:is(string.match(r.body, 'json template js'), 'json template js',
        'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/ctxaction.jsonaaa')
    test:is(r.status, 500, 'testserv 500') -- WTF?
    test:is(r.reason, 'Internal server error', 'testserv reason')
    test:is(string.match(r.body, 'No such file'), 'No such file',
        'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/hello.html')
    test:is(r.status, 200, 'testserv 200')
    test:is(r.reason, 'Ok', 'testserv reason')
    test:is(string.match(r.body, 'static html'), 'static html',
        'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/absentaction')
    test:is(r.status, 500, 'testserv 500')
    test:is(r.reason, 'Internal server error', 'testserv reason')
    test:is(string.match(r.body, 'contain function'), 'contain function',
        'testserv body')

    local r = http_client.get('http://127.0.0.1:12345/helper')
    test:is(r.status, 200, 'helper 200')
    test:is(r.reason, 'Ok', 'helper reason')
    test:is(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')

    local r = http_client.get('http://127.0.0.1:12345/helper?abc')
    test:is(r.status, 200, 'helper?abc 200')
    test:is(r.reason, 'Ok', 'helper?abc reason')
    test:is(string.match(r.body, 'Hello, world'), 'Hello, world', 'helper body')

    httpd:route({path = '/die', file = 'helper.html.el'},
        function() error(123) end )

    local r = http_client.get('http://127.0.0.1:12345/die')
    test:is(r.status, 500, 'die 500')
    test:is(r.reason, 'Internal server error', 'die reason')

    httpd:route({ path = '/info' }, function(cx)
        cx:render({ json = cx.req.peer })
    end)
    local r = json.decode(http_client.get('http://127.0.0.1:12345/info').body)
    test:is(r.host, '127.0.0.1', 'peer.host')
    test:isnumber(r.port, 'peer.port')

    local r = httpd:route({method = 'POST', path = '/dit', file = 'helper.html.el'}, function(tx) tx:render({text = 'POST = ' .. tx.req.body}) end )
    test:istable(r, ':route')


test:test('GET/POST at one route', function(test)

    test:plan(4)
    r = httpd:route({method = 'POST', path = '/dit', file = 'helper.html.el'}, function(tx) tx:render({text = 'POST = ' .. tx.req.body}) end )

    test:istable(r, 'add POST method')


    r = httpd:route({method = 'GET', path = '/dit', file = 'helper.html.el'}, function(tx) tx:render({text = 'GET = ' .. tx.req.body}) end )
    test:istable(r, 'add GET method')

    r = http_client.request('POST', 'http://127.0.0.1:12345/dit', 'test')
    test:is(r.body, 'POST = test', 'POST reply')

    r = http_client.request('GET', 'http://127.0.0.1:12345/dit')
    test:is(r.body, 'GET = ', 'GET reply')
end)

    httpd:route({path = '/chunked'}, function(self)
        return self:iterate(ipairs({'chunked', 'encoding', 'test'}))
    end)

    -- http client currently doesn't support chunked encoding
    local r = http_client.get('http://127.0.0.1:12345/chunked')
    test:is(r.status, 200, 'chunked 200')
    test:is(r.body, '7\r\nchunked\r\n8\r\nencoding\r\n4\r\ntest\r\n0\r\n\r\n',
        'chunked body')

    httpd:stop()
end)

test:check()
os.exit(0)
